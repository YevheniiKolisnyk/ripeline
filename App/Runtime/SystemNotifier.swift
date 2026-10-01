import Foundation
import os
@preconcurrency import UserNotifications

/// `Notifier` over `UserNotifications`. A thin adapter: what it is told to do is tested
/// through `SessionController`; failures are logged locally and otherwise ignored.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    private static let pendingPrefix = "ripeline.segment-end."
    private static let immediateIdentifier = "ripeline.summary"

    private let center: UNUserNotificationCenter
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "notifications")

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func schedule(_ kind: SignalKind, in interval: TimeInterval, id: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        add(Self.pendingPrefix + id, kind, trigger)
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.pendingPrefix + id])
    }

    func cancelAllPending() {
        let center = center
        let prefix = Self.pendingPrefix
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    func deliverNow(_ kind: SignalKind) {
        add(Self.immediateIdentifier, kind, nil)
    }

    private func add(_ identifier: String, _ kind: SignalKind, _ trigger: UNNotificationTrigger?) {
        let text = SignalContent(kind: kind)
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let logger = logger
        // The completion-handler form queues the request at once, so it stays ordered with a
        // cancel that follows.
        center.add(request) { error in
            if let error {
                logger.error("Could not add notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Show banner and sound, and keep it in Notification Center, even while the app is active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
