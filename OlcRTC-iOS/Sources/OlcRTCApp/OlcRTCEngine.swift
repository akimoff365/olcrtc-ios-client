import Foundation

#if canImport(Mobile)
import Mobile
#endif

enum OlcRTCEngine {
    static func start(profile: OlcRTCProfile, socksPort: Int = 18080, credentials: SocksCredentials) throws {
        #if canImport(Mobile)
        MobileSetProviders()
        MobileSetDNS("8.8.8.8:53")
        MobileSetTransport(profile.transport)

        if profile.transport == "vp8channel" {
            let fps = Int(profile.payload["vp8-fps"] ?? "") ?? 60
            let batch = Int(profile.payload["vp8-batch"] ?? "") ?? 64
            MobileSetVP8Options(fps, batch)
        }

        var startError: NSError?
        let started = MobileStartWithTransport(
            profile.carrier,
            profile.transport,
            profile.roomID,
            profile.clientID,
            profile.keyHex,
            socksPort,
            credentials.username,
            credentials.password,
            &startError
        )
        if let startError {
            throw startError
        }
        guard started else {
            throw RuntimeError.startFailed
        }

        var waitError: NSError?
        let ready = MobileWaitReady(12_000, &waitError)
        if let waitError {
            throw waitError
        }
        guard ready else {
            throw RuntimeError.readyTimeout
        }
        #else
        throw RuntimeError.frameworkMissing
        #endif
    }

    static func stop() {
        #if canImport(Mobile)
        MobileStop()
        #endif
    }

    enum RuntimeError: LocalizedError {
        case frameworkMissing
        case startFailed
        case readyTimeout

        var errorDescription: String? {
            switch self {
            case .frameworkMissing:
                return "Mobile.xcframework is not linked. Build it with Scripts/build-mobile-xcframework.sh."
            case .startFailed:
                return "olcrtc did not start."
            case .readyTimeout:
                return "olcrtc SOCKS proxy was not ready in time."
            }
        }
    }
}
