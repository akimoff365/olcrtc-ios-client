import Foundation
import Network

@MainActor
final class LocalProxyController: ObservableObject {
    enum Status: String {
        case stopped = "Остановлен"
        case starting = "Запускается"
        case restarting = "Перезапуск"
        case running = "Работает"
        case needsTunnelRestart = "Нужен рестарт VPN"
        case failed = "Ошибка"
    }

    enum HealthState: String {
        case idle = "Нет"
        case checking = "Проверка"
        case healthy = "Маршрут OK"
        case unhealthy = "Нет маршрута"
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastMessage: String?
    @Published private(set) var activeProfile: OlcRTCProfile?
    @Published private(set) var reconnectCount = 0
    @Published private(set) var networkName = "Нет"
    @Published private(set) var credentials = SocksCredentials.load()
    @Published private(set) var healthState: HealthState = .idle
    @Published private(set) var logs: [ProxyLogEntry] = []
    @Published private(set) var socksPort = 18080
    @Published private(set) var isOperationInProgress = false
    @Published private(set) var metrics = ConnectionMetrics.load()
    @Published private(set) var readinessState: ReadinessState = .notReady
    @Published private(set) var readinessChecks: [ReadinessCheck] = []
    @Published private(set) var profilePingResults: [String: ProfilePingResult] = [:]

    private let watchdogInitialDelayNanoseconds: UInt64 = 90_000_000_000
    private let watchdogBaseIntervalNanoseconds: UInt64 = 60_000_000_000
    private var watchdogIntervalNanoseconds: UInt64 = 60_000_000_000
    private let watchdogMaxIntervalNanoseconds: UInt64 = 240_000_000_000
    private let watchdogFailureThreshold = 4
    private let pathQueue = DispatchQueue(label: "ru.pasklove.olcrtc.path-monitor")
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?
    private var reconnectTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var foregroundCheckTask: Task<Void, Never>?
    private var networkChangeTask: Task<Void, Never>?
    private var consecutiveHealthFailures = 0
    private var lastForegroundSuccessLogDate: Date?
    private var isInBackground = false
    private let portStorageKey = "olcrtc.last.successful.port"
    private var sessionStartTime: Date?
    private var lastNetworkType: String = "Нет"
    private var uptimeCheckTask: Task<Void, Never>?
    private var lastUptimeNotificationHours = 0

    var canRestart: Bool {
        activeProfile != nil && status != .stopped && status != .starting && status != .restarting
    }

    var logText: String {
        logs.map(\.line).joined(separator: "\n")
    }

    var sanitizedLogText: String {
        Self.sanitizeLogs(logText)
    }

