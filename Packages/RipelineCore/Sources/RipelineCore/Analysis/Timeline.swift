import Foundation

/// A stretch of a timeline: what it was, and when.
public struct TimelineBlock<Kind: Sendable & Equatable>: Sendable, Equatable {
    /// What this stretch is.
    public let kind: Kind
    /// When the stretch starts.
    public let start: Date
    /// When the stretch ends.
    public let end: Date

    /// A block of `kind` from `start` to `end`.
    public init(kind: Kind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }
}

/// Everything the UI needs to draw the planned and actual rows on a shared time axis.
public struct Timeline: Sendable, Equatable {
    /// One block per planned segment, in plan order.
    public let planned: [TimelineBlock<SegmentKind>]
    /// Chronological. Touching intervals of the same kind are merged into one block.
    /// The interval being recorded runs up to `now`.
    public let actual: [TimelineBlock<ActualKind>]
    /// The span covering both rows, for sizing the axis. `nil` when both are empty.
    public let bounds: DateInterval?

    /// - Parameter now: Used as given. Use `SessionEngine.timeline()` to also get the engine's
    ///   protection against a clock that was set back.
    public init(snapshot: SessionSnapshot, now: Date) {
        var current = snapshot
        current.catchUp(to: now)

        planned = current.plan.map { TimelineBlock(kind: $0.kind, start: $0.start, end: $0.end) }

        var merged: [TimelineBlock<ActualKind>] = []
        let intervals = current.actuals(at: now).flatMap(\.intervals).sorted { $0.start < $1.start }
        for interval in intervals {
            if let last = merged.last, last.kind == interval.kind, last.end == interval.start {
                merged[merged.count - 1] = TimelineBlock(kind: last.kind, start: last.start, end: interval.end)
            } else {
                merged.append(TimelineBlock(kind: interval.kind, start: interval.start, end: interval.end))
            }
        }
        actual = merged

        bounds = Self.bounds(planned: planned, actual: merged)
    }
}

extension Timeline {
    /// Builds a timeline from ready-made blocks, for previews and tests.
    public init(planned: [TimelineBlock<SegmentKind>], actual: [TimelineBlock<ActualKind>]) {
        self.planned = planned
        self.actual = actual
        self.bounds = Self.bounds(planned: planned, actual: actual)
    }

    static func bounds(
        planned: [TimelineBlock<SegmentKind>], actual: [TimelineBlock<ActualKind>]
    ) -> DateInterval? {
        let starts = planned.map(\.start) + actual.map(\.start)
        let ends = planned.map(\.end) + actual.map(\.end)
        guard let first = starts.min(), let last = ends.max() else { return nil }
        return DateInterval(start: first, end: last)
    }
}

extension SessionEngine {
    /// Planned and actual blocks as of the current time, ready to draw.
    public func timeline() -> Timeline {
        Timeline(snapshot: snapshot, now: currentInstant())
    }
}
