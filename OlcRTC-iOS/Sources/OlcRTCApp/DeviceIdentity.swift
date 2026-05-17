import Foundation
import Security

enum DeviceIdentity {
    static func profileClientID(carrier: String, roomID: String, keyHex: String) -> String {
        "ios-\(hash(seed: "\(installSeed())|\(carrier)|\(roomID)|\(keyHex)"))"
    }

    static func legacyProfileClientID(carrier: String, roomID: String, keyHex: String) -> String {
        "ios-\(hash(seed: "\(carrier)|\(roomID)|\(keyHex)"))"
    }

    private static let keychainService = "ru.pasklove.olcrtc.device"
    private static let keychainAccount = "install-seed"
    private static var cachedInstallSeed: String?

    private static func installSeed() -> String {
        if let cachedInstallSeed {
            return cachedInstallSeed
        }

        if let data = KeychainStore.read(service: keychainService, account: keychainAccount),
           let value = String(data: data, encoding: .utf8),
           !value.isEmpty {
            cachedInstallSeed = value
            return value
        }

        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        KeychainStore.save(Data(value.utf8), service: keychainService, account: keychainAccount)
        cachedInstallSeed = value
        return value
    }

    private static func hash(seed: String) -> String {
        let value = seed.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { result, byte in
            (result ^ UInt64(byte)).multipliedReportingOverflow(by: 1_099_511_628_211).partialValue
        }
        return String(value, radix: 16)
    }
}