    func start(profile: OlcRTCProfile) async {
        guard !isOperationInProgress else {
            appendLog(.warning, "Operation already in progress, ignoring start request")
            return
        }
        
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        
        reconnectTask?.cancel()
        reconnectTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        networkChangeTask?.cancel()
        networkChangeTask = nil
        stopWatchdog()
        status = .starting
        lastMessage = nil
        lastPathSignature = nil
        networkName = "Проверка"
        healthState = .checking
        consecutiveHealthFailures = 0
        watchdogIntervalNanoseconds = watchdogBaseIntervalNanoseconds
        appendLog(
            .info,
            "Starting profile: \(profile.displayName)",
            context: [
                "network": networkName,
                "readyTimeout": "\(profile.startReadyTimeoutMilliseconds / 1000)s"
            ]
        )

        let maxAttempts = profile.startAttemptCount
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                let requestedPort = loadPreferredPort()
                let startResult = try await Task.detached(priority: .userInitiated) {
                    try startEngine(profile: profile, requestedPort: requestedPort, stopDelay: 0.35)
                }.value
                try BackgroundKeepAlive.shared.start()

                socksPort = startResult.port
                credentials = startResult.credentials
                if startResult.port != requestedPort {
                    appendLog(.warning, "SOCKS port \(requestedPort) was busy; using \(startResult.port)")
                }
                appendRuntimeClientIDIfNeeded(startResult.runtimeClientID, profile: profile)

                guard await OlcRTCEngine.checkTunnelConnectivity(
                    port: startResult.port,
                    credentials: startResult.credentials,
                    timeoutNanoseconds: profile.tunnelCheckTimeoutNanoseconds
                ) else {
                    throw ControllerError.tunnelConnectivityFailed
                }

                saveSuccessfulPort(startResult.port)
                activeProfile = profile
                reconnectCount = 0
                healthState = .healthy
                status = .running
                lastMessage = "Маршрут проверен. Теперь можно включать профиль во внешнем VPN-клиенте."
                
                // Record metrics
                sessionStartTime = Date()
                metrics.recordEvent(.successfulStart)
                metrics.save()
                
                startPathMonitor()
                startWatchdog()
                startUptimeMonitor()
                appendLog(.success, "Tunnel CONNECT passed on 127.0.0.1:\(startResult.port)")
                
                // Send notification if app was in background
                if isInBackground {
                    NotificationManager.shared.send(.connectionRestored)
                }
                
                readinessState = .ready
                readinessChecks = []
                
                return
            } catch {
                lastError = error
                appendLog(.warning, "Start attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                
                if attempt < maxAttempts {
                    let delaySeconds = Double(attempt * attempt)
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
            }
        }
        
        stopEngineInBackground()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
        networkName = "Нет"
        healthState = .unhealthy
        status = .failed
        lastMessage = "Не удалось запустить после \(maxAttempts) попыток: \(lastError?.localizedDescription ?? "unknown")"
        
        // Record metrics
        metrics.recordEvent(.failedStart(reason: lastError?.localizedDescription ?? "unknown"))
        metrics.save()
        
        // Send notification
        NotificationManager.shared.send(
            .connectionFailed,
            context: lastError?.localizedDescription ?? "Не удалось запустить после \(maxAttempts) попыток"
        )
        
        appendLog(.error, "All start attempts failed")
    }

    func restartSocks() {
        guard let activeProfile else {
            return
        }
        
        // Record metrics
        metrics.recordEvent(.manualRestart)
        metrics.save()

        scheduleRestart(profile: activeProfile, reason: "Перезапускаю локальный SOCKS...", delayNanoseconds: 0)
    }
    
    func resetMetrics() {
        metrics.reset()
    }
    
    func checkReadiness() async {
        readinessState = .checking
        let result = await ReadinessChecker.check(
            status: status,
            healthState: healthState,
            socksPort: socksPort,
            credentials: credentials
        )
        readinessState = result.state
        readinessChecks = result.checks
        appendLog(.info, "Readiness check: \(result.state.rawValue)")
    }

