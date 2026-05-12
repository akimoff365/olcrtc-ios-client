import Foundation

#if canImport(Mobile)
import Mobile
#endif

enum OlcRTCEngine {
    static func start(profile: OlcRTCProfile, socksPort: Int = 10808) throws {
        #if canImport(Mobile)
        MobileSetProviders()
        MobileSetDNS("8.8.8.8:53")
        MobileSetTransport(profile.transport)

        if profile.transport == "vp8channel" {
            let fps = Int(profile.payload["vp8-fps"] ?? "") ?? 60
            let batch = Int(profile.payload["vp8-batch"] ?? "") ?? 64
            MobileSetVP8Options(fps, batch)
        }

        try MobileStartWithTransport(
            profile.carrier,
            profile.transport,
            profile.roomID,
            profile.clientID,
            profile.keyHex,
            socksPort,
            "",
            ""
        )
        try MobileWaitReady(12_000)
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

        var errorDescription: String? {
            "Mobile.xcframework is not linked. Build it with Scripts/build-mobile-xcframework.sh."
        }
    }
}
