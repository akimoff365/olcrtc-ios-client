import Foundation
import NetworkExtension

@MainActor
final class VPNController: ObservableObject {
    enum Status: String {
        case idle = "Не настроен"
        case loading = "Проверка"
        case installed = "Готов"
        case connecting = "Подключается"
        case connected = "VPN включен"
        case disconnected = "Отключен"
        case failed = "Ошибка"
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastMessage: String?

    private let tunnelBundleIdentifier = "ru.pasklove.olcrtc.tunnel"
    private let managerDescription = "OlcRTC Gateway"

    init() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        status = .loading
        do {
            if let manager = try await loadManager() {
                updateStatus(from: manager)
            } else {
                status = .idle
                lastMessage = "VPN профиль еще не установлен."
            }
        } catch {
            status = .failed
            lastMessage = error.localizedDescription
        }
    }

    func install(profile: OlcRTCProfile, socksPort: Int, credentials: SocksCredentials) async {
        status = .loading
        do {
            let manager = try await loadManager() ?? NETunnelProviderManager()
            let tunnelProtocol = NETunnelProviderProtocol()
            tunnelProtocol.providerBundleIdentifier = tunnelBundleIdentifier
            tunnelProtocol.serverAddress = profile.roomLabel
            tunnelProtocol.providerConfiguration = [
                "carrier": profile.carrier,
                "transport": profile.transport,
                "roomID": profile.roomID,
                "keyHex": profile.keyHex,
                "clientID": profile.runtimeClientID(),
                "socksPort": socksPort,
                "socksUser": credentials.username,
                "socksPass": credentials.password
            ]

            manager.localizedDescription = managerDescription
            manager.protocolConfiguration = tunnelProtocol
            manager.isEnabled = true
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            status = .installed
            lastMessage = "VPN профиль установлен. iOS может запросить подтверждение."
        } catch {
            status = .failed
            lastMessage = error.localizedDescription
        }
    }

    func start() async {
        status = .connecting
        do {
            guard let manager = try await loadManager() else {
                status = .idle
                lastMessage = "Сначала установи VPN профиль."
                return
            }
            try manager.connection.startVPNTunnel()
            updateStatus(from: manager)
        } catch {
            status = .failed
            lastMessage = error.localizedDescription
        }
    }

    func stop() async {
        do {
            guard let manager = try await loadManager() else {
                status = .idle
                return
            }
            manager.connection.stopVPNTunnel()
            updateStatus(from: manager)
        } catch {
            status = .failed
            lastMessage = error.localizedDescription
        }
    }

    private func loadManager() async throws -> NETunnelProviderManager? {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        return managers.first { $0.localizedDescription == managerDescription }
    }

    private func updateStatus(from manager: NETunnelProviderManager) {
        switch manager.connection.status {
        case .connected:
            status = .connected
        case .connecting, .reasserting:
            status = .connecting
        case .disconnected:
            status = .disconnected
        case .disconnecting:
            status = .disconnected
        case .invalid:
            status = .installed
        @unknown default:
            status = .installed
        }
    }
}
