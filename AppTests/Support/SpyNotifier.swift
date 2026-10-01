import Foundation
@testable import Ripeline

/// A `Notifier` that records what it is told, in order.
@MainActor
final class SpyNotifier: Notifier {
    enum Call: Equatable {
        case authorize
        case schedule(SignalKind, TimeInterval)
        case cancel
        case deliver(SignalKind)
    }

    private(set) var calls: [Call] = []
    /// Set to `false` to model notifications that are unavailable: everything is ignored.
    var recording = true

    func requestAuthorization() async { if recording { calls.append(.authorize) } }
    func schedule(_ kind: SignalKind, in interval: TimeInterval) { if recording { calls.append(.schedule(kind, interval)) } }
    func cancelPending() { if recording { calls.append(.cancel) } }
    func deliverNow(_ kind: SignalKind) { if recording { calls.append(.deliver(kind)) } }

    func reset() { calls = [] }
}
