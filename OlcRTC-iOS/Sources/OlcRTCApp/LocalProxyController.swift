import Foundation

@MainActor
final class LocalProxyController: ObservableObject {
    enum Status: String {
        case stopped = "Stopped"
        case starting = "Starting"
        case running = "Running"
        case failed = "Failed"
    }

    @Published private(set) var status: Status = .stopped
    @Published private(set) var lastMessage: String?
    @Published private(set) var activeProfile: OlcRTCProfile?

    let socksPort = 18080

    func start(profile: OlcRTCProfile) async {
        status = .starting
        lastMessage = nil

        do {
            OlcRTCEngine.stop()
            try await Task.detached(priority: .userInitiated) { [socksPort] in
                try OlcRTCEngine.start(profile: profile, socksPort: socksPort)
            }.value
            try BackgroundKeepAlive.shared.start()

            activeProfile = profile
            status = .running
            lastMessage = "Keep-alive is active. Use SOCKS5 127.0.0.1:\(socksPort) in Happ, Incy, or another client."
        } catch {
            OlcRTCEngine.stop()
            BackgroundKeepAlive.shared.stop()
            activeProfile = nil
            status = .failed
            lastMessage = error.localizedDescription
        }
    }

    func stop() {
        OlcRTCEngine.stop()
        BackgroundKeepAlive.shared.stop()
        activeProfile = nil
        status = .stopped
        lastMessage = nil
    }
}
