import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerOverviewTests {
    private func started(session: SessionSettings? = nil) async -> Harness {
        let h = Harness(session: session)
        await h.startStandardDay()
        return h
    }

    // MARK: read models

    @Test func theTimelineMirrorsThePlanAndTheRunningDay() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        let timeline = h.controller.timeline
        #expect(timeline.planned.count == h.controller.plan.count)
        #expect(timeline.planned.first == TimelineBlock(kind: SegmentKind.work, start: t(9), end: t(9, 50)))
        #expect(timeline.actual == [TimelineBlock(kind: ActualKind.work, start: t(9), end: t(9, 20))])
    }

    @Test func theComparisonCountsTheOpenInterval() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        let comparison = h.controller.comparison
        #expect(comparison.rows[0].work == minutes(20))
        #expect(comparison.rows[0].planned == minutes(50))
        let plannedFocus = h.controller.plan.filter { $0.kind == .work }.reduce(0) { $0 + $1.duration }
        #expect(comparison.totals.focusPlanned == plannedFocus)
        #expect(comparison.totals.actualEnd == nil)
    }

    @Test func overtimeShowsAsALongerActualBlockAndAPositiveDelta() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 55))
        #expect(h.controller.comparison.rows[0].delta == minutes(5))
        #expect(h.controller.timeline.actual.last?.end == t(9, 55))
    }

    // MARK: session settings

    @Test func changingSettingsWritesThemAndSavesTheSnapshot() async {
        let h = await started(); defer { h.cleanUp() }
        let changed = SessionSettings(pausesCountAsRest: false, autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true)
        h.controller.updateSessionSettings(changed)
        #expect(h.settings.session == changed)
        #expect(h.store.saved.last?.settings == changed)
    }

    /// Review Focus 3: a change must not advance a segment that is already in overtime or rewrite what was recorded.
    @Test func enablingAutoAdvanceInOvertimeDoesNotAdvanceOrRewrite() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 55)); h.controller.refresh()
        #expect(h.controller.phase == .overtime(onBreak: false))
        let before = h.controller.comparison.rows[0]
        h.controller.updateSessionSettings(SessionSettings(autoAdvanceWorkToBreak: true))
        h.controller.refresh()
        #expect(h.controller.phase == .overtime(onBreak: false))
        #expect(h.controller.comparison.rows[0] == before)
    }

    @Test func anOpenPauseKeepsItsKindAndTheNextPauseUsesTheNewSetting() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 10)); h.controller.pause()                   // counts as rest (default)
        h.controller.updateSessionSettings(SessionSettings(pausesCountAsRest: false))
        h.clock.set(t(9, 15)); h.controller.resume()
        #expect(h.controller.comparison.rows[0].rest == minutes(5))
        #expect(h.controller.comparison.rows[0].untracked == 0)

        h.clock.set(t(9, 20)); h.controller.pause()
        h.clock.set(t(9, 25)); h.controller.resume()
        #expect(h.controller.comparison.rows[0].untracked == minutes(5))
        #expect(h.controller.comparison.rows[0].rest == minutes(5))
    }

    /// Review finding: a segment whose end has passed but was not ticked yet must be settled with the
    /// settings that were in force when it ended, not with the ones chosen a moment later.
    @Test func aSettingChangedJustAfterASegmentEndDoesNotApplyRetroactively() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 50).addingTimeInterval(0.5))            // the end has passed; no tick yet
        h.controller.updateSessionSettings(SessionSettings(autoAdvanceWorkToBreak: true))
        h.controller.refresh()
        #expect(h.controller.phase == .overtime(onBreak: false))
    }

    @Test func turningAutoAdvanceOffJustAfterTheEndDoesNotUndoTheAdvance() async {
        let h = await started(session: SessionSettings(autoAdvanceWorkToBreak: true)); defer { h.cleanUp() }
        h.clock.set(t(9, 50).addingTimeInterval(0.5))            // the break should already have begun
        h.controller.updateSessionSettings(SessionSettings(autoAdvanceWorkToBreak: false))
        h.controller.refresh()
        #expect(h.controller.phase == .onBreak)
    }

    @Test func enablingAutoAdvanceMidSegmentTakesEffectAtTheNextEnd() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        h.controller.updateSessionSettings(SessionSettings(autoAdvanceWorkToBreak: true))
        h.clock.set(t(9, 50)); h.controller.refresh()
        #expect(h.controller.phase == .onBreak)
    }

    @Test func settingsChosenBeforeADayApplyToIt() async {
        let h = Harness(); defer { h.cleanUp() }
        let chosen = SessionSettings(pausesCountAsRest: false, autoAdvanceWorkToBreak: true)
        h.controller.updateSessionSettings(chosen)
        #expect(h.settings.session == chosen)
        #expect(h.store.saved.isEmpty)                      // nothing to save without a day
        await h.startStandardDay()
        #expect(h.store.saved.last?.settings == chosen)
    }
}
