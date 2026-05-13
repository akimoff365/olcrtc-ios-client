import Foundation
import Security

struct SocksCredentials: Codable, Equatable {
    let username: String
    let password: String

    static func load() -> SocksCredentials {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: storageKey),
           let credentials = try? JSONDecoder().decode(SocksCredentials.self, from: data) {
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
            UserDefaults.standard.set(data, forKey: Self.storageKey)
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

    private static let storageKey = "olcrtc.socks.credentials"

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
        addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? self
    }
}
