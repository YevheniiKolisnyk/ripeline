import Foundation
import Testing
@testable import RipelineCore

struct TomatoTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    /// Work 25, break 5, work 25 from 09:00, started at 09:00.
    private func started(kind: SessionKind = .day) throws -> (engine: SessionEngine, clock: ManualClock) {
        let clock = ManualClock(t(9))
        var engine = SessionEngine(clock: clock)
        try engine.startDay(plan: makePlan([(.work, 25), (.shortBreak, 5), (.work, 25)]), settings: SessionSettings(), kind: kind)
        try engine.start()
        return (engine, clock)
    }

    @Test func aBlockGrowsWithTheWorkDoneAndIsFullAtThePlannedLength() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 10))
        var first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 0.4))
        #expect(first.availability == .growing)
        clock.set(t(9, 25))
        first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 1))
        #expect(first.availability == .pickable)          // it waits in overtime
    }

    @Test func aPauseDoesNotGrowTheTomato() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        clock.set(t(9, 10)); try engine.pause()
        clock.set(t(9, 20)); try engine.resume()
        clock.set(t(9, 25))
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.workTime, minutes(15)))
        #expect(close(first.growth, 0.6))
        #expect(first.availability == .growing)
    }

    /// Review focus 1: extra time grows the tomato past 100% but it stays unpickable while the block runs.
    @Test func anExtendedBlockGrowsPastFullButIsNotPickableWhileItRuns() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        clock.set(t(9, 20)); try engine.extend(minutes: 10)       // now ends at 09:35
        clock.set(t(9, 30))
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 1.2))
        #expect(first.availability == .growing)
        clock.set(t(9, 35))                                        // the extension ran out: overtime
        #expect(try #require(engine.tomatoes().first).availability == .pickable)
    }

    @Test func overtimeKeepsGrowingTheTomato() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 40))                                        // 15 minutes past the plan
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 1.6))
        #expect(first.availability == .pickable)
    }

    @Test func aSkippedBlockIsPickableWhenSomeWorkWasDone() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        clock.set(t(9, 10)); try engine.skip()
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 0.4))
        #expect(first.availability == .pickable)
    }

    @Test func aBlockSkippedBeforeAnyWorkGivesNothing() throws {
        var engine = try started().engine
        try engine.skip()
        let first = try #require(engine.tomatoes().first)
        #expect(first.workTime == 0)
        #expect(first.availability == .empty)
    }

    @Test func breaksGiveNoTomatoAndIdsAreTheSegmentIds() throws {
        let (engine, _) = try started()
        let tomatoes = engine.tomatoes()
        let plan = engine.snapshot.plan
        #expect(tomatoes.map(\.segmentIndex) == [0, 2])
        #expect(tomatoes.map(\.id) == [plan[0].id, plan[2].id])
        #expect(tomatoes.map(\.plannedTime) == [minutes(25), minutes(25)])
    }

    @Test func aBlockThatHasNotStartedIsUpcomingUntilItsDayEnds() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        #expect(engine.tomatoes()[1].availability == .upcoming)
        #expect(engine.tomatoes()[1].growth == 0)
        clock.set(t(9, 10)); try engine.endDay()
        #expect(engine.tomatoes()[0].availability == .pickable)
        #expect(engine.tomatoes()[1].availability == .empty)
    }

    @Test func aDayThatIsLoadedButNotStartedHasOnlyUpcomingTomatoes() throws {
        let (engine, _) = try makeEngine(plan: makePlan([(.work, 25), (.shortBreak, 5), (.work, 25)]))
        #expect(engine.tomatoes().map(\.availability) == [.upcoming, .upcoming])
    }

    @Test func aQuickSessionGivesATomatoToEveryBlockItGrows() throws {
        let clock = ManualClock(t(9))
        var engine = SessionEngine(clock: clock)
        try engine.startDay(plan: makePlan([(.work, 25)]), settings: SessionSettings(), kind: .quick)
        try engine.start()
        try engine.appendSegments([
            PlannedSegment(index: 1, kind: .shortBreak, start: t(9, 25), end: t(9, 30)),
            PlannedSegment(index: 2, kind: .work, start: t(9, 30), end: t(9, 55)),
        ])
        #expect(engine.tomatoes().map(\.segmentIndex) == [0, 2])
        #expect(engine.tomatoes()[1].availability == .upcoming)
    }

    @Test func readingTomatoesNeverChangesTheEngine() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 40))
        let before = engine.snapshot
        _ = engine.tomatoes()
        #expect(engine.snapshot == before)
    }

    @Test func aClockSetBackNeverGivesNegativeWork() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 10))
        _ = engine.tomatoes()
        clock.set(t(8, 0))
        let first = try #require(engine.tomatoes().first)
        #expect(first.workTime >= 0)
    }

    /// Review finding: a stored day whose block was still running when the app was closed is not running any more,
    /// so its tomato can be picked instead of waiting for ever.
    @Test func aSettledDayLetsAStillRunningBlockBePicked() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 10))
        let running = engine.tomatoes()
        #expect(running[0].availability == .growing && running[1].availability == .upcoming)
        let settled = Tomatoes.of(engine.snapshot, at: t(9, 10), settled: true)
        #expect(close(settled[0].growth, 0.4))
        #expect(settled[0].availability == .pickable)
        #expect(settled[1].availability == .empty)                 // it never started and now never will
    }

    @Test func aSettledBlockWithNoWorkGivesNothing() throws {
        let (engine, _) = try started()
        let settled = Tomatoes.of(engine.snapshot, at: t(9), settled: true)
        #expect(settled[0].availability == .empty)
    }
}
