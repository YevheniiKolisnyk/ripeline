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
        try snapshot.start(at: syncedNow())
    }

    /// Stops the countdown of the running segment, keeping its remaining time.
    public mutating func pause() throws(SessionError) {
        try snapshot.pause(at: syncedNow())
    }

    /// Continues a paused segment with the time it had left.
    public mutating func resume() throws(SessionError) {
        try snapshot.resume(at: syncedNow())
    }

    /// Ends the day. A running or paused segment is marked skipped.
    public mutating func endDay() throws(SessionError) {
        try snapshot.endDay(at: syncedNow())
    }

    /// Adds time to the current segment. From overtime it restarts the countdown from now.
    public mutating func extend(minutes: Int) throws(SessionError) {
        try snapshot.extend(minutes: minutes, at: syncedNow())
    }

    /// Gives up on the current segment and starts the next one.
    public mutating func skip() throws(SessionError) {
        try snapshot.skip(at: syncedNow())
    }

    /// Leaves overtime and starts the next segment.
    public mutating func advance() throws(SessionError) {
        try snapshot.advance(at: syncedNow())
    }

    /// Brings the engine up to the current time. Call it on a timer, and after waking from sleep.
    public mutating func tick() {
        _ = syncedNow()
    }

    /// Changes settings. Affects future transitions only; an open pause keeps its kind.
    public mutating func updateSettings(_ settings: SessionSettings) {
        snapshot.settings = settings
    }

    // MARK: Countdown

    /// Seconds left in the current segment, or `nil` when none is counting down.
    /// Zero in overtime.
    public func remainingTime() -> TimeInterval? {
        let current = caughtUp()
        switch current.state {
        case let .running(_, endsAt): return max(0, endsAt.timeIntervalSince(currentInstant()))
        case let .paused(_, remaining): return remaining
        case .overtime: return 0
        case .idle, .finished: return nil
        }
    }

    /// Seconds spent past the planned end, or `nil` when not in overtime.
    public func overtimeElapsed() -> TimeInterval? {
        guard case let .overtime(_, since) = caughtUp().state else { return nil }
        return currentInstant().timeIntervalSince(since)
    }

    // MARK: Time

    /// "Now", but never earlier than anything already recorded, so a clock that was set back
    /// cannot produce negative intervals.
    private func currentInstant() -> Date {
        max(clock.now, snapshot.lastRecordedInstant ?? .distantPast)
    }

    /// The snapshot as it would be after `tick()`, without changing the engine.
    private func caughtUp() -> SessionSnapshot {
        var copy = snapshot
        copy.catchUp(to: currentInstant())
        return copy
    }

    /// Catches up to the current time and returns it. Every action starts here.
    private mutating func syncedNow() -> Date {
        let now = currentInstant()
        snapshot.catchUp(to: now)
        return now
    }
}
