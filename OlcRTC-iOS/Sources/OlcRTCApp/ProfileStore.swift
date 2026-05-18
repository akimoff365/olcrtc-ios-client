import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [OlcRTCProfile] = []

    private let storageKey = "olcrtc.profiles"

    init() {
        load()
    }

    func upsert(_ profile: OlcRTCProfile) {
        profiles.removeAll { $0.id == profile.id || $0.secretID == profile.secretID }
        profiles.insert(profile, at: 0)
        save()
    }

    func upsert(_ importedProfiles: [OlcRTCProfile]) {
        guard !importedProfiles.isEmpty else {
            return
        }

        let importedIDs = Set(importedProfiles.map(\.id))
        let importedSecretIDs = Set(importedProfiles.map(\.secretID))
        profiles.removeAll { importedIDs.contains($0.id) || importedSecretIDs.contains($0.secretID) }
        profiles.insert(contentsOf: importedProfiles, at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            if profiles.indices.contains(offset) {
                ProfileSecretStore.deleteKeyHex(profileID: profiles[offset].id)
                ProfileSecretStore.deleteKeyHex(profileID: profiles[offset].secretID)
            }
            profiles.remove(at: offset)
        }
        save()
    }

    func remove(_ profile: OlcRTCProfile) {
        profiles.removeAll { $0.id == profile.id || $0.secretID == profile.secretID }
        ProfileSecretStore.deleteKeyHex(profileID: profile.id)
        ProfileSecretStore.deleteKeyHex(profileID: profile.secretID)
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        let decodedProfiles = (try? JSONDecoder().decode([OlcRTCProfile].self, from: data)) ?? []
        var didMigrate = false
        profiles = decodedProfiles.map { profile in
            let keyHex = ProfileSecretStore.loadKeyHex(profile: profile) ?? profile.keyHex
            var loadedProfile = profile.withKeyHex(keyHex)
            if loadedProfile.hasLegacyGeneratedClientID {
                loadedProfile = loadedProfile.withClientID(
                    DeviceIdentity.profileClientID(
                        carrier: loadedProfile.carrier,
                        roomID: loadedProfile.roomID,
                        keyHex: loadedProfile.keyHex
                    )
                )
                didMigrate = true
            }
            return loadedProfile
        }

        if didMigrate {
            save()
        }
    }

    private func save() {
        profiles.forEach { profile in
            ProfileSecretStore.saveKeyHex(profile.keyHex, profileID: profile.secretID)
        }

        let publicProfiles = profiles.map { profile in
            profile.withKeyHex("")
        }

        guard let data = try? JSONEncoder().encode(publicProfiles) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
