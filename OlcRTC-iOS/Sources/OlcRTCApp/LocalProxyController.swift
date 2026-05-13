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

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastMessage: String?
    @Published private(set) var activeProfile: OlcRTCProfile?
    @Published private(set) var reconnectCount = 0
    @Published private(set) var networkName = "Нет"
    @Published private(set) var credentials = SocksCredentials.load()

    let socksPort = 18080
    private let pathQueue = DispatchQueue(label: "ru.pasklove.olcrtc.path-monitor")
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?
    private var reconnectTask: Task<Void, Never>?

    var canRestart: Bool {
        activeProfile != nil && status != .stopped && status != .starting && status != .restarting
    }

    func start(profile: OlcRTCProfile) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        status = .starting
        lastMessage = nil
        lastPathSignature = nil
        networkName = "Проверка"

        do {
            OlcRTCEngine.stop()
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                let credentials = SocksCredentials.load()
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort, credentials: credentials)
            }.value
            try BackgroundKeepAlive.shared.start()

            credentials = SocksCredentials.load()
            activeProfile = profile
            reconnectCount = 0
            status = .running
            lastMessage = "SOCKS5 готов: 127.0.0.1:\(socksPort), auth включен"
            startPathMonitor()
        } catch {
            OlcRTCEngine.stop()
            BackgroundKeepAlive.shared.stop()
            activeProfile = nil
            networkName = "Нет"
            status = .failed
            lastMessage = error.localizedDescription
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
        OlcRTCEngine.stop()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
        reconnectCount = 0
        networkName = "Нет"
        lastPathSignature = nil
        stopPathMonitor()
        status = .stopped
        lastMessage = nil
    }

    private func restartNow(profile: OlcRTCProfile, reason: String) async {
        guard activeProfile?.id == profile.id else {
            return
        }

        status = .restarting
        lastMessage = reason

        do {
            OlcRTCEngine.stop()
            try? await Task.sleep(nanoseconds: 600_000_000)
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                let credentials = SocksCredentials.load()
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort, credentials: credentials)
            }.value
            try BackgroundKeepAlive.shared.start()

            credentials = SocksCredentials.load()
            reconnectCount += 1
            status = .running
            lastMessage = "SOCKS перезапущен. Теперь включи профиль во внешнем VPN-клиенте."
        } catch {
            OlcRTCEngine.stop()
            status = .failed
            lastMessage = "Не удалось перезапустить SOCKS: \(error.localizedDescription)"
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
        guard let activeProfile else {
            return
        }

        guard snapshot.isSatisfied else {
            if status == .running || status == .restarting {
                lastMessage = "Сеть переключается. Жду рабочее соединение..."
            }
            return
        }

        guard status == .running || status == .failed || status == .needsTunnelRestart else {
            return
        }

        status = .needsTunnelRestart
        lastMessage = "Сеть изменилась. Отключи туннель во внешнем VPN-клиенте, нажми Restart SOCKS, затем включи туннель обратно."
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
