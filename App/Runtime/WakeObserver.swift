import AppKit
import Foundation

/// Calls back when the Mac wakes from sleep or the system clock is changed, so the day can
/// catch up at once instead of waiting for the next tick. The only place that observes AppKit.
@MainActor
final class WakeObserver {
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(onWake: @escaping @MainActor () -> Void) {
        let workspace = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default
        for (center, name) in [(workspace, NSWorkspace.didWakeNotification), (defaultCenter, Notification.Name.NSSystemClockDidChange)] {
            let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
                Task { @MainActor in onWake() }
            }
            tokens.append((center, token))
        }
    }

    /// Stops observing. Also happens when the observer is released.
    func invalidate() {
        for (center, token) in tokens { center.removeObserver(token) }
        tokens = []
    }

    isolated deinit { invalidate() }
}
