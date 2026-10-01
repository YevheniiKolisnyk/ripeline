import Foundation
@testable import Ripeline

/// A `Notifier` that records what it is told, in order.
@MainActor
final class SpyNotifier: Notifier {
    enum Call: Equatable {
        case authorize
        case schedule(SignalKind, TimeInterval)
        case cancel
        case cancelAll
        case deliver(SignalKind)
    }

    private(set) var calls: [Call] = []
    /// The identifiers passed to `schedule` and `cancel`, in order.
    private(set) var scheduledIDs: [String] = []
    private(set) var cancelledIDs: [String] = []
    /// Set to `false` to model notifications that are unavailable: everything is ignored.
    var recording = true

    func requestAuthorization() async { if recording { calls.append(.authorize) } }
    func schedule(_ kind: SignalKind, in interval: TimeInterval, id: String) {
        guard recording else { return }
        calls.append(.schedule(kind, interval))
        scheduledIDs.append(id)
    }

    func cancel(id: String) {
        guard recording else { return }
        calls.append(.cancel)
        cancelledIDs.append(id)
    }

    func cancelAllPending() { if recording { calls.append(.cancelAll) } }
    func deliverNow(_ kind: SignalKind) { if recording { calls.append(.deliver(kind)) } }

    func reset() { calls = []; scheduledIDs = []; cancelledIDs = [] }
}
