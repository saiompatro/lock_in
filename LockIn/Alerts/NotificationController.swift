import AppKit
import UserNotifications

/// Owns the `UNUserNotificationCenter` integration: permission, posting, action routing.
/// Every method is a safe no-op when the process has no bundle (e.g. unit tests, `swift run`),
/// because `UNUserNotificationCenter.current()` traps without one.
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    enum Action {
        case backToStudying
        case takeBreak
    }

    /// A notification action (or a click on the banner itself) was chosen.
    var onAction: ((Action) -> Void)?

    static let categoryID = "com.lockin.distraction"
    static let backActionID = "com.lockin.action.back"
    static let breakActionID = "com.lockin.action.break"
    /// Fixed identifier: a repeat reminder replaces the previous banner instead of stacking.
    static let requestID = "com.lockin.distraction.alert"

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
    }

    override init() {
        super.init()
        guard let center else { return }
        center.delegate = self
        let back = UNNotificationAction(identifier: Self.backActionID, title: "Back to studying", options: [])
        let pause = UNNotificationAction(identifier: Self.breakActionID, title: "Take a break", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID,
                                              actions: [back, pause],
                                              intentIdentifiers: [],
                                              options: [])
        center.setNotificationCategories([category])
    }

    // MARK: Permission

    /// true = authorized, false = denied, nil = not determined yet (or no bundle).
    func authorizationStatus() async -> Bool? {
        guard let center else { return false }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .denied: return false
        case .notDetermined: return nil
        @unknown default: return false
        }
    }

    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Authorized now, asking the user once if the decision has not been made yet.
    func ensureAuthorized() async -> Bool {
        switch await authorizationStatus() {
        case .some(let granted): return granted
        case .none: return await requestAuthorization()
        }
    }

    // MARK: Posting

    /// Post (replacing any previous one). Delivered silently; `SoundPlayer` handles audio.
    func post(title: String, body: String) async {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.categoryIdentifier = Self.categoryID
        let request = UNNotificationRequest(identifier: Self.requestID, content: content, trigger: nil)
        // Replace instead of stacking.
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
        try? await center.add(request)
    }

    func removeAll() {
        guard let center else { return }
        center.removeDeliveredNotifications(withIdentifiers: [Self.requestID])
        center.removePendingNotificationRequests(withIdentifiers: [Self.requestID])
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even while Lock In is the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let identifier = response.actionIdentifier
        completionHandler()
        Task { @MainActor [weak self] in
            switch identifier {
            case Self.backActionID, UNNotificationDefaultActionIdentifier:
                self?.onAction?(.backToStudying)
            case Self.breakActionID:
                self?.onAction?(.takeBreak)
            default:
                break
            }
        }
    }
}
