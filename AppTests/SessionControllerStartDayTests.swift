import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerStartDayTests {
    private func request(
        focus: Int = 100,
        preset: Preset = Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15),
        start: Date = t(9)
    ) -> DayPlanRequest {
        DayPlanRequest(
            mode: .netFocus(start: start, focusMinutes: focus), longBreak: .none,
            remainderStrategy: .leaveFree, preset: preset
        )
    }

    @Test func startsExactlyTheRequestedPlan() async throws {
        let h = Harness(); defer { h.cleanUp() }
        let req = request()
        let started = await h.controller.startDay(request: req)
        #expect(started)
        let expected = try PlanGenerator.generate(req)
        #expect(h.controller.plan.map(\.kind) == expected.map(\.kind))
        #expect(h.controller.plan.map(\.start) == expected.map(\.start))
        #expect(h.controller.plan.map(\.end) == expected.map(\.end))
        #expect(h.controller.phase == .working)
        #expect(h.controller.plan[0].end == t(9, 25))
        #expect(h.store.saved.count == 1)
        #expect(h.notifier.calls.filter { $0 == .authorize }.count == 1)
    }

    @Test func refusesWhileADayIsRunning() async {
        let h = Harness(); defer { h.cleanUp() }
        await h.controller.startDay(request: request())
        let saves = h.store.saved.count
        let started = await h.controller.startDay(request: request(focus: 200))
        #expect(!started)
        #expect(h.store.saved.count == saves)
        #expect(h.notifier.calls.filter { $0 == .authorize }.count == 1)
        #expect(h.controller.plan.count == 7)       // still the first day: 4 blocks of 25 + 3 breaks
    }

    @Test func startsAgainAfterTheDayEnds() async {
        let h = Harness(); defer { h.cleanUp() }
        await h.controller.startDay(request: request())
        h.clock.set(t(9, 30)); h.controller.endDay()
        h.clock.set(t(10)); h.controller.refresh()
        let started = await h.controller.startDay(request: request(start: t(10)))
        #expect(started)
        #expect(h.controller.plan[0].start == t(10))
    }

    @Test func aRequestTheGeneratorRejectsStartsNothing() async {
        let h = Harness(); defer { h.cleanUp() }
        let bad = request(preset: Preset(workMinutes: 0, shortBreakMinutes: 5, longBreakMinutes: 15))
        let started = await h.controller.startDay(request: bad)
        #expect(!started)
        #expect(h.controller.phase == .idle)
        #expect(h.store.saved.isEmpty)
        #expect(h.notifier.calls.isEmpty)           // no permission prompt for a day that cannot start
    }

    @Test func theCountdownFollowsTheClockNotTheRequestsStart() async {
        let h = Harness(now: t(9)); defer { h.cleanUp() }
        await h.controller.startDay(request: request(start: t(8)))
        #expect(h.controller.remaining == minutes(25))
    }
}
