import SwiftUI

@main
struct OlcRTCApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var proxy = LocalProxyController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(proxy)
        }
    }
}
