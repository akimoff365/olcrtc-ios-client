import Foundation
import Network

@MainActor
final class LocalProxyController: ObservableObject {
    enum Status: String {
        case stopped = "Остановлен"
        case starting = "Запускается"
        case reconnecting = "Переподключение"
        case running = "Работает"
        case failed = "Ошибка"
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastMessage: String?
    @Published private(set) var activeProfile: OlcRTCProfile?
    @Published private(set) var reconnectCount = 0
    @Published private(set) var networkName = "Нет"

    let socksPort = 18080
    private let pathQueue = DispatchQueue(label: "ru.pasklove.olcrtc.path-monitor")
    private var pathMonitor: NWPathMonitor?
    private var lastPathSignature: String?
    private var reconnectTask: Task<Void, Never>?

    var canReconnect: Bool {
        activeProfile != nil && status != .stopped && status != .starting && status != .reconnecting
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
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort)
            }.value
            try BackgroundKeepAlive.shared.start()

            activeProfile = profile
            reconnectCount = 0
            status = .running
            lastMessage = "SOCKS5 готов: 127.0.0.1:\(socksPort)"
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

    func reconnect() {
        guard let activeProfile else {
            return
        }

        scheduleReconnect(profile: activeProfile, reason: "Ручное переподключение...", delayNanoseconds: 0)
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

    private func reconnectNow(profile: OlcRTCProfile, reason: String) async {
        guard activeProfile?.id == profile.id else {
            return
        }

        status = .reconnecting
        lastMessage = reason

        do {
            OlcRTCEngine.stop()
            try? await Task.sleep(nanoseconds: 600_000_000)
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort)
            }.value
            try BackgroundKeepAlive.shared.start()

            reconnectCount += 1
            status = .running
            lastMessage = "Переподключено. SOCKS5: 127.0.0.1:\(socksPort)"
        } catch {
            OlcRTCEngine.stop()
            status = .failed
            lastMessage = "Не удалось переподключиться: \(error.localizedDescription)"
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
            if status == .running || status == .reconnecting {
                lastMessage = "Сеть переключается. Жду рабочее соединение..."
            }
            return
        }

        guard status == .running || status == .failed else {
            return
        }

        scheduleReconnect(profile: activeProfile, reason: "Сеть изменилась. Переподключаю olcrtc...", delayNanoseconds: 1_800_000_000)
    }

    private func scheduleReconnect(profile: OlcRTCProfile, reason: String, delayNanoseconds: UInt64) {
        reconnectTask?.cancel()
        reconnectTask = Task { [profile] in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else {
                return
            }
            await reconnectNow(profile: profile, reason: reason)
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
