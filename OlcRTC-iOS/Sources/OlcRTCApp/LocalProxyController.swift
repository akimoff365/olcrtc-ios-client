import Foundation
import Network

@MainActor
final class LocalProxyController: ObservableObject {
    enum Status: String {
        case stopped = "Stopped"
        case starting = "Starting"
        case reconnecting = "Reconnecting"
        case running = "Running"
        case failed = "Failed"
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastMessage: String?
    @Published private(set) var activeProfile: OlcRTCProfile?
    @Published private(set) var reconnectCount = 0

    let socksPort = 18080
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "ru.pasklove.olcrtc.path-monitor")
    private var pathMonitorStarted = false
    private var lastPathSignature: String?
    private var reconnectTask: Task<Void, Never>?

    func start(profile: OlcRTCProfile) async {
        status = .starting
        lastMessage = nil
        lastPathSignature = nil

        do {
            OlcRTCEngine.stop()
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort)
            }.value
            try BackgroundKeepAlive.shared.start()

            activeProfile = profile
            status = .running
            lastMessage = "Keep-alive is active. Use SOCKS5 127.0.0.1:\(socksPort) in Happ, Incy, or another client."
            startPathMonitorIfNeeded()
        } catch {
            OlcRTCEngine.stop()
            BackgroundKeepAlive.shared.stop()
            activeProfile = nil
            status = .failed
            lastMessage = error.localizedDescription
        }
    }

    func reconnect() {
        guard let activeProfile else {
            return
        }

        scheduleReconnect(profile: activeProfile, reason: "Manual reconnect requested.", delayNanoseconds: 0)
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        OlcRTCEngine.stop()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
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
            lastMessage = "Reconnected. Use SOCKS5 127.0.0.1:\(socksPort) in Happ, Incy, or another client."
        } catch {
            OlcRTCEngine.stop()
            status = .failed
            lastMessage = "Reconnect failed: \(error.localizedDescription). Wait a few seconds, then tap Reconnect."
        }
    }

    private func startPathMonitorIfNeeded() {
        guard !pathMonitorStarted else {
            return
        }

        pathMonitorStarted = true
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.pathSignature(path)
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(signature: signature, isSatisfied: isSatisfied)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    private func handlePathUpdate(signature: String, isSatisfied: Bool) {
        if lastPathSignature == nil {
            lastPathSignature = signature
            return
        }

        guard lastPathSignature != signature else {
            return
        }

        lastPathSignature = signature
        guard let activeProfile else {
            return
        }

        guard isSatisfied else {
            if status == .running || status == .reconnecting {
                lastMessage = "Network is switching. Waiting for a usable connection..."
            }
            return
        }

        guard status == .running || status == .failed else {
            return
        }

        scheduleReconnect(profile: activeProfile, reason: "Network changed. Reconnecting olcrtc...", delayNanoseconds: 1_800_000_000)
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

    nonisolated private static func pathSignature(_ path: NWPath) -> String {
        let interfaces = path.availableInterfaces
            .filter { path.usesInterfaceType($0.type) }
            .map { "\($0.type)" }
            .sorted()
            .joined(separator: ",")

        return "\(path.status)|\(path.isExpensive)|\(path.isConstrained)|\(interfaces)"
    }
}
