import Foundation

enum ProfileSecretStore {
    private static let service = "ru.pasklove.olcrtc.profile"

    static func loadKeyHex(profile: OlcRTCProfile) -> String? {
        loadKeyHex(profileID: profile.secretID)
            ?? loadKeyHex(profileID: profile.id)
            ?? loadLegacyKeyHex(profile: profile)
    }

    static func loadKeyHex(profileID: String) -> String? {
        guard let data = KeychainStore.read(service: service, account: account(profileID: profileID)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func saveKeyHex(_ keyHex: String, profileID: String) {
        guard !keyHex.isEmpty else {
            return
        }
        KeychainStore.save(Data(keyHex.utf8), service: service, account: account(profileID: profileID))
    }

    static func deleteKeyHex(profileID: String) {
        KeychainStore.delete(service: service, account: account(profileID: profileID))
    }

    private static func account(profileID: String) -> String {
        "\(profileID).keyHex"
    }

    private static func loadLegacyKeyHex(profile: OlcRTCProfile) -> String? {
        let prefix = "\(profile.carrier)|\(profile.transport)|\(profile.roomID)|"
        let suffix = "|\(profile.clientID).keyHex"

        for item in KeychainStore.readAll(service: service) {
            guard item.account.hasPrefix(prefix),
                  item.account.hasSuffix(suffix),
                  let keyHex = String(data: item.data, encoding: .utf8),
                  keyHex.count == 64,
                  keyHex.allSatisfy(\.isHexDigit) else {
                continue
            }
            saveKeyHex(keyHex, profileID: profile.secretID)
            return keyHex
        }

        return nil
    }
}