    func pingProfile(_ profile: OlcRTCProfile) async {
        guard profilePingResults[profile.id]?.state.isChecking != true else {
            return
        }

        profilePingResults[profile.id] = ProfilePingResult(state: .checking, checkedAt: Date())
        appendLog(.info, "Profile ping started: \(profile.displayName)")

        if status != .stopped {
            guard activeProfile?.id == profile.id, status == .running else {
                let message = "Останови текущий профиль перед проверкой другого."
                profilePingResults[profile.id] = ProfilePingResult(state: .failed(message), checkedAt: Date())
                appendLog(.warning, "Profile ping blocked: another profile is active")
                return
            }

            let startedAt = Date()
            let passed = await OlcRTCEngine.checkGoogleConnectivity(
                port: socksPort,
                credentials: credentials,
                timeoutNanoseconds: profile.tunnelCheckTimeoutNanoseconds
            )
            let elapsed = Date().timeIntervalSince(startedAt)
            if passed {
                profilePingResults[profile.id] = ProfilePingResult(state: .success(elapsed), checkedAt: Date())
                appendLog(.success, "Profile ping passed: Google CONNECT in \(String(format: "%.1f", elapsed))s")
            } else {
                let message = "Google через текущий SOCKS не отвечает."
                profilePingResults[profile.id] = ProfilePingResult(state: .failed(message), checkedAt: Date())
                appendLog(.warning, "Profile ping failed: Google CONNECT did not pass")
            }
            return
        }

        guard !isOperationInProgress else {
            let message = "Сейчас идет другая операция. Повтори проверку через пару секунд."
            profilePingResults[profile.id] = ProfilePingResult(state: .failed(message), checkedAt: Date())
            appendLog(.warning, "Profile ping skipped: operation in progress")
            return
        }

        isOperationInProgress = true
        defer { isOperationInProgress = false }

        do {
            let requestedPort = loadPreferredPort()
            let startedAt = Date()
            let startResult = try await Task.detached(priority: .userInitiated) {
                try startEngine(profile: profile, requestedPort: requestedPort, stopDelay: 0.35)
            }.value

            let passed = await OlcRTCEngine.checkGoogleConnectivity(
                port: startResult.port,
                credentials: startResult.credentials,
                timeoutNanoseconds: profile.tunnelCheckTimeoutNanoseconds
            )
            await Task.detached(priority: .utility) {
                OlcRTCEngine.stop()
            }.value

            let elapsed = Date().timeIntervalSince(startedAt)
            if passed {
                profilePingResults[profile.id] = ProfilePingResult(state: .success(elapsed), checkedAt: Date())
                saveSuccessfulPort(startResult.port)
                appendLog(.success, "Profile ping passed: \(profile.displayName) -> Google in \(String(format: "%.1f", elapsed))s")
            } else {
                let message = "Профиль поднялся, но Google через туннель не отвечает."
                profilePingResults[profile.id] = ProfilePingResult(state: .failed(message), checkedAt: Date())
                appendLog(.warning, "Profile ping failed: Google CONNECT did not pass")
            }
        } catch {
            await Task.detached(priority: .utility) {
                OlcRTCEngine.stop()
            }.value
            profilePingResults[profile.id] = ProfilePingResult(state: .failed(error.localizedDescription), checkedAt: Date())
            appendLog(.error, "Profile ping failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard !isOperationInProgress else {
            appendLog(.warning, "Operation in progress, deferring stop")
            Task {
                while isOperationInProgress {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                await stop()
            }
            return
        }
        
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        
        // Record session end
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            metrics.recordEvent(.sessionEnd(duration: duration))
            metrics.recordEvent(.networkUsage(type: lastNetworkType, duration: duration))
            metrics.save()
            sessionStartTime = nil
        }
        
        reconnectTask?.cancel()
        reconnectTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        networkChangeTask?.cancel()
        networkChangeTask = nil
        uptimeCheckTask?.cancel()
        uptimeCheckTask = nil
        stopWatchdog()
        stopEngineInBackground()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
        reconnectCount = 0
        networkName = "Нет"
        healthState = .idle
        consecutiveHealthFailures = 0
        lastPathSignature = nil
        watchdogIntervalNanoseconds = watchdogBaseIntervalNanoseconds
        lastUptimeNotificationHours = 0
        stopPathMonitor()
        status = .stopped
        lastMessage = nil
        readinessState = .notReady
        readinessChecks = []
        appendLog(.info, "Stopped")
    }

    private func restartNow(profile: OlcRTCProfile, reason: String) async {
        guard activeProfile?.id == profile.id else {
            return
        }

        status = .restarting
        lastMessage = reason
        healthState = .checking
        appendLog(.info, reason)

        do {
            let requestedPort = socksPort
            let startResult = try await Task.detached(priority: .userInitiated) {
                try startEngine(profile: profile, requestedPort: requestedPort, stopDelay: 0.9)
            }.value
            try BackgroundKeepAlive.shared.start()

            socksPort = startResult.port
            credentials = startResult.credentials
            if startResult.port != requestedPort {
                appendLog(.warning, "SOCKS port \(requestedPort) was busy; using \(startResult.port)")
            }
            appendRuntimeClientIDIfNeeded(startResult.runtimeClientID, profile: profile)

            guard await OlcRTCEngine.checkTunnelConnectivity(
                port: startResult.port,
                credentials: startResult.credentials,
                timeoutNanoseconds: profile.tunnelCheckTimeoutNanoseconds
            ) else {
                throw ControllerError.tunnelConnectivityFailed
            }

            reconnectCount += 1
            consecutiveHealthFailures = 0
            healthState = .healthy
            status = .running
            lastMessage = "Маршрут снова проверен. Включи профиль во внешнем VPN-клиенте."
            appendLog(.success, "Tunnel CONNECT passed after restart")
        } catch {
            stopEngineInBackground()
            healthState = .unhealthy
            status = .failed
            lastMessage = "Не удалось перезапустить SOCKS: \(error.localizedDescription)"
            appendLog(.error, "Restart failed: \(error.localizedDescription)")
        }
    }

    private func startPathMonitor() {
        stopPathMonitor()

        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let snapshot = Self.snapshot(from: path)
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(snapshot)
            }
        }
        pathMonitor.start(queue: pathQueue)
        self.pathMonitor = pathMonitor
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePathUpdate(_ snapshot: NetworkPathSnapshot) {
        let previousNetwork = networkName
        networkName = snapshot.name
        lastNetworkType = snapshot.name

        if lastPathSignature == nil {
            lastPathSignature = snapshot.signature
            return
        }

        guard lastPathSignature != snapshot.signature else {
            return
        }

        lastPathSignature = snapshot.signature
        guard activeProfile != nil else {
            return
        }

        guard snapshot.isSatisfied else {
            if status == .running || status == .restarting {
                lastMessage = "Сеть переключается. Жду рабочее соединение..."
                appendLog(.warning, "Network is switching")
            }
            return
        }

        guard status == .running || status == .failed || status == .needsTunnelRestart else {
            return
        }
        
        // Record network change
        metrics.recordEvent(.networkChange(from: previousNetwork, to: snapshot.name))
        metrics.save()

        // Debounce network changes
        networkChangeTask?.cancel()
        networkChangeTask = Task { [weak self, snapshot] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.processNetworkChange(snapshot)
        }
    }
    
