import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerActionTests {
    private func started() async -> Harness {
        let h = Harness()
        await h.startStandardDay()
        return h
    }

    @Test func quickStartBuildsTheDefaultPlanAndRuns() async {
        let h = await started(); defer { h.cleanUp() }
        #expect(h.controller.phase == .working)
        let plan = h.controller.plan
        #expect(plan.map(\.kind) == [.work, .shortBreak, .work, .shortBreak, .work, .shortBreak, .work, .shortBreak, .work])
        #expect(plan.filter { $0.kind == .work }.map(\.duration) == [3000, 3000, 3000, 3000, 2400])
        #expect(plan[0].start == t(9))
        #expect(plan[0].end == t(9, 50))
        #expect(h.store.saved.count == 1)
        #expect(h.notifier.calls.filter { $0 == .authorize }.count == 1)
    }

    @Test func quickStartDoesNothingWhileADayIsRunning() async {
        let h = await started(); defer { h.cleanUp() }
        await h.startStandardDay()
        #expect(h.store.saved.count == 1)
        #expect(h.notifier.calls.filter { $0 == .authorize }.count == 1)
    }

    @Test func pauseFreezesTheCountdownAndResumeRestartsIt() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        h.controller.pause()
        #expect(h.controller.phase == .paused(onBreak: false))
        #expect(h.controller.remaining == minutes(30))
        h.clock.set(t(9, 45))
        #expect(h.controller.remaining == minutes(30))
        h.controller.resume()
        #expect(h.controller.phase == .working)
        #expect(h.controller.remaining == minutes(30))
        #expect(h.store.saved.count == 3)
    }

    @Test func extendAddsTime() async {
        let h = await started(); defer { h.cleanUp() }
        h.controller.extend(minutes: 5)
        #expect(h.controller.remaining == minutes(55))
    }

    @Test func skipMovesToTheNextSegmentAndRecordsTheSkip() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        h.controller.skip()
        #expect(h.controller.phase == .onBreak)
        #expect(h.store.saved.last?.actuals[0].status == .skipped)
    }

    @Test func advanceLeavesOvertime() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 55))
        #expect(h.controller.phase == .overtime(onBreak: false))
        h.controller.advance()
        #expect(h.controller.phase == .onBreak)
    }

    @Test func endingTheDayAllowsANewOne() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 30))
        h.controller.endDay()
        #expect(h.controller.phase == .finished)
        h.clock.set(t(11, 0))
        await h.startStandardDay()
        #expect(h.controller.phase == .working)
        #expect(h.controller.plan[0].start == t(11, 0))
    }

    @Test func actionsThatAreNotAllowedChangeNothing() {
        let h = Harness(); defer { h.cleanUp() }
        h.controller.pause()
        h.controller.skip()
        h.controller.endDay()
        #expect(h.controller.phase == .idle)
        #expect(h.store.saved.isEmpty)
    }

    @Test func aFailingStoreDoesNotStopTheDay() async {
        let h = Harness(); defer { h.cleanUp() }
        h.store.failSave = true
        await h.startStandardDay()
        #expect(h.controller.phase == .working)
        #expect(h.store.saved.isEmpty)
    }

    @Test func progressIsTheShareOfTheSegmentThatPassed() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 25))
        #expect(h.controller.progress == 0.5)
        h.clock.set(t(9, 55))
        #expect(h.controller.progress == 1)
    }

    @Test func noProgressWithoutASegment() {
        let h = Harness(); defer { h.cleanUp() }
        #expect(h.controller.progress == nil)
    }

    @Test func lagReflectsPausedTime() async {
        let h = await started(); defer { h.cleanUp() }
        #expect(h.controller.scheduleStatus?.lag == 0)
        h.clock.set(t(9, 10)); h.controller.pause()
        h.clock.set(t(9, 20)); h.controller.resume()
        #expect(h.controller.scheduleStatus?.lag == minutes(10))
    }

    @Test func repeatedActionsAtOneInstantApplyOnce() async {
        let h = await started(); defer { h.cleanUp() }
        h.clock.set(t(9, 20))
        let before = h.store.saved.count
        h.controller.pause(); h.controller.pause()
        h.controller.resume(); h.controller.resume()
        #expect(h.store.saved.count == before + 2)
        #expect(h.controller.phase == .working)
        #expect(h.controller.remaining == minutes(30))
    }
}
