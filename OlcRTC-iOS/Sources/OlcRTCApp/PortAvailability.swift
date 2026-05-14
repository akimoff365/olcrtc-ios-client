import Foundation
import Darwin

enum PortAvailability {
    static func nextAvailableTCPPort(startingAt preferredPort: Int) -> Int {
        let start = min(max(preferredPort, 1), 65_535)

        for port in start...65_535 where isLocalTCPPortAvailable(port) {
            return port
        }

        if start > 1 {
            for port in 1..<start where isLocalTCPPortAvailable(port) {
                return port
            }
        }

        return preferredPort
    }

    static func isLocalTCPPortAvailable(_ port: Int) -> Bool {
        guard (1...65_535).contains(port) else {
            return false
        }

        let descriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
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

        guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else {
            return false
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }
}
