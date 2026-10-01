import Foundation

/// Plan versus reality, per segment and for the whole day.
public struct DayComparison: Sendable, Equatable {
    /// Plan versus reality for one segment.
    public struct Row: Sendable, Equatable {
        /// The planned segment this row describes.
        public let segment: PlannedSegment
        /// Where the segment stands: not started, active, completed or skipped.
        public let status: SegmentStatus
        /// Planned length in seconds.
        public let planned: TimeInterval
        /// Seconds recorded as work.
        public let work: TimeInterval
        /// Seconds recorded as rest.
        public let rest: TimeInterval
        /// Seconds of untracked pause.
        public let untracked: TimeInterval

        /// Everything recorded in the segment: work + rest + untracked.
        public var actual: TimeInterval { work + rest + untracked }
        /// `actual - planned`. Positive: the segment took longer than planned.
        public var delta: TimeInterval { actual - planned }

        public init(
            segment: PlannedSegment, status: SegmentStatus, planned: TimeInterval,
            work: TimeInterval, rest: TimeInterval, untracked: TimeInterval
        ) {
            self.segment = segment
            self.status = status
            self.planned = planned
            self.work = work
            self.rest = rest
            self.untracked = untracked
        }
    }

    /// Plan versus reality for the whole day.
    public struct Totals: Sendable, Equatable {
        /// Planned work time, in seconds.
        public let focusPlanned: TimeInterval
        /// Work time actually recorded, in seconds.
        public let focusActual: TimeInterval
        /// Planned break time, in seconds.
        public let restPlanned: TimeInterval
        /// Rest time actually recorded, in seconds.
        public let restActual: TimeInterval
        /// Total untracked pause, in seconds.
        public let untracked: TimeInterval
        /// End of the last planned segment. `nil` for an empty plan.
        public let plannedEnd: Date?
        /// When the day actually ended. `nil` while it is still going.
        public let actualEnd: Date?

        public init(
            focusPlanned: TimeInterval, focusActual: TimeInterval,
            restPlanned: TimeInterval, restActual: TimeInterval,
            untracked: TimeInterval, plannedEnd: Date?, actualEnd: Date?
        ) {
            self.focusPlanned = focusPlanned
            self.focusActual = focusActual
            self.restPlanned = restPlanned
            self.restActual = restActual
            self.untracked = untracked
            self.plannedEnd = plannedEnd
            self.actualEnd = actualEnd
        }
    }

    /// One row per planned segment, in plan order.
    public let rows: [Row]
    /// Whole-day figures.
    public let totals: Totals

    /// Builds a comparison from ready-made figures, for previews and tests.
    public init(rows: [Row], totals: Totals) {
        self.rows = rows
        self.totals = totals
    }

    /// Compares `snapshot` with its plan as of `now`. The interval being recorded counts up to `now`.
    /// - Parameter now: Used as given. Use `SessionEngine.comparison()` to also get the engine's
    ///   protection against a clock that was set back.
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
