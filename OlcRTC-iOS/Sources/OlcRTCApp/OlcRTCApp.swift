import SwiftUI

@main
struct OlcRTCApp: App {
    @StateObject private var store = ProfileStore()
    @StateObject private var proxy = LocalProxyController()
    @StateObject private var notifications = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Set notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(proxy)
                .environmentObject(notifications)
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        proxy.appDidBecomeActive()
                        notifications.clearBadge()
                    case .inactive, .background:
                        proxy.appWillResignActive()
                    @unknown default:
                        break
                    }
                }
                .task {
                    // Request notification permission on first launch
                    if notifications.authorizationStatus == .notDetermined {
                        _ = await notifications.requestAuthorization()
                    }
                }
        }
    }
}
