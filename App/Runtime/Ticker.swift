import Foundation

/// Calls a handler about once a second while it is running.
///
/// Nothing depends on the ticker being exact: all time comes from `Date`s, so a late or
/// missed tick only delays what the screen shows.
@MainActor protocol Ticker: AnyObject {
    var isRunning: Bool { get }

    /// Starts calling `handler`. Starting a running ticker does nothing; one loop only.
    func start(_ handler: @escaping @MainActor () -> Void)

    func stop()
}

/// A `Ticker` that sleeps in a task. `sleep` is injectable so tests need no real time.
@MainActor
final class TaskTicker: Ticker {
    private let interval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var task: Task<Void, Never>?

    init(
        interval: Duration = .seconds(1),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.interval = interval
        self.sleep = sleep
    }

    var isRunning: Bool { task != nil }

    func start(_ handler: @escaping @MainActor () -> Void) {
        guard task == nil else { return }
        let interval = interval
        let sleep = sleep
        task = Task { @MainActor in
            while !Task.isCancelled {
                do { try await sleep(interval) } catch { break }
                guard !Task.isCancelled else { break }
                handler()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
