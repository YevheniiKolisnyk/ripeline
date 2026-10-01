import Foundation
import RipelineCore

/// One day in the history list: what happened, summed up at the last thing that was recorded.
struct HistoryEntry: Equatable, Identifiable, Sendable {
    /// The store key of the day's file.
    let id: String
    let snapshot: SessionSnapshot
    /// When the first recorded time began; the plan's start if nothing was recorded.
    let startedAt: Date
    /// The last recorded instant; `nil` when nothing was recorded.
    let endedAt: Date?
    let focusActual: TimeInterval
    let focusPlanned: TimeInterval
    let restActual: TimeInterval
    let isFinished: Bool
    /// The actual end minus the planned end, for a finished day with records; `nil` otherwise.
    let lag: TimeInterval?

    init(day: StoredDay) {
        let snapshot = day.snapshot
        let last = SnapshotSource.lastRecordedInstant(of: snapshot)
        let comparison = DayComparison(snapshot: snapshot, now: last ?? snapshot.plan.first?.start ?? .distantPast)
        let starts = snapshot.actuals.flatMap(\.intervals).map(\.start) + [snapshot.openInterval?.start].compactMap { $0 }

        id = day.key
        self.snapshot = snapshot
        startedAt = starts.min() ?? snapshot.plan.first?.start ?? .distantPast
        endedAt = last
        focusActual = comparison.totals.focusActual
        focusPlanned = comparison.totals.focusPlanned
        restActual = comparison.totals.restActual
        isFinished = snapshot.state == .finished
        if isFinished, let end = comparison.totals.actualEnd, let planned = comparison.totals.plannedEnd {
            lag = end.timeIntervalSince(planned)
        } else {
            lag = nil
        }
    }
}
