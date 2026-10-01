import Foundation

/// The source of "now". Injected so tests control time.
public protocol WallClock: Sendable {
    var now: Date { get }
}

/// The system clock. The only place in the core that reads real time.
public struct SystemClock: WallClock {
    public init() {}

    public var now: Date { Date() }
}