    private func processNetworkChange(_ snapshot: NetworkPathSnapshot) async {
        guard status == .running || status == .failed || status == .needsTunnelRestart else {
            return
        }
        
        // First check if connection is actually broken
        appendLog(.info, "Verifying connection after network change to \(snapshot.name)")
        let isAlive = await OlcRTCEngine.checkTunnelConnectivity(
            port: socksPort,
            credentials: credentials,
            timeoutNanoseconds: 6_000_000_000 // 6 seconds for network change check
        )
        
        if isAlive {
            appendLog(.success, "Network changed but tunnel still works")
            healthState = .healthy
            return
        }
        
        guard let activeProfile else {
            return
        }

        appendLog(.warning, "Network change broke the tunnel")
        metrics.recordEvent(.reconnect(reason: "Network change"))
        metrics.save()
        
        // Send notification if in background
        if isInBackground {
            NotificationManager.shared.send(
                .networkChanged,
                context: "Сеть изменилась на \(snapshot.name)"
            )
        }
        
        beginAutomaticNetworkRecovery(
            profile: activeProfile,
            reason: "Network changed to \(snapshot.name)"
        )
    }

    private func beginAutomaticNetworkRecovery(profile: OlcRTCProfile, reason: String) {
        reconnectTask?.cancel()
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        stopWatchdog()
        stopEngineInBackground()
        healthState = .checking
        consecutiveHealthFailures = 0
        watchdogIntervalNanoseconds = watchdogBaseIntervalNanoseconds
        status = .restarting
        lastMessage = "Сеть изменилась. Пробую восстановить SOCKS автоматически..."
        appendLog(.warning, "\(reason). Auto recovery started")

        reconnectTask = Task { [profile, reason] in
            await runAutomaticNetworkRecovery(profile: profile, reason: reason)
        }
    }

