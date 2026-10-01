import Foundation
import RipelineCore

/// A stored day as a `DayOverviewSource`: everything is read at one fixed instant, the last thing that
/// was recorded, so a day that was never ended is drawn as it stood and does not grow with the clock.
@MainActor
final class SnapshotSource: DayOverviewSource {
    private let snapshot: SessionSnapshot
    private let instant: Date

    init(snapshot: SessionSnapshot) {
        self.snapshot = snapshot
        instant = Self.lastRecordedInstant(of: snapshot) ?? snapshot.plan.first?.start ?? .distantPast
    }

    /// The latest end of a recorded interval, or the start of the one still open; `nil` if nothing
    /// was recorded.
    static func lastRecordedInstant(of snapshot: SessionSnapshot) -> Date? {
        let closed = snapshot.actuals.flatMap(\.intervals).map(\.end)
        return (closed + [snapshot.openInterval?.start].compactMap { $0 }).max()
    }

    var hasDay: Bool { !snapshot.plan.isEmpty }
    /// A stored day is always drawn as over: no "now" line and no lag chip.
    var overviewPhase: Phase { .finished }
    var overviewTimeline: Timeline { Timeline(snapshot: snapshot, now: instant) }
    var overviewComparison: DayComparison { DayComparison(snapshot: snapshot, now: instant) }
    var overviewStatus: ScheduleStatus? { nil }
    var overviewNow: Date { instant }
    var overviewLastRecord: Date? { Self.lastRecordedInstant(of: snapshot) }
}
