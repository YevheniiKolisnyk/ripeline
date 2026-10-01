import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// What the controller tells the notifier and the ticker as the day unfolds.
@MainActor
struct SessionControllerBookkeepingTests {
    private let allAuto = SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true)

    /// A harness with a day started through the quick-start plan (work 50, break 10, …).
    private func started(session: SessionSettings? = nil) async -> Harness {
        let h = Harness(session: session)
        await h.controller.startQuickDay()
        return h
    }

    // MARK: notification scheduling

    @Test func startingSchedulesTheEndOfTheFirstSegment() async {
        let h = await started(); defer { h.cleanUp() }
        #expect(h.notifier.calls == [.authorize, .schedule(.workEnded, 3000)])
        #expect(h.ticker.isRunning)
    }

    @Test func pausingCancelsAndStopsTheTicker() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20)); h.notifier.reset()
        h.controller.pause()
        #expect(h.notifier.calls == [.cancel])
        #expect(!h.ticker.isRunning)
    }

    @Test func resumingSchedulesTheRemainingTime() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20)); h.controller.pause()
        h.clock.set(t(9, 25)); h.notifier.reset()
        h.controller.resume()
        #expect(h.notifier.calls == [.schedule(.workEnded, 1800)])
        #expect(h.ticker.isRunning)
    }

    @Test func extendingMovesTheScheduledTime() async {
        let h = await started(); defer { h.cleanUp() }
        h.notifier.reset()
        h.controller.extend(minutes: 5)
        #expect(h.notifier.calls == [.schedule(.workEnded, 3300)])
    }

    @Test func skippingCancelsTheOldRequestAndSchedulesTheBreakEnd() async {
        let h = await started(); defer { h.cleanUp() }
        let firstID = h.notifier.scheduledIDs[0]
        h.clock.set(t(9, 20)); h.notifier.reset()
        h.controller.skip()
        #expect(h.notifier.calls == [.cancel, .schedule(.breakEnded, 600)])
        #expect(h.notifier.cancelledIDs == [firstID])
        #expect(h.notifier.scheduledIDs != [firstID])
    }

    @Test func endingTheDayCancelsAndStopsTheTicker() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 30)); h.notifier.reset()
        h.controller.endDay()
        #expect(h.notifier.calls == [.cancel])
        #expect(!h.ticker.isRunning)
    }

    /// The request for the segment end is due at this very moment: cancelling it would swallow it.
    @Test func ordinaryExpiryLeavesTheDueNotificationAlone() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 50)); h.notifier.reset()
        h.controller.refresh()
        #expect(h.controller.phase == .overtime(onBreak: false))
        #expect(h.notifier.calls.isEmpty)
        #expect(h.ticker.isRunning)
    }

    @Test func pausingCancelsTheRequestItScheduled() async {
        let h = await started(); defer { h.cleanUp() }
        let id = h.notifier.scheduledIDs[0]
        h.clock.set(t(9, 20)); h.controller.pause()
        #expect(h.notifier.cancelledIDs == [id])
    }

    @Test func eachSegmentHasItsOwnRequest() async {
        let h = await started(session: SessionSettings(autoAdvanceWorkToBreak: true)); defer { h.cleanUp() }
        let first = h.notifier.scheduledIDs[0]
        h.clock.set(t(9, 50)); h.controller.refresh()
        #expect(h.notifier.scheduledIDs.count == 2)
        #expect(h.notifier.scheduledIDs[1] != first)       // the next segment never replaces the one that is due
        #expect(h.notifier.cancelledIDs.isEmpty)
    }

    @Test func extendingKeepsTheSameRequest() async {
        let h = await started(); defer { h.cleanUp() }
        h.controller.extend(minutes: 5)
        #expect(Set(h.notifier.scheduledIDs).count == 1)
        #expect(h.notifier.cancelledIDs.isEmpty)
    }

    @Test func advancingOutOfOvertimeSchedulesTheBreak() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 55)); h.controller.refresh(); h.notifier.reset()
        h.controller.advance()
        #expect(h.notifier.calls == [.schedule(.breakEnded, 600)])
    }

    @Test func autoAdvanceSchedulesTheNextSegmentWithoutDelivering() async {
        let h = await started(session: SessionSettings(autoAdvanceWorkToBreak: true)); defer { h.cleanUp() }
        h.clock.set(t(9, 50)); h.notifier.reset()
        h.controller.refresh()
        #expect(h.controller.phase == .onBreak)
        #expect(h.notifier.calls == [.schedule(.breakEnded, 600)])
    }

    // MARK: idempotence and the ticker

    @Test func refreshingTwiceAtOneInstantChangesNothing() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        h.controller.refresh()
        let calls = h.notifier.calls, saves = h.store.saved.count
        h.controller.refresh()
        h.controller.refresh()
        #expect(h.notifier.calls == calls)
        #expect(h.store.saved.count == saves)
    }

    @Test func theTickerCallsRefresh() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 30))
        h.ticker.fire()
        #expect(h.controller.now == t(9, 30))
    }

    @Test func theTickerRunsOnlyWhileRunningOrInOvertime() async {
        let h = await started(); defer { h.cleanUp() }
        #expect(h.ticker.isRunning)
        h.clock.set(t(9, 55)); h.controller.refresh()
        #expect(h.ticker.isRunning)                                  // overtime
        h.controller.advance()
        #expect(h.ticker.isRunning)                                  // break running
        h.controller.pause()
        #expect(!h.ticker.isRunning)                                 // paused
        h.controller.resume(); h.controller.endDay()
        #expect(!h.ticker.isRunning)                                 // finished
    }

    // MARK: relaunch

    @Test func relaunchAfterOneEndDeliversOnceAndCancels() throws {
        let h = Harness(now: t(9, 55), stored: try startedSnapshot()); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.notifier.calls == [.deliver(.workEnded), .cancelAll])
        #expect(h.ticker.isRunning)
    }

    @Test func relaunchAfterSeveralEndsDeliversOneSummary() throws {
        let h = Harness(now: t(11, 15), stored: try startedSnapshot(settings: allAuto)); defer { h.cleanUp() }
        h.controller.restore()
        // Segment 3 (a break) ended last; the final work block is running.
        #expect(h.notifier.calls == [.deliver(.breakEnded), .schedule(.dayFinished, 2100)])
    }

    @Test func relaunchPastTheEndOfTheDayDeliversDayFinished() throws {
        let h = Harness(now: t(14), stored: try startedSnapshot(settings: allAuto)); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .finished)
        #expect(h.notifier.calls == [.deliver(.dayFinished), .cancelAll])
        #expect(!h.ticker.isRunning)
    }

    @Test func relaunchWithNothingCrossedOnlySchedules() throws {
        let h = Harness(now: t(9, 20), stored: try startedSnapshot()); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.notifier.calls == [.schedule(.workEnded, 1800)])
    }

    // MARK: authorization and unavailable notifications

    @Test func authorizationIsRequestedOncePerLaunch() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 30)); h.controller.endDay()
        await h.controller.startQuickDay()
        #expect(h.notifier.calls.filter { $0 == .authorize }.count == 1)
    }

    @Test func theDayWorksWhenNotificationsAreUnavailable() async {
        let h = Harness(); defer { h.cleanUp() }
        h.notifier.recording = false
        await h.controller.startQuickDay()
        h.clock.set(t(9, 10)); h.controller.pause()
        h.clock.set(t(9, 15)); h.controller.resume()
        h.controller.skip()
        #expect(h.controller.phase == .onBreak)
        h.controller.endDay()
        #expect(h.controller.phase == .finished)
        #expect(h.notifier.calls.isEmpty)
    }
}
