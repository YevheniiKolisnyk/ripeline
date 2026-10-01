import Foundation
import os
import UserNotifications

/// `Notifier` over `UserNotifications`. A thin adapter: what it is told to do is tested
/// through `SessionController`; failures are logged locally and otherwise ignored.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    private static let pendingIdentifier = "ripeline.segment-end"
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

    func schedule(_ kind: SignalKind, in interval: TimeInterval) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        add(Self.pendingIdentifier, kind, trigger)
    }

    func cancelPending() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.pendingIdentifier])
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
        let center = center
        let logger = logger
        Task {
            do { try await center.add(request) } catch {
                logger.error("Could not add notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Show banner and sound even while the app is the active application.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
