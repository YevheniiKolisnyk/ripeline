import Foundation

/// How far the day is from its plan.
public struct ScheduleStatus: Sendable, Equatable {
    /// When the plan said the day would end.
    public let plannedEnd: Date
    /// When the day will end if everything left takes exactly its planned time.
    /// Once the day is finished, when it actually ended.
    public let projectedEnd: Date

    /// `projectedEnd - plannedEnd` in seconds. Positive: behind schedule. Negative: ahead.
    public var lag: TimeInterval { projectedEnd.timeIntervalSince(plannedEnd) }

    /// Builds a status from ready-made dates, for previews and tests.
    public init(plannedEnd: Date, projectedEnd: Date) {
        self.plannedEnd = plannedEnd
        self.projectedEnd = projectedEnd
    }

    /// The status of `snapshot` at `now`, or `nil` when there is nothing to compare: no plan,
    /// or a finished day in which nothing was recorded.
    ///
    /// Segments that ran out before `now` are accounted for even if the engine was not ticked.
    /// `now` is used as given; `SessionEngine.scheduleStatus()` also guards against a clock that
    /// was set back.
    public init?(snapshot: SessionSnapshot, now: Date) {
        guard let plannedEnd = snapshot.plan.last?.end else { return nil }
        var current = snapshot
        current.catchUp(to: now)

        let projectedEnd: Date
        switch current.state {
        case .finished:
            guard let actualEnd = current.lastRecordedInstant else { return nil }
            projectedEnd = actualEnd
        case .idle, .running, .paused, .overtime:
            let currentRemaining: TimeInterval
            switch current.state {
            case let .running(_, endsAt): currentRemaining = max(0, endsAt.timeIntervalSince(now))
            case let .paused(_, remaining): currentRemaining = remaining
            default: currentRemaining = 0
            }
            let notStarted = zip(current.plan, current.actuals)
                .filter { $0.1.status == .notStarted }
                .reduce(0) { $0 + $1.0.duration }
            // Before the day starts nothing can be ahead of schedule: count from the planned start.
            var base = now
            if case .idle = current.state, let plannedStart = current.plan.first?.start {
                base = max(now, plannedStart)
            }
            projectedEnd = base.addingTimeInterval(currentRemaining + notStarted)
        }
        self.plannedEnd = plannedEnd
        self.projectedEnd = projectedEnd
    }
}

extension SessionEngine {
    /// The lag indicator as of the current time, or `nil` when there is nothing to compare.
    public func scheduleStatus() -> ScheduleStatus? {
        ScheduleStatus(snapshot: snapshot, now: currentInstant())
    }
}
