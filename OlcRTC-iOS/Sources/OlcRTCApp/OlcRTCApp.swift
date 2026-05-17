import SwiftUI

@main
struct OlcRTCApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var proxy = LocalProxyController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(proxy)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        proxy.appDidBecomeActive()
                    case .inactive, .background:
                        proxy.appWillResignActive()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
