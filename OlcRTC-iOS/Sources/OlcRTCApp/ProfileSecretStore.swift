import Foundation

enum ProfileSecretStore {
    private static let service = "ru.pasklove.olcrtc.profile"

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
}
