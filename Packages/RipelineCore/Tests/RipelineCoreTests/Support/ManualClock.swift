import Foundation
import Synchronization
@testable import RipelineCore

/// A clock the test moves by hand. No real time ever passes.
final class ManualClock: WallClock, Sendable {
    private let current: Mutex<Date>

    init(_ start: Date) { current = Mutex(start) }

    var now: Date { current.withLock { $0 } }

    func set(_ date: Date) { current.withLock { $0 = date } }
}
