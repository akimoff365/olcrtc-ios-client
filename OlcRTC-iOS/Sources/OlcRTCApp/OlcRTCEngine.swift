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
        let ready = MobileWaitReady(profile.startReadyTimeoutMilliseconds, &waitError)
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

    static func checkLocalSocks(port: Int, credentials: SocksCredentials, timeoutNanoseconds: UInt64 = 5_000_000_000) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await Self.socksAuthHandshake(port: port, credentials: credentials)
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

    static func checkTunnelConnectivity(port: Int, credentials: SocksCredentials, timeoutNanoseconds: UInt64 = 12_000_000_000) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            // Add timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }
            
            // Add parallel probe tasks for each target
            for target in SocksConnectTarget.defaults {
                group.addTask {
                    await Self.socksConnectProbe(port: port, credentials: credentials, target: target)
                }
            }
            
            // Return on first success
            for await result in group {
                if result {
                    group.cancelAll()
                    return true
                }
            }
            
            return false
        }
    }

    private static func socksAuthHandshake(port: Int, credentials: SocksCredentials) async -> Bool {
        await Task.detached(priority: .utility) {
            let username = Array(credentials.username.utf8)
            let password = Array(credentials.password.utf8)
            guard (1...65_535).contains(port),
                  username.count <= 255,
                  password.count <= 255 else {
                return false
            }

            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                return false
            }
            defer {
                close(descriptor)
            }
            Self.setSocketTimeouts(descriptor)

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

            guard result == 0 else {
                return false
            }

            guard Self.writeAll([0x05, 0x01, 0x02], to: descriptor),
                  Self.readExact(2, from: descriptor) == [0x05, 0x02] else {
                return false
            }

            var authRequest: [UInt8] = [0x01, UInt8(username.count)]
            authRequest.append(contentsOf: username)
            authRequest.append(UInt8(password.count))
            authRequest.append(contentsOf: password)

            return Self.writeAll(authRequest, to: descriptor)
                && Self.readExact(2, from: descriptor) == [0x01, 0x00]
        }.value
    }

    private static func socksConnectProbe(port: Int, credentials: SocksCredentials, target: SocksConnectTarget) async -> Bool {
        await Task.detached(priority: .utility) {
            let username = Array(credentials.username.utf8)
            let password = Array(credentials.password.utf8)
            guard (1...65_535).contains(port),
                  username.count <= 255,
                  password.count <= 255 else {
                return false
            }

            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                return false
            }
            defer {
                close(descriptor)
            }
            Self.setSocketTimeouts(descriptor)

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

            guard result == 0 else {
                return false
            }

            guard Self.writeAll([0x05, 0x01, 0x02], to: descriptor),
                  Self.readExact(2, from: descriptor) == [0x05, 0x02] else {
                return false
            }

            var authRequest: [UInt8] = [0x01, UInt8(username.count)]
            authRequest.append(contentsOf: username)
            authRequest.append(UInt8(password.count))
            authRequest.append(contentsOf: password)

            guard Self.writeAll(authRequest, to: descriptor),
                  Self.readExact(2, from: descriptor) == [0x01, 0x00] else {
                return false
            }

            guard let request = target.connectRequest,
                  Self.writeAll(request, to: descriptor),
                  let header = Self.readExact(4, from: descriptor),
                  header.count == 4,
                  header[0] == 0x05,
                  header[1] == 0x00 else {
                return false
            }

            let addressLength: Int
            switch header[3] {
            case 0x01:
                addressLength = 4
            case 0x03:
                guard let lengthByte = Self.readExact(1, from: descriptor)?.first else {
                    return false
                }
                addressLength = Int(lengthByte)
            case 0x04:
                addressLength = 16
            default:
                return false
            }

            return Self.readExact(addressLength + 2, from: descriptor) != nil
        }.value
    }

    private static func setSocketTimeouts(_ descriptor: Int32, seconds: Int = 3) {
        var timeout = timeval(tv_sec: seconds, tv_usec: 0)
        withUnsafePointer(to: &timeout) { pointer in
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_RCVTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
            _ = setsockopt(
                descriptor,
                SOL_SOCKET,
                SO_SNDTIMEO,
                pointer,
                socklen_t(MemoryLayout<timeval>.size)
            )
        }
    }

    private static func writeAll(_ bytes: [UInt8], to descriptor: Int32) -> Bool {
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { rawBuffer in
                Darwin.send(
                    descriptor,
                    rawBuffer.baseAddress!.advanced(by: offset),
                    bytes.count - offset,
                    0
                )
            }
            guard written > 0 else {
                return false
            }
            offset += written
        }
        return true
    }

    private static func readExact(_ count: Int, from descriptor: Int32) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: count)
        var offset = 0
        while offset < count {
            let received = bytes.withUnsafeMutableBytes { rawBuffer in
                Darwin.recv(
                    descriptor,
                    rawBuffer.baseAddress!.advanced(by: offset),
                    count - offset,
                    0
                )
            }
            guard received > 0 else {
                return nil
            }
            offset += received
        }
        return bytes
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

private struct SocksConnectTarget: Sendable {
    enum Address: Sendable {
        case ipv4(String)
        case domain(String)
    }

    let address: Address
    let port: UInt16

    static let defaults = [
        SocksConnectTarget(address: .ipv4("1.1.1.1"), port: 443),
        SocksConnectTarget(address: .ipv4("8.8.8.8"), port: 443),
        SocksConnectTarget(address: .domain("www.apple.com"), port: 443)
    ]

    var connectRequest: [UInt8]? {
        var request: [UInt8] = [0x05, 0x01, 0x00]

        switch address {
        case let .ipv4(value):
            let parts = value.split(separator: ".").compactMap { UInt8($0) }
            guard parts.count == 4 else {
                return nil
            }
            request.append(0x01)
            request.append(contentsOf: parts)
        case let .domain(value):
            let host = Array(value.utf8)
            guard !host.isEmpty, host.count <= 255 else {
                return nil
            }
            request.append(0x03)
            request.append(UInt8(host.count))
            request.append(contentsOf: host)
        }

        request.append(UInt8(port >> 8))
        request.append(UInt8(port & 0xff))
        return request
    }
}
