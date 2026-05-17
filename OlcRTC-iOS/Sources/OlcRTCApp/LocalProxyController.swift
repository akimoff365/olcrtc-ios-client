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

    private let watchdogInitialDelayNanoseconds: UInt64 = 20_000_000_000
    private var watchdogIntervalNanoseconds: UInt64 = 45_000_000_000
    private let watchdogMaxIntervalNanoseconds: UInt64 = 300_000_000_000
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

    var canRestart: Bool {
        activeProfile != nil && status != .stopped && status != .starting && status != .restarting
    }

    var logText: String {
        logs.map(\.line).joined(separator: "\n")
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
        watchdogIntervalNanoseconds = 45_000_000_000
        appendLog(.info, "Starting profile: \(profile.displayName)", context: ["network": networkName])

        let maxAttempts = 3
        var lastError: Error?
        
        for attempt in 1...maxAttempts {
            do {
                let requestedPort = loadPreferredPort()
                let startResult = try await Task.detached(priority: .userInitiated) {
                    let credentials = SocksCredentials.load()
                    OlcRTCEngine.stop()
                    Thread.sleep(forTimeInterval: 0.35)
                    let port = PortAvailability.nextAvailableTCPPort(startingAt: requestedPort)
                    try OlcRTCEngine.start(profile: profile, socksPort: port, credentials: credentials)
                    return EngineStartResult(port: port, credentials: credentials)
                }.value
                try BackgroundKeepAlive.shared.start()

                socksPort = startResult.port
                credentials = startResult.credentials
                if startResult.port != requestedPort {
                    appendLog(.warning, "SOCKS port \(requestedPort) was busy; using \(startResult.port)")
                }

                guard await OlcRTCEngine.checkTunnelConnectivity(port: startResult.port, credentials: startResult.credentials) else {
                    throw ControllerError.tunnelConnectivityFailed
                }

                saveSuccessfulPort(startResult.port)
                activeProfile = profile
                reconnectCount = 0
                healthState = .healthy
                status = .running
                lastMessage = "Маршрут проверен. Теперь можно включать профиль во внешнем VPN-клиенте."
                startPathMonitor()
                startWatchdog()
                appendLog(.success, "Tunnel CONNECT passed on 127.0.0.1:\(startResult.port)")
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
        appendLog(.error, "All start attempts failed")
    }

    func restartSocks() {
        guard let activeProfile else {
            return
        }

        scheduleRestart(profile: activeProfile, reason: "Перезапускаю локальный SOCKS...", delayNanoseconds: 0)
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
        
        reconnectTask?.cancel()
        reconnectTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        networkChangeTask?.cancel()
        networkChangeTask = nil
        stopWatchdog()
        stopEngineInBackground()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
        reconnectCount = 0
        networkName = "Нет"
        healthState = .idle
        consecutiveHealthFailures = 0
        lastPathSignature = nil
        watchdogIntervalNanoseconds = 45_000_000_000
        stopPathMonitor()
        status = .stopped
        lastMessage = nil
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
                let credentials = SocksCredentials.load()
                OlcRTCEngine.stop()
                Thread.sleep(forTimeInterval: 0.9)
                let port = PortAvailability.nextAvailableTCPPort(startingAt: requestedPort)
                try OlcRTCEngine.start(profile: profile, socksPort: port, credentials: credentials)
                return EngineStartResult(port: port, credentials: credentials)
            }.value
            try BackgroundKeepAlive.shared.start()

            socksPort = startResult.port
            credentials = startResult.credentials
            if startResult.port != requestedPort {
                appendLog(.warning, "SOCKS port \(requestedPort) was busy; using \(startResult.port)")
            }

            guard await OlcRTCEngine.checkTunnelConnectivity(port: startResult.port, credentials: startResult.credentials) else {
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
        networkName = snapshot.name

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

        // Debounce network changes
        networkChangeTask?.cancel()
        networkChangeTask = Task { [weak self, snapshot] in
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
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
        
        appendLog(.warning, "Network change broke the tunnel")
        enterExternalTunnelRecovery("Network changed to \(snapshot.name)")
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
                let interval = await self?.watchdogIntervalNanoseconds ?? 45_000_000_000
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
        
        // Restore normal watchdog interval if running
        if status == .running {
            watchdogIntervalNanoseconds = 45_000_000_000
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
            watchdogIntervalNanoseconds = 120_000_000_000 // 2 minutes
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
            enterExternalTunnelRecovery("Foreground check failed")
        }
    }

    private func runWatchdogTick() async {
        guard status == .running,
              let activeProfile,
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
            watchdogIntervalNanoseconds = 45_000_000_000
            if previousHealth != .healthy {
                appendLog(.success, "Watchdog: tunnel CONNECT restored")
            }
            return
        }

        consecutiveHealthFailures += 1
        healthState = .unhealthy
        // Increase interval on failure
        watchdogIntervalNanoseconds = min(watchdogIntervalNanoseconds * 2, watchdogMaxIntervalNanoseconds)
        appendLog(.warning, "Watchdog: tunnel CONNECT failed (\(consecutiveHealthFailures)/2), next check in \(watchdogIntervalNanoseconds / 1_000_000_000)s")

        if consecutiveHealthFailures >= 2 {
            appendLog(.warning, "Watchdog: restarting local SOCKS after repeated failures")
            scheduleRestart(profile: activeProfile, reason: "Watchdog перезапускает SOCKS: тестовый CONNECT не проходит.", delayNanoseconds: 0)
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
        stopWatchdog()
        stopEngineInBackground()
        healthState = .unhealthy
        consecutiveHealthFailures = 0
        watchdogIntervalNanoseconds = 45_000_000_000
        status = .needsTunnelRestart
        lastMessage = "Сеть изменилась. Выключи туннель во внешнем VPN-клиенте, нажми «Перезапустить», затем включи туннель обратно."
        appendLog(.warning, "\(reason). Local SOCKS stopped; external VPN tunnel restart is required.")
    }

    private func stopEngineInBackground() {
        Task.detached(priority: .utility) {
            OlcRTCEngine.stop()
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
        let signature = "\(statusName)|\(path.isExpensive)|\(path.isConstrained)|\(visibleName)"
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
