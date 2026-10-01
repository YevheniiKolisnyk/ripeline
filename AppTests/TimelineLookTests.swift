import RipelineCore
import SwiftUI
import Testing
@testable import Ripeline

@MainActor
struct TimelineLookTests {
    @Test func colourIsNotTheOnlyCue() {
        let work = TimelineRowsView.heightFraction(for: SegmentKind.work)
        let shortBreak = TimelineRowsView.heightFraction(for: SegmentKind.shortBreak)
        let longBreak = TimelineRowsView.heightFraction(for: SegmentKind.longBreak)
        #expect(work == 1)
        #expect(shortBreak < 1)
        // The long break is told from the short one by height too, not only by colour.
        #expect(longBreak > shortBreak)
        #expect(longBreak < 1)

        #expect(TimelineRowsView.heightFraction(for: ActualKind.work) == 1)
        #expect(TimelineRowsView.heightFraction(for: ActualKind.rest) < 1)
        #expect(TimelineRowsView.heightFraction(for: ActualKind.untracked) < 1)
    }

    @Test func aSkippedSegmentsDifferenceIsNotGreen() {
        // Cutting a segment short on purpose is not a win: plain, like a difference within a minute.
        let skipped = SegmentTableView.deltaColour(-2400, status: .skipped)
        let early = SegmentTableView.deltaColour(-2400, status: .completed)
        let late = SegmentTableView.deltaColour(300, status: .completed)
        let tiny = SegmentTableView.deltaColour(30, status: .completed)
        #expect(skipped == Color.secondary)
        #expect(early == Color.green)
        #expect(late == Color.orange)
        #expect(tiny == Color.secondary)
    }
}
