import Foundation

/// A `Notifier` that does nothing.
@MainActor
final class NullNotifier: Notifier {
    func requestAuthorization() async {}
    func schedule(_ kind: SignalKind, in interval: TimeInterval, id: String) {}
    func cancel(id: String) {}
    func cancelAllPending() {}
    func deliverNow(_ kind: SignalKind) {}
}

/// A `Ticker` that never ticks.
@MainActor
final class NullTicker: Ticker {
    var isRunning: Bool { false }
    func start(_ handler: @escaping @MainActor () -> Void) {}
    func stop() {}
}
