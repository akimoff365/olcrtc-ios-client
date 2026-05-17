import Foundation
import UserNotifications

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    private override init() {
        super.init()
        
        // Set default value for notifications.enabled if not set
        if UserDefaults.standard.object(forKey: "notifications.enabled") == nil {
            UserDefaults.standard.set(true, forKey: "notifications.enabled")
        }
        
        checkAuthorizationStatus()
    }
    
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            await checkAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }
    
    func checkAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
                isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func sendNotification(
        title: String,
        body: String,
        identifier: String = UUID().uuidString,
        delay: TimeInterval = 0
    ) {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = 1
        
        let trigger: UNNotificationTrigger? = delay > 0 
            ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            : nil
        
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
    
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
    
    func removeAllPendingNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    func removeAllDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        clearBadge()
    }
}

// MARK: - Notification Types

extension NotificationManager {
    enum NotificationType {
        case connectionRestored
        case connectionFailed
        case networkChanged
        case actionRequired
        case longUptime(hours: Int)
        
        var title: String {
            switch self {
            case .connectionRestored:
                return "Соединение восстановлено"
            case .connectionFailed:
                return "Ошибка подключения"
            case .networkChanged:
                return "Сеть изменилась"
            case .actionRequired:
                return "Требуется действие"
            case .longUptime(let hours):
                return "Приложение работает без проблем уже \(hours) часов!"
            }
        }
        
        func body(context: String = "") -> String {
            switch self {
            case .connectionRestored:
                return "SOCKS прокси снова работает. Можно включить VPN."
            case .connectionFailed:
                return context.isEmpty ? "Не удалось подключиться" : context
            case .networkChanged:
                return "Перезапустите SOCKS и внешний VPN"
            case .actionRequired:
                return context.isEmpty ? "Откройте приложение" : context
            case .longUptime(let hours):
                return "Приложение работает без проблем уже \(hours) часов!"
            }
        }
        
        var identifier: String {
            switch self {
            case .connectionRestored:
                return "connection.restored"
            case .connectionFailed:
                return "connection.failed"
            case .networkChanged:
                return "network.changed"
            case .actionRequired:
                return "action.required"
            case .longUptime:
                return "long.uptime"
            }
        }
    }
    
    func send(_ type: NotificationType, context: String = "") {
        // Check if notifications are enabled globally
        guard UserDefaults.standard.bool(forKey: "notifications.enabled") else {
            return
        }
        
        // Check if this specific notification type is enabled
        let key: String
        switch type {
        case .connectionRestored:
            key = "notifications.connectionRestored"
        case .connectionFailed:
            key = "notifications.connectionFailed"
        case .networkChanged:
            key = "notifications.networkChanged"
        case .actionRequired:
            key = "notifications.actionRequired"
        case .longUptime:
            key = "notifications.longUptime"
        }
        
        // Default to true if not set
        let isEnabled = UserDefaults.standard.object(forKey: key) as? Bool ?? true
        guard isEnabled else {
            return
        }
        
        sendNotification(
            title: type.title,
            body: type.body(context: context),
            identifier: type.identifier
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        Task { @MainActor in
            clearBadge()
        }
        completionHandler()
    }
}
