import Foundation
import Testing
import RipelineCore   // deliberately not @testable: only public API is visible here

/// Stage 2 builds SwiftUI previews and tests from these value types without running an engine.
struct PublicAPITests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func readModelsCanBeBuiltByHand() {
        let end = start.addingTimeInterval(3000)
        let segment = PlannedSegment(index: 0, kind: .work, start: start, end: end)

        let row = DayComparison.Row(
            segment: segment, status: .completed, planned: 3000, work: 3100, rest: 0, untracked: 60
        )
        let totals = DayComparison.Totals(
            focusPlanned: 3000, focusActual: 3100, restPlanned: 0, restActual: 0,
            untracked: 60, plannedEnd: end, actualEnd: end
        )
        let comparison = DayComparison(rows: [row], totals: totals)
        #expect(comparison.rows.first?.delta == 160)
        #expect(comparison.totals.focusActual == 3100)

        let timeline = Timeline(
            planned: [TimelineBlock(kind: SegmentKind.work, start: start, end: end)],
            actual: [TimelineBlock(kind: ActualKind.work, start: start, end: end)]
        )
        #expect(timeline.bounds == DateInterval(start: start, end: end))

        let status = ScheduleStatus(plannedEnd: end, projectedEnd: end.addingTimeInterval(120))
        #expect(status.lag == 120)
    }
}
