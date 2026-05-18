import NetworkExtension

#if canImport(Mobile)
import Mobile
#endif

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private var socksPort = 18080
    private var tunnelStarted = false

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let config = protocolConfiguration as? NETunnelProviderProtocol,
              let providerConfiguration = config.providerConfiguration,
              let carrier = providerConfiguration["carrier"] as? String,
              let transport = providerConfiguration["transport"] as? String,
              let roomID = providerConfiguration["roomID"] as? String,
              let keyHex = providerConfiguration["keyHex"] as? String,
              let clientID = providerConfiguration["clientID"] as? String else {
            completionHandler(TunnelError.invalidConfiguration)
            return
        }

        socksPort = providerConfiguration["socksPort"] as? Int ?? 18080
        let socksUser = providerConfiguration["socksUser"] as? String ?? ""
        let socksPass = providerConfiguration["socksPass"] as? String ?? ""

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "10.88.0.1")
        settings.mtu = 1280
        settings.ipv4Settings = NEIPv4Settings(addresses: ["10.88.0.2"], subnetMasks: ["255.255.255.0"])
        settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
        settings.proxySettings = proxySettings(port: socksPort)

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self else {
                completionHandler(TunnelError.providerDeallocated)
                return
            }

            if let error {
                completionHandler(error)
                return
            }

            #if canImport(Mobile)
            MobileSetProviders()
            MobileSetDNS("8.8.8.8:53")
            MobileSetTransport(transport)
            MobileSetLivenessOptions(20_000, 15_000, 12)

            var startError: NSError?
            let started = MobileStartWithTransport(
                carrier,
                transport,
                roomID,
                clientID,
                keyHex,
                self.socksPort,
                socksUser,
                socksPass,
                &startError
            )

            if let startError {
                completionHandler(startError)
                return
            }

            guard started else {
                completionHandler(TunnelError.olcrtcStartFailed)
                return
            }

            self.tunnelStarted = true
            completionHandler(nil)
            #else
            completionHandler(TunnelError.mobileFrameworkMissing)
            #endif
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        #if canImport(Mobile)
        if tunnelStarted {
            MobileStop()
        }
        #endif
        tunnelStarted = false
        completionHandler()
    }

    private func proxySettings(port: Int) -> NEProxySettings {
        let settings = NEProxySettings()
        settings.autoProxyConfigurationEnabled = true
        settings.proxyAutoConfigurationJavaScript = """
        function FindProxyForURL(url, host) {
            if (isPlainHostName(host)) { return "DIRECT"; }
            if (host === "localhost" || host === "127.0.0.1") { return "DIRECT"; }
            if (dnsDomainIs(host, ".local")) { return "DIRECT"; }
            return "SOCKS5 127.0.0.1:\(port); SOCKS 127.0.0.1:\(port); DIRECT";
        }
        """
        settings.excludeSimpleHostnames = true
        settings.exceptionList = [
            "*.local",
            "localhost",
            "127.0.0.1"
        ]
        return settings
    }
}

private enum TunnelError: LocalizedError {
    case invalidConfiguration
    case providerDeallocated
    case mobileFrameworkMissing
    case olcrtcStartFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "OlcRTC VPN configuration is incomplete."
        case .providerDeallocated:
            return "OlcRTC VPN provider was deallocated."
        case .mobileFrameworkMissing:
            return "Mobile.xcframework is not linked to the packet tunnel."
        case .olcrtcStartFailed:
            return "olcRTC failed to start inside the packet tunnel."
        }
    }
}
