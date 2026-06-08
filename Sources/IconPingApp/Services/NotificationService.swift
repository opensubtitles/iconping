import Foundation
import UserNotifications
import IconPingCore

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private var lastDownAt: Date?
    private var lastUpAt: Date?

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    /// `throttleSeconds` collapses bursts. `withSound` toggles the default sound.
    func notifyTransition(
        from: ConnectivityState,
        to: ConnectivityState,
        throttleSeconds: Int,
        withSound: Bool,
        notifyDown: Bool,
        notifyUp: Bool
    ) {
        let now = Date()

        let title: String
        let body: String

        switch (from, to) {
        case (_, .down) where notifyDown:
            if let last = lastDownAt, now.timeIntervalSince(last) < Double(throttleSeconds) { return }
            lastDownAt = now
            title = String(localized: "notif.down.title", defaultValue: "Internet connection lost")
            body  = String(localized: "notif.down.body",  defaultValue: "Your connection appears to be down.")
        case (.down, .up), (.down, .slow):
            guard notifyUp else { return }
            if let last = lastUpAt, now.timeIntervalSince(last) < Double(throttleSeconds) { return }
            lastUpAt = now
            title = String(localized: "notif.up.title", defaultValue: "Internet connection restored")
            body  = String(localized: "notif.up.body",  defaultValue: "Your connection is back.")
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        if withSound { content.sound = .default }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
