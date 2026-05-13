import Foundation
import Darwin

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

    static func checkLocalSocks(port: Int, timeoutNanoseconds: UInt64 = 3_000_000_000) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await Self.tcpConnects(port: port)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private static func tcpConnects(port: Int) async -> Bool {
        await Task.detached(priority: .utility) {
            guard (1...65_535).contains(port) else {
                return false
            }

            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                return false
            }
            defer {
                close(descriptor)
            }

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = in_port_t(port).bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    Darwin.connect(
                        descriptor,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }

            return result == 0
        }.value
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
