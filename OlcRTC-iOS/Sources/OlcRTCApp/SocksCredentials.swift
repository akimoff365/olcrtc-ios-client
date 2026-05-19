import Foundation
import Security

struct SocksCredentials: Codable, Equatable, Sendable {
    let username: String
    let password: String

    static func load() -> SocksCredentials {
        if let data = KeychainStore.read(service: keychainService, account: keychainAccount),
           let credentials = try? JSONDecoder().decode(SocksCredentials.self, from: data) {
            return credentials
        }

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: legacyStorageKey),
           let credentials = try? JSONDecoder().decode(SocksCredentials.self, from: data) {
            credentials.save()
            defaults.removeObject(forKey: legacyStorageKey)
            return credentials
        }

        let credentials = SocksCredentials(
            username: "olc_" + Self.token(length: 8),
            password: Self.token(length: 20)
        )
        credentials.save()
        return credentials
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            KeychainStore.save(data, service: Self.keychainService, account: Self.keychainAccount)
        }
    }

    func socks5URL(port: Int) -> String {
        let user = username.urlComponentEncoded
        let pass = password.urlComponentEncoded
        return "socks5://\(user):\(pass)@127.0.0.1:\(port)#OlcRTC"
    }

    func legacySocksURL(port: Int) -> String {
        let authority = "\(username):\(password)@127.0.0.1:\(port)"
        let encoded = Data(authority.utf8).base64EncodedString()
        return "socks://\(encoded)#OlcRTC"
    }

    private static let legacyStorageKey = "olcrtc.socks.credentials"
    private static let keychainService = "ru.pasklove.olcrtc.socks"
    private static let keychainAccount = "default"

    private static func token(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var result = ""
        result.reserveCapacity(length)

        for _ in 0..<length {
            var byte: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            result.append(alphabet[Int(byte) % alphabet.count])
        }

        return result
    }
}

private extension String {
    var urlComponentEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