    private func runAutomaticNetworkRecovery(profile: OlcRTCProfile, reason: String) async {
        let delays: [UInt64] = [
            500_000_000,
            2_000_000_000,
            5_000_000_000,
            6_000_000_000,
            12_000_000_000,
            24_000_000_000,
            36_000_000_000
        ]

        for (index, delay) in delays.enumerated() {
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else {
                return
            }
            guard activeProfile?.id == profile.id, status != .stopped else {
                return
            }

            if isOperationInProgress {
                appendLog(.warning, "Network recovery attempt \(index + 1)/\(delays.count) delayed: operation in progress")
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            isOperationInProgress = true
            status = .restarting
            healthState = .checking
            lastMessage = "Восстановление после смены сети: попытка \(index + 1)/\(delays.count)..."
            appendLog(.info, "Network recovery attempt \(index + 1)/\(delays.count)")

            do {
                let requestedPort = socksPort
                let startResult = try await Task.detached(priority: .userInitiated) {
                    try startEngine(profile: profile, requestedPort: requestedPort, stopDelay: 1.2)
                }.value
                try BackgroundKeepAlive.shared.start()

                socksPort = startResult.port
                credentials = startResult.credentials
                if startResult.port != requestedPort {
                    appendLog(.warning, "SOCKS port \(requestedPort) was busy; using \(startResult.port)")
                }
                appendRuntimeClientIDIfNeeded(startResult.runtimeClientID, profile: profile)

                guard await OlcRTCEngine.checkTunnelConnectivity(
                    port: startResult.port,
                    credentials: startResult.credentials,
                    timeoutNanoseconds: profile.tunnelCheckTimeoutNanoseconds
                ) else {
                    throw ControllerError.tunnelConnectivityFailed
                }

                saveSuccessfulPort(startResult.port)
                reconnectCount += 1
                consecutiveHealthFailures = 0
                healthState = .healthy
                status = .running
                lastMessage = "Маршрут восстановлен после смены сети."
                readinessState = .checking
                startPathMonitor()
                startWatchdog()
                appendLog(.success, "Network recovery succeeded on attempt \(index + 1)")
                NotificationManager.shared.send(.connectionRestored)

                readinessState = .ready
                readinessChecks = []
                isOperationInProgress = false
                return
            } catch {
                stopEngineInBackground()
                BackgroundKeepAlive.shared.stop()
                healthState = .unhealthy
                appendLog(.warning, "Network recovery attempt \(index + 1)/\(delays.count) failed: \(error.localizedDescription)")
                isOperationInProgress = false
            }
        }

        markExternalTunnelRestartRequired("\(reason). Automatic recovery failed")
    }

    private func scheduleRestart(profile: OlcRTCProfile, reason: String, delayNanoseconds: UInt64) {
        reconnectTask?.cancel()
        reconnectTask = Task { [profile] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }
            await restartNow(profile: profile, reason: reason)
        }
    }

    private func startWatchdog() {
        stopWatchdog()
        let initialDelay = watchdogInitialDelayNanoseconds
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: initialDelay)
            while !Task.isCancelled {
                await self?.runWatchdogTick()
                // Use dynamic interval
                let interval = await self?.watchdogIntervalNanoseconds ?? self?.watchdogBaseIntervalNanoseconds ?? 25_000_000_000
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    func appDidBecomeActive() {
        isInBackground = false
        
        // Clear notifications when app becomes active
        NotificationManager.shared.clearBadge()
        
        // Restore normal watchdog interval if running
        if status == .running {
            watchdogIntervalNanoseconds = watchdogBaseIntervalNanoseconds
            if pathMonitor == nil {
                startPathMonitor()
            }
        }
        
        guard status == .running, foregroundCheckTask == nil else {
            return
        }

        foregroundCheckTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.verifyLocalSocksAfterForeground()
            await MainActor.run {
                self.foregroundCheckTask = nil
            }
        }
    }
    
    func appWillResignActive() {
        isInBackground = true
        // Increase watchdog interval in background to save battery
        if status == .running {
            do {
                try BackgroundKeepAlive.shared.start()
                BackgroundKeepAlive.shared.refresh()
            } catch {
                appendLog(.warning, "Background keep-alive failed: \(error.localizedDescription)")
            }
            watchdogIntervalNanoseconds = 60_000_000_000
            appendLog(.info, "Entering background, reducing watchdog frequency")
        }
    }

    private func verifyLocalSocksAfterForeground() async {
        guard status == .running else {
            return
        }

        let previousHealth = healthState
        if previousHealth != .healthy {
            healthState = .checking
        }
        let isAlive = await OlcRTCEngine.checkTunnelConnectivity(port: socksPort, credentials: credentials)
        guard status == .running else {
            return
        }

        if isAlive {
            healthState = .healthy
            logForegroundSuccessIfNeeded(previousHealth: previousHealth)
        } else {
            guard let activeProfile else {
                enterExternalTunnelRecovery("Foreground check failed")
                return
            }
            beginAutomaticNetworkRecovery(profile: activeProfile, reason: "Foreground check failed")
        }
    }

