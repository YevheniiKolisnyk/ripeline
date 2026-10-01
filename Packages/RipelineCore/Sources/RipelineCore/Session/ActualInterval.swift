import Foundation

/// What a recorded stretch of time was spent on.
public enum ActualKind: String, Codable, Sendable, Equatable {
    case work
    case rest
    /// Paused time that counts as neither work nor rest.
    case untracked
}

/// A closed stretch of recorded time inside one segment.
public struct ActualInterval: Codable, Sendable, Equatable {
    /// What the time was spent on.
    public let kind: ActualKind
    public let start: Date
    public let end: Date

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(kind: ActualKind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

/// The stretch of time that is still being recorded. It closes at the next state change.
public struct OpenInterval: Codable, Sendable, Equatable {
    /// What the time since `start` is being spent on.
    public let kind: ActualKind
    /// When the interval began.
    public let start: Date

    public init(kind: ActualKind, start: Date) {
        self.kind = kind
        self.start = start
    }
}
