import Foundation

/// Plan versus reality, per segment and for the whole day.
public struct DayComparison: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let segment: PlannedSegment
        public let status: SegmentStatus
        /// Planned length in seconds.
        public let planned: TimeInterval
        public let work: TimeInterval
        public let rest: TimeInterval
        public let untracked: TimeInterval

        /// Everything recorded in the segment: work + rest + untracked.
        public var actual: TimeInterval { work + rest + untracked }
        /// `actual - planned`. Positive: the segment took longer than planned.
        public var delta: TimeInterval { actual - planned }
    }

    public struct Totals: Sendable, Equatable {
        public let focusPlanned: TimeInterval
        public let focusActual: TimeInterval
        public let restPlanned: TimeInterval
        public let restActual: TimeInterval
        public let untracked: TimeInterval
        public let plannedEnd: Date?
        /// When the day actually ended. `nil` while it is still going.
        public let actualEnd: Date?
    }

    public let rows: [Row]
    public let totals: Totals

    /// Compares `snapshot` with its plan as of `now`. The interval being recorded counts up to `now`.
    public init(snapshot: SessionSnapshot, now: Date) {
        var current = snapshot
        current.catchUp(to: now)
        let actuals = current.actuals(at: now)

        func sum(_ actual: SegmentActual, _ kind: ActualKind) -> TimeInterval {
            actual.intervals.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration }
        }
        rows = zip(current.plan, actuals).map { segment, actual in
            Row(
                segment: segment, status: actual.status, planned: segment.duration,
                work: sum(actual, .work), rest: sum(actual, .rest), untracked: sum(actual, .untracked)
            )
        }

        let isFinished = current.state == .finished
        totals = Totals(
            focusPlanned: rows.filter { $0.segment.kind == .work }.reduce(0) { $0 + $1.planned },
            focusActual: rows.reduce(0) { $0 + $1.work },
            restPlanned: rows.filter { $0.segment.kind.isBreak }.reduce(0) { $0 + $1.planned },
            restActual: rows.reduce(0) { $0 + $1.rest },
            untracked: rows.reduce(0) { $0 + $1.untracked },
            plannedEnd: current.plan.last?.end,
            actualEnd: isFinished ? current.lastRecordedInstant : nil
        )
    }
}

extension SessionEngine {
    /// Plan versus reality as of the current time.
    public func comparison() -> DayComparison {
        DayComparison(snapshot: snapshot, now: currentInstant())
    }
}
