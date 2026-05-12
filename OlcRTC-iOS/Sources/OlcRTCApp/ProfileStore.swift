import Foundation

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [OlcRTCProfile] = []

    private let storageKey = "olcrtc.profiles"

    init() {
        load()
    }

    func upsert(_ profile: OlcRTCProfile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.insert(profile, at: 0)
        save()
    }

    func remove(at offsets: IndexSet) {
        for offset in offsets.sorted(by: >) {
            profiles.remove(at: offset)
        }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return
        }

        profiles = (try? JSONDecoder().decode([OlcRTCProfile].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
