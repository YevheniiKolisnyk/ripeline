import Foundation

/// A stretch of a timeline: what it was, and when.
public struct TimelineBlock<Kind: Sendable & Equatable>: Sendable, Equatable {
    public let kind: Kind
    public let start: Date
    public let end: Date
}

/// Everything the UI needs to draw the planned and actual rows on a shared time axis.
public struct Timeline: Sendable, Equatable {
    public let planned: [TimelineBlock<SegmentKind>]
    /// Chronological. Touching intervals of the same kind are merged into one block.
    /// The interval being recorded runs up to `now`.
    public let actual: [TimelineBlock<ActualKind>]
    /// The span covering both rows, for sizing the axis. `nil` when both are empty.
    public let bounds: DateInterval?

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

        let starts = planned.map(\.start) + merged.map(\.start)
        let ends = planned.map(\.end) + merged.map(\.end)
        if let first = starts.min(), let last = ends.max() {
            bounds = DateInterval(start: first, end: last)
        } else {
            bounds = nil
        }
    }
}

extension SessionEngine {
    /// Planned and actual blocks as of the current time, ready to draw.
    public func timeline() -> Timeline {
        Timeline(snapshot: snapshot, now: currentInstant())
    }
}
