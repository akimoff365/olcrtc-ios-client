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

    let socksPort = 18080
    private let watchdogInitialDelayNanoseconds: UInt64 = 20_000_000_000
    private let watchdogIntervalNanoseconds: UInt64 = 45_000_000_000
    private let pathQueue = DispatchQueue(label: "ru.pasklove.olcrtc.path-monitor")
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?
    private var reconnectTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var foregroundCheckTask: Task<Void, Never>?
    private var consecutiveHealthFailures = 0
    private var lastForegroundSuccessLogDate: Date?

    var canRestart: Bool {
        activeProfile != nil && status != .stopped && status != .starting && status != .restarting
    }

    var logText: String {
        logs.map(\.line).joined(separator: "\n")
    }

    func start(profile: OlcRTCProfile) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        stopWatchdog()
        status = .starting
        lastMessage = nil
        lastPathSignature = nil
        networkName = "Проверка"
        healthState = .checking
        consecutiveHealthFailures = 0
        appendLog(.info, "Starting profile: \(profile.displayName)")

        do {
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                let credentials = SocksCredentials.load()
                OlcRTCEngine.stop()
                Thread.sleep(forTimeInterval: 0.35)
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort, credentials: credentials)
            }.value
            try BackgroundKeepAlive.shared.start()

            let currentCredentials = SocksCredentials.load()
            credentials = currentCredentials
            guard await OlcRTCEngine.checkTunnelConnectivity(port: socksPort, credentials: currentCredentials) else {
                throw ControllerError.tunnelConnectivityFailed
            }

            activeProfile = profile
            reconnectCount = 0
            healthState = .healthy
            status = .running
            lastMessage = "Маршрут проверен. Теперь можно включать профиль во внешнем VPN-клиенте."
            startPathMonitor()
            startWatchdog()
            appendLog(.success, "Tunnel CONNECT passed on 127.0.0.1:\(socksPort)")
        } catch {
            stopEngineInBackground()
            BackgroundKeepAlive.shared.stop()
            activeProfile = nil
            networkName = "Нет"
            healthState = .unhealthy
            status = .failed
            lastMessage = error.localizedDescription
            appendLog(.error, "Start failed: \(error.localizedDescription)")
        }
    }

    func restartSocks() {
        guard let activeProfile else {
            return
        }

        scheduleRestart(profile: activeProfile, reason: "Перезапускаю локальный SOCKS...", delayNanoseconds: 0)
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        foregroundCheckTask?.cancel()
        foregroundCheckTask = nil
        stopWatchdog()
        stopEngineInBackground()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
        reconnectCount = 0
        networkName = "Нет"
        healthState = .idle
        consecutiveHealthFailures = 0
        lastPathSignature = nil
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
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                let credentials = SocksCredentials.load()
                OlcRTCEngine.stop()
                Thread.sleep(forTimeInterval: 0.9)
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort, credentials: credentials)
            }.value
            try BackgroundKeepAlive.shared.start()

            let currentCredentials = SocksCredentials.load()
            credentials = currentCredentials
            guard await OlcRTCEngine.checkTunnelConnectivity(port: socksPort, credentials: currentCredentials) else {
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
        let interval = watchdogIntervalNanoseconds
        watchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: initialDelay)
            while !Task.isCancelled {
                await self?.runWatchdogTick()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    func appDidBecomeActive() {
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
        guard status == .running, let activeProfile else {
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
            if previousHealth != .healthy {
                appendLog(.success, "Watchdog: tunnel CONNECT restored")
            }
            return
        }

        consecutiveHealthFailures += 1
        healthState = .unhealthy
        appendLog(.warning, "Watchdog: tunnel CONNECT failed (\(consecutiveHealthFailures)/2)")

        if consecutiveHealthFailures >= 2 {
            appendLog(.warning, "Watchdog: restarting local SOCKS after repeated failures")
            scheduleRestart(profile: activeProfile, reason: "Watchdog перезапускает SOCKS: тестовый CONNECT не проходит.", delayNanoseconds: 0)
        }
    }

    private func appendLog(_ level: ProxyLogEntry.Level, _ message: String) {
        logs.insert(ProxyLogEntry(date: Date(), level: level, message: message), at: 0)
        if logs.count > 160 {
            logs.removeLast(logs.count - 160)
        }
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
        stopWatchdog()
        stopEngineInBackground()
        healthState = .unhealthy
        consecutiveHealthFailures = 0
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

private enum ControllerError: LocalizedError {
    case tunnelConnectivityFailed

    var errorDescription: String? {
        switch self {
        case .tunnelConnectivityFailed:
            return "SOCKS5 запустился, но через него не проходит тестовый CONNECT."
        }
    }
}