    private func runWatchdogTick() async {
        guard status == .running,
              activeProfile != nil,
              !isOperationInProgress else {
            return
        }

        let previousHealth = healthState
        if previousHealth != .healthy {
            healthState = .checking
        }
        let isAlive = await OlcRTCEngine.checkTunnelConnectivity(port: socksPort, credentials: credentials)

        guard status == .running else {
            return
        }

        if isAlive {
            consecutiveHealthFailures = 0
            healthState = .healthy
            // Reset interval on success
            watchdogIntervalNanoseconds = watchdogBaseIntervalNanoseconds
            if previousHealth != .healthy {
                appendLog(.success, "Watchdog: tunnel CONNECT restored")
            }
            return
        }

        consecutiveHealthFailures += 1
        healthState = .unhealthy
        // Increase interval on failure
        watchdogIntervalNanoseconds = min(watchdogIntervalNanoseconds * 2, watchdogMaxIntervalNanoseconds)
        appendLog(.warning, "Watchdog: tunnel CONNECT failed (\(consecutiveHealthFailures)/\(watchdogFailureThreshold)), next check in \(watchdogIntervalNanoseconds / 1_000_000_000)s")

        if consecutiveHealthFailures >= watchdogFailureThreshold {
            appendLog(.warning, "Watchdog: repeated failures; waiting for manual restart to avoid interrupting external VPN")
            metrics.recordEvent(.watchdogRestart)
            metrics.save()
            stopWatchdog()
            status = .needsTunnelRestart
            lastMessage = "Проверка маршрута не проходит. Если интернет во внешнем VPN пропал, выключи внешний VPN, затем перезапусти SOCKS."
        }
    }

    private func appendLog(_ level: ProxyLogEntry.Level, _ message: String, context: [String: String] = [:]) {
        var fullMessage = message
        if !context.isEmpty {
            let contextStr = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            fullMessage += " [\(contextStr)]"
        }
        
        logs.insert(ProxyLogEntry(date: Date(), level: level, message: fullMessage), at: 0)
        if logs.count > 200 {
            logs.removeLast(logs.count - 200)
        }
    }

    private static func sanitizeLogs(_ value: String) -> String {
        let patterns = [
            #"(?i)(keyhex|key|password|pass|socksPass)=([^,\]\s]+)"#: "$1=<redacted>",
            #"[A-Fa-f0-9]{64}"#: "<keyhex-redacted>",
            #"olcrtc://[^\s]+"#: "<olcrtc-uri-redacted>",
            #"socks5?://[^\s]+"#: "<socks-uri-redacted>"
        ]

        var sanitized = value
        for (pattern, replacement) in patterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return sanitized
    }
    
    private func loadPreferredPort() -> Int {
        let saved = UserDefaults.standard.integer(forKey: portStorageKey)
        return saved > 0 ? saved : 18080
    }
    
    private func saveSuccessfulPort(_ port: Int) {
        UserDefaults.standard.set(port, forKey: portStorageKey)
    }

    private func logForegroundSuccessIfNeeded(previousHealth: HealthState) {
        let now = Date()
        let shouldLog = previousHealth != .healthy
            || lastForegroundSuccessLogDate == nil
            || now.timeIntervalSince(lastForegroundSuccessLogDate ?? .distantPast) > 120

        guard shouldLog else {
            return
        }

        lastForegroundSuccessLogDate = now
        appendLog(.success, "Foreground check: tunnel CONNECT passed")
    }

    private func enterExternalTunnelRecovery(_ reason: String) {
        reconnectTask?.cancel()
        reconnectTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        networkChangeTask?.cancel()
        networkChangeTask = nil
        markExternalTunnelRestartRequired(reason)
    }

