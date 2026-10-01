import Foundation

/// Where the engine is. All times are absolute `Date`s so the state survives sleep and relaunch.
public enum SessionState: Codable, Sendable, Equatable {
    /// No segment is running. A day may or may not be loaded.
    case idle
    /// The segment's countdown ends at `endsAt`.
    case running(segmentIndex: Int, endsAt: Date)
    /// The countdown is stopped with `remaining` seconds left.
    case paused(segmentIndex: Int, remaining: TimeInterval)
    /// The planned time ran out at `since`; time keeps being recorded in the same segment.
    case overtime(segmentIndex: Int, since: Date)
    case finished
}

/// Things the user can do. Used to ask which buttons are available.
public enum SessionAction: String, Sendable, Equatable, CaseIterable {
    case startDay
    case start
    case pause
    case resume
    case extend
    case skip
    case advance
    case endDay
    /// Adds segments to a quick session while it runs.
    case append
}

/// Why the engine refused an action or a stored snapshot.
public enum SessionError: Error, Sendable, Equatable {
    /// `startDay` was given an empty plan.
    case emptyPlan
    /// `startDay` was given a plan whose segments are not contiguous, positive-length and
    /// indexed by position.
    case invalidPlan
    /// `extend` was given zero or negative minutes.
    case nonPositiveExtension
    /// The action is not valid in the current state.
    case notAllowed(SessionAction)
    /// A restored snapshot is internally inconsistent.
    case invalidSnapshot
}
