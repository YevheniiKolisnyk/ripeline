import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerQuickTests {
    private func started(_ length: QuickBlockLength = .short) async -> Harness {
        let h = Harness()
        await h.controller.startQuickSession(length: length)
        await settleBackgroundWork()
        return h
    }

    // MARK: starting

    @Test func aBlockStartsAtOnce() async {
        let h = Harness(); defer { h.cleanUp() }
        let started = await h.controller.startQuickSession(length: .short)
        await settleBackgroundWork()
        #expect(started)
        #expect(h.controller.phase == .working)
        #expect(h.controller.isQuickSession)
        #expect(h.controller.plan.count == 1)
        #expect(h.controller.plan[0].duration == minutes(25))
        #expect(h.controller.plan[0].start == t(9))
        #expect(h.store.saved.count == 1)
        #expect(h.store.saved[0].kind == .quick)
        #expect(h.settings.quickBlockLength == .short)
        #expect(h.notifier.calls.filter { $0 == .authorize }.count == 1)
    }

    @Test(arguments: [(QuickBlockLength.medium, 50), (.long, 90)])
    func otherLengths(length: QuickBlockLength, minutesLong: Int) async {
        let h = await started(length); defer { h.cleanUp() }
        #expect(h.controller.plan[0].duration == minutes(minutesLong))
        #expect(h.settings.quickBlockLength == length)           // remembered for next time
    }

    @Test func aRunningDayOrSessionRefusesAnotherStart() async {
        let day = Harness(); defer { day.cleanUp() }
        await day.startStandardDay()
        let saves = day.store.saved.count
        #expect(await day.controller.startQuickSession(length: .short) == false)
        #expect(day.store.saved.count == saves)
        #expect(!day.controller.isQuickSession)

        let quick = await started(); defer { quick.cleanUp() }
        let quickSaves = quick.store.saved.count
        #expect(await quick.controller.startQuickSession(length: .long) == false)
        #expect(quick.store.saved.count == quickSaves)
        #expect(quick.controller.plan[0].duration == minutes(25))
    }

    @Test func afterTheSessionEndsAnotherCanStart() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 10)); h.controller.endDay()
        h.clock.set(t(10))
        #expect(await h.controller.startQuickSession(length: .medium))
        #expect(h.controller.plan[0].start == t(10))
        #expect(h.controller.plan.count == 1)
    }

    @Test func anOrdinaryDayIsStillADay() async {
        let h = Harness(); defer { h.cleanUp() }
        await h.startStandardDay()
        #expect(h.store.saved[0].kind == .day)
        #expect(!h.controller.isQuickSession)
    }

    // MARK: notifications (Review Focus 3)

    @Test func theFirstBlockSaysBlockFinishedNotDayFinished() async {
        let h = await started(); defer { h.cleanUp() }
        #expect(h.notifier.calls == [.schedule(.workEnded, 1500), .authorize])
    }

    @Test func everyAddedSegmentGetsItsNotification() async {
        let h = await started(); defer { h.cleanUp() }
        h.controller.addBlock()
        h.notifier.reset()
        h.clock.set(t(9, 25)); h.controller.refresh()                 // the first block ran out
        h.controller.advance()                                        // into the added break
        #expect(h.notifier.calls == [.schedule(.breakEnded, 300)])
        h.notifier.reset()
        h.clock.set(t(9, 30)); h.controller.refresh()
        h.controller.advance()                                        // into the added block, which is the last segment so far
        #expect(h.notifier.calls == [.schedule(.workEnded, 1500)])   // never "day finished"
    }

    // MARK: adding blocks

    @Test func anotherBlockIsAddedBehindTheRunningOne() async {
        let h = await started(); defer { h.cleanUp() }
        h.notifier.reset()
        let saves = h.store.saved.count
        h.controller.addBlock()
        #expect(h.controller.plan.map(\.kind) == [.work, .shortBreak, .work])
        #expect(h.controller.plan[1].duration == minutes(5))
        #expect(h.controller.plan[2].duration == minutes(25))
        #expect(h.controller.phase == .working)
        #expect(h.store.saved.count == saves + 1)
        #expect(h.notifier.calls.isEmpty)                             // the running segment's request is unchanged
    }

    @Test func aBlockCanBeAddedDuringAPause() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 10)); h.controller.pause()
        h.notifier.reset()
        h.controller.addBlock()
        #expect(h.controller.plan.count == 3)
        #expect(h.controller.phase == .paused(onBreak: false))
        #expect(h.notifier.calls.isEmpty)
        h.clock.set(t(9, 15)); h.controller.resume()
        #expect(h.notifier.calls == [.schedule(.workEnded, 900)])
    }

    @Test func aBlockCanBeAddedInOvertime() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 30)); h.controller.refresh()
        #expect(h.controller.phase == .overtime(onBreak: false))
        h.controller.addBlock()
        h.controller.advance()
        #expect(h.controller.phase == .onBreak)
    }

    /// Review finding: with auto-advance on, the last block waits in overtime, so "Another block" is still there.
    @Test func withAutoAdvanceTheLastBlockWaitsInOvertimeAndOffersAnotherBlock() async {
        let h = Harness(session: SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true))
        defer { h.cleanUp() }
        await h.controller.startQuickSession(length: .short)
        await settleBackgroundWork()
        h.clock.set(t(9, 30)); h.controller.refresh()
        #expect(h.controller.phase == .overtime(onBreak: false))
        #expect(PopoverActions.visible(phase: h.controller.phase, isQuick: true, isAllowed: h.controller.isAllowed).contains(.addBlock))
        h.controller.addBlock()
        #expect(h.controller.plan.count == 3)
        h.controller.advance()
        #expect(h.controller.phase == .onBreak)
    }

    @Test func manyBlocks() async {
        let h = await started(); defer { h.cleanUp() }
        for _ in 0..<5 { h.controller.addBlock() }
        #expect(h.controller.plan.count == 11)
        #expect(h.controller.isQuickSession)
    }

    @Test func nothingIsAddedToADayOrToNoDay() async {
        let day = Harness(); defer { day.cleanUp() }
        await day.startStandardDay()
        let count = day.controller.plan.count
        day.controller.addBlock()
        #expect(day.controller.plan.count == count)

        let none = Harness(); defer { none.cleanUp() }
        none.controller.addBlock()
        #expect(none.controller.plan.isEmpty && none.store.saved.isEmpty)
    }

    // MARK: the usual controls and finishing

    @Test func extendSkipAndDone() async {
        let h = await started(); defer { h.cleanUp() }
        h.controller.addBlock()
        h.controller.extend(minutes: 5)
        #expect(h.controller.remaining == minutes(30))
        h.clock.set(t(9, 10)); h.controller.skip()
        #expect(h.controller.phase == .onBreak)
        h.clock.set(t(9, 12)); h.controller.endDay()
        #expect(h.controller.phase == .finished)
        #expect(h.controller.activeDayID == nil)
    }

    @Test func skippingTheOnlyBlockFinishesTheSession() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 10)); h.controller.skip()
        #expect(h.controller.phase == .finished)
    }

    // MARK: relaunch (Review Focus 5)

    private func threeBlocks(from start: Date) -> [PlannedSegment] {
        var plan = QuickSession.plan(length: .short, start: start)
        plan += QuickSession.nextBlocks(after: plan)
        plan += QuickSession.nextBlocks(after: plan)
        return plan
    }

    @Test func aSessionWithSeveralBlocksSurvivesARelaunch() throws {
        let snapshot = try playedDay(plan: threeBlocks(from: t(9)), kind: .quick) { engine, _ in try engine.start() }
        let h = Harness(now: t(9, 10), stored: snapshot); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.plan.count == 5)
        #expect(h.controller.isQuickSession)
        #expect(h.controller.phase == .working)
        #expect(h.notifier.calls == [.schedule(.workEnded, 900)])
        h.controller.addBlock()
        #expect(h.controller.plan.count == 7)
    }

    @Test func aQuickSessionLeftFromYesterdayStartsFresh() throws {
        let snapshot = try playedDay(plan: threeBlocks(from: d(14, 9)), kind: .quick) { engine, _ in try engine.start() }
        let h = Harness(now: d(15, 9), stored: snapshot); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .idle)
        #expect(h.controller.plan.isEmpty)
        #expect(h.store.quarantined.isEmpty)                          // the file is kept
    }
}
