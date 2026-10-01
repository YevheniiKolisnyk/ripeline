import Foundation
@testable import Ripeline

/// A `Ticker` the test fires by hand.
@MainActor
final class ManualTicker: Ticker {
    private(set) var isRunning = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var handler: (@MainActor () -> Void)?

    func start(_ handler: @escaping @MainActor () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        startCount += 1
        self.handler = handler
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        stopCount += 1
        handler = nil
    }

    /// Runs the handler once, as the real ticker would after one second, if it is running.
    func fire() { handler?() }
}
