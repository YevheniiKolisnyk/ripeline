import Foundation

/// The Pomodoro state machine.
///
/// Time is always derived from `Date`s (`endsAt - now`), never from a counter that is
/// decremented, so the engine stays correct after the Mac sleeps.
public struct SessionEngine: Sendable {
    public private(set) var snapshot: SessionSnapshot
    private let clock: any WallClock

    /// An idle engine with no day loaded.
    public init(clock: any WallClock) {
        self.snapshot = .empty
        self.clock = clock
    }

    public var state: SessionState { snapshot.state }

    /// Whether `action` is valid right now, so the UI can enable or disable its controls.
    public func isAllowed(_ action: SessionAction) -> Bool {
        snapshot.isAllowed(action)
    }

    // MARK: Actions

    /// Loads a plan. Valid when idle or finished; the engine stays idle until `start`.
    public mutating func startDay(plan: [PlannedSegment], settings: SessionSettings) throws(SessionError) {
        try snapshot.startDay(plan: plan, settings: settings)
    }

    /// Starts the first segment.
    public mutating func start() throws(SessionError) {
        try snapshot.start(at: clock.now)
    }

    /// Stops the countdown of the running segment, keeping its remaining time.
    public mutating func pause() throws(SessionError) {
        try snapshot.pause(at: clock.now)
    }

    /// Continues a paused segment with the time it had left.
    public mutating func resume() throws(SessionError) {
        try snapshot.resume(at: clock.now)
    }

    /// Ends the day. A running or paused segment is marked skipped.
    public mutating func endDay() throws(SessionError) {
        try snapshot.endDay(at: clock.now)
    }

    /// Changes settings. Affects future transitions only; an open pause keeps its kind.
    public mutating func updateSettings(_ settings: SessionSettings) {
        snapshot.settings = settings
    }

    // MARK: Countdown

    /// Seconds left in the current segment, or `nil` when none is counting down.
    public func remainingTime() -> TimeInterval? {
        switch snapshot.state {
        case let .running(_, endsAt): max(0, endsAt.timeIntervalSince(clock.now))
        case let .paused(_, remaining): remaining
        case .idle, .overtime, .finished: nil
        }
    }
}