    private func markExternalTunnelRestartRequired(_ reason: String) {
        stopWatchdog()
        stopEngineInBackground()
        healthState = .unhealthy
        consecutiveHealthFailures = 0
        watchdogIntervalNanoseconds = watchdogBaseIntervalNanoseconds
        status = .needsTunnelRestart
        lastMessage = "Сеть изменилась. Выключи туннель во внешнем VPN-клиенте, нажми «Перезапустить», затем включи туннель обратно."
        
        // Send notification
        NotificationManager.shared.send(
            .actionRequired,
            context: "Требуется перезапуск SOCKS и внешнего VPN"
        )
        
        appendLog(.warning, "\(reason). Local SOCKS stopped; external VPN tunnel restart is required.")
    }

    private func appendRuntimeClientIDIfNeeded(_ runtimeClientID: String, profile: OlcRTCProfile) {
        guard runtimeClientID != profile.clientID else {
            return
        }

        appendLog(.info, "Runtime client id: \(runtimeClientID)")
    }

    private func stopEngineInBackground() {
        Task.detached(priority: .utility) {
            OlcRTCEngine.stop()
        }
    }
    
    private func startUptimeMonitor() {
        uptimeCheckTask?.cancel()
        lastUptimeNotificationHours = 0
        
        uptimeCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                // Check every hour
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour
                
                guard let self, let startTime = await self.sessionStartTime else {
                    continue
                }
                
                let uptime = Date().timeIntervalSince(startTime)
                let hours = Int(uptime / 3600)
                
                // Send notifications at 6, 12, 24 hours
                let milestones = [6, 12, 24]
                let lastNotified = await self.lastUptimeNotificationHours
                for milestone in milestones {
                    if hours >= milestone && lastNotified < milestone {
                        await MainActor.run {
                            self.lastUptimeNotificationHours = milestone
                            NotificationManager.shared.send(.longUptime(hours: milestone))
                            self.appendLog(.success, "Uptime milestone: \(milestone) hours")
                        }
                        break
                    }
                }
            }
        }
    }

    nonisolated private static func snapshot(from path: NWPath) -> NetworkPathSnapshot {
        let interfaces: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "Wi-Fi"),
            (.cellular, "LTE"),
            (.wiredEthernet, "Ethernet"),
            (.loopback, "Loopback"),
            (.other, "Другая")
        ]

        let names = interfaces
            .filter { path.usesInterfaceType($0.0) }
            .map(\.1)

        let statusName: String
        switch path.status {
        case .satisfied:
            statusName = "online"
        case .unsatisfied:
            statusName = "offline"
        case .requiresConnection:
            statusName = "waiting"
        @unknown default:
            statusName = "unknown"
        }

        let visibleName = names.isEmpty ? "Нет" : names.joined(separator: " + ")
        let physicalName = names.filter { $0 != "Другая" }.joined(separator: " + ")
        let stablePhysicalName = physicalName.isEmpty ? "Нет" : physicalName
        let signature = "\(statusName)|\(path.isExpensive)|\(stablePhysicalName)"
        return NetworkPathSnapshot(signature: signature, name: visibleName, isSatisfied: path.status == .satisfied)
    }
}

private struct NetworkPathSnapshot {
    let signature: String
    let name: String
    let isSatisfied: Bool
}

private struct EngineStartResult: Sendable {
    let port: Int
    let credentials: SocksCredentials
    let runtimeClientID: String
}

private func startEngine(profile: OlcRTCProfile, requestedPort: Int, stopDelay: TimeInterval) throws -> EngineStartResult {
    let credentials = SocksCredentials.load()
    let runtimeClientID = profile.runtimeClientID()
    OlcRTCEngine.stop()
    Thread.sleep(forTimeInterval: stopDelay)
    let port = PortAvailability.nextAvailableTCPPort(startingAt: requestedPort)
    try OlcRTCEngine.start(profile: profile, socksPort: port, credentials: credentials, runtimeClientID: runtimeClientID)
    return EngineStartResult(port: port, credentials: credentials, runtimeClientID: runtimeClientID)
}

private enum ControllerError: LocalizedError {
    case tunnelConnectivityFailed

    var errorDescription: String? {
        switch self {
        case .tunnelConnectivityFailed:
            return "SOCKS5 запустился, но через него не проходит тестовый CONNECT."
        }
    }
}
