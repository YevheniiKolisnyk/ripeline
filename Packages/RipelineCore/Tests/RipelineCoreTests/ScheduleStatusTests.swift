import Foundation
import Testing
@testable import RipelineCore

struct ScheduleStatusTests {
    /// Work 50, break 10, work 50, break 10, work 50: planned 09:00–11:50.
    private let plan = makePlan([(.work, 50), (.shortBreak, 10), (.work, 50), (.shortBreak, 10), (.work, 50)])

    private func engine(startingAt start: Date = t(9)) throws -> (engine: SessionEngine, clock: ManualClock) {
        try makeEngine(plan: plan, at: start)
    }

    private func lag(_ engine: SessionEngine) -> TimeInterval? {
        engine.scheduleStatus()?.lag
    }

    @Test func idleBeforeThePlannedStartIsOnSchedule() throws {
        let (engine, _) = try engine()
        let status = try #require(engine.scheduleStatus())
        #expect(status.plannedEnd == t(11, 50))
        #expect(status.projectedEnd == t(11, 50))
        #expect(status.lag == 0)
    }

    @Test func idleAfterThePlannedStartIsBehind() throws {
        let (engine, _) = try engine(startingAt: t(9, 15))
        #expect(lag(engine) == minutes(15))
    }

    @Test func startingLateStaysBehindByTheSameAmount() throws {
        var (engine, clock) = try engine(startingAt: t(9, 15))
        try engine.start()
        clock.set(t(9, 30))
        #expect(lag(engine) == minutes(15))
    }

    @Test func pausingAddsToTheLag() throws {
        var (engine, clock) = try engine()
        try engine.start()
        clock.set(t(9, 30)); try engine.pause()
        clock.set(t(9, 40)); try engine.resume()
        #expect(lag(engine) == minutes(10))
    }

    @Test func overtimeGrowsTheLagMinuteByMinute() throws {
        var (engine, clock) = try engine()
        try engine.start()
        clock.set(t(9, 52))
        #expect(lag(engine) == minutes(2))
        clock.set(t(9, 57))
        #expect(lag(engine) == minutes(7))
        #expect(engine.snapshot.state == .running(segmentIndex: 0, endsAt: t(9, 50)))
    }

    @Test func extendingAddsToTheLag() throws {
        var (engine, clock) = try engine()
        try engine.start()
        clock.set(t(9, 10)); try engine.extend(minutes: 5)
        #expect(lag(engine) == minutes(5))
    }

    @Test func skippingMakesTheDayAheadOfSchedule() throws {
        var (engine, clock) = try engine()
        try engine.start()
        clock.set(t(9, 20)); try engine.skip()
        #expect(lag(engine) == minutes(-30))
    }

    @Test func finishedDayUsesTheRealEnd() throws {
        var (engine, clock) = try engine()
        try engine.start()
        clock.set(t(10, 30)); try engine.endDay()
        let status = try #require(engine.scheduleStatus())
        #expect(status.projectedEnd == t(10, 30))
        #expect(status.lag == minutes(-80))
    }

    @Test func finishedDayStaysFixedAsTimePasses() throws {
        var (engine, clock) = try engine()
        try engine.start()
        clock.set(t(10, 30)); try engine.endDay()
        clock.set(t(18))
        #expect(lag(engine) == minutes(-80))
    }

    @Test func noStatusWithoutAPlan() {
        let engine = SessionEngine(clock: ManualClock(t(9)))
        #expect(engine.scheduleStatus() == nil)
    }

    @Test func noStatusForADayEndedBeforeAnythingHappened() throws {
        var (engine, _) = try engine()
        try engine.endDay()
        #expect(engine.scheduleStatus() == nil)
    }
}
