import Foundation
import UserNotifications

enum Notifier {
    static let credentialCategory = "CREDENTIAL"
    static let reauthAction = "REAUTH"

    /// UNUserNotificationCenter só funciona dentro de um .app (não em `swift run`).
    static var available: Bool { Bundle.main.bundleIdentifier != nil }

    static func setup(delegate: UNUserNotificationCenterDelegate) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        let reauth = UNNotificationAction(identifier: reauthAction, title: "Reautenticar", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: credentialCategory, actions: [reauth], intentIdentifiers: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func send(title: String, body: String, category: String? = nil) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
