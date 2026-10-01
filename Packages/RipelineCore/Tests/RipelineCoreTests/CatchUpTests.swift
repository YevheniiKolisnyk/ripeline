import Foundation
import Testing
@testable import RipelineCore

/// The Mac sleeps (or the app is suspended) and a single `tick()` arrives much later.
struct CatchUpTests {
    /// Work 50, break 10, work 50, break 10, work 50: 09:00–11:50.
    private let plan = makePlan([(.work, 50), (.shortBreak, 10), (.work, 50), (.shortBreak, 10), (.work, 50)])

    private func started(_ settings: SessionSettings) throws -> (engine: SessionEngine, clock: ManualClock) {
        var (engine, clock) = try makeEngine(plan: plan, settings: settings)
        try engine.start()
        return (engine, clock)
    }

    private let allAuto = SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true)

    @Test func autoAdvanceWalksThroughEverySegmentThatEndedMeanwhile() throws {
        var (engine, clock) = try started(allAuto)
        clock.set(t(11, 15))
        engine.tick()
        let actuals = engine.snapshot.actuals
        #expect(actuals.map(\.status) == [.completed, .completed, .completed, .completed, .active])
        #expect(recorded(actuals[0]) == [workedFor(t(9, 0), t(9, 50))])
        #expect(recorded(actuals[1]) == [rested(t(9, 50), t(10, 0))])
        #expect(recorded(actuals[2]) == [workedFor(t(10, 0), t(10, 50))])
        #expect(recorded(actuals[3]) == [rested(t(10, 50), t(11, 0))])
        #expect(engine.state == .running(segmentIndex: 4, endsAt: t(11, 50)))
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .work, start: t(11, 0)))
        #expect(engine.remainingTime() == minutes(35))
    }

    @Test func withoutAutoAdvanceTheEngineEndsInOvertimeOfTheRunningSegment() throws {
        var (engine, clock) = try started(SessionSettings())
        clock.set(t(11, 15))
        engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
        #expect(engine.snapshot.actuals.map(\.status) == [.active, .notStarted, .notStarted, .notStarted, .notStarted])
        #expect(engine.overtimeElapsed() == minutes(85))
    }

    @Test func partialAutoAdvanceStopsWhereTheFlagIsOff() throws {
        var (engine, clock) = try started(SessionSettings(autoAdvanceWorkToBreak: true))
        clock.set(t(11, 15))
        engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 1, since: t(10, 0)))
        #expect(engine.snapshot.actuals.map(\.status) == [.completed, .active, .notStarted, .notStarted, .notStarted])
        #expect(recorded(engine.snapshot.actuals[1]) == [rested(t(9, 50), t(10, 0))])
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .rest, start: t(10, 0)))
    }

    @Test func autoAdvancePastTheEndOfThePlanFinishesAtTheRealEndTime() throws {
        var (engine, clock) = try started(allAuto)
        clock.set(t(14))
        engine.tick()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals.allSatisfy { $0.status == .completed })
        #expect(engine.snapshot.actuals[4].intervals.last?.end == t(11, 50))
        #expect(engine.snapshot.openInterval == nil)
    }

    @Test func aPausedSegmentDoesNotAdvanceWhileTheMacSleeps() throws {
        var (engine, clock) = try started(allAuto)
        clock.set(t(9, 20)); try engine.pause()
        clock.set(t(14))
        engine.tick()
        #expect(engine.state == .paused(segmentIndex: 0, remaining: minutes(30)))
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .rest, start: t(9, 20)))
    }

    @Test func aGapOfDaysTerminates() throws {
        var (engine, clock) = try started(allAuto)
        clock.set(t(9).addingTimeInterval(3 * 24 * 3600))
        engine.tick()
        #expect(engine.state == .finished)
    }

    // MARK: actions after a sleep

    @Test func actionsCatchUpBeforeTheyApply() throws {
        var (engine, clock) = try started(SessionSettings())
        clock.set(t(11, 15))
        #expect(throws: SessionError.notAllowed(.pause)) { try engine.pause() }
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
    }

    @Test func pausingAfterASleepWithAutoAdvancePausesTheSegmentThatIsNowRunning() throws {
        var (engine, clock) = try started(allAuto)
        clock.set(t(11, 15))
        try engine.pause()
        #expect(engine.state == .paused(segmentIndex: 4, remaining: minutes(35)))
        #expect(engine.snapshot.actuals[3].status == .completed)
    }

    @Test func advancingAfterASleepRecordsTheWholeOvertime() throws {
        var (engine, clock) = try started(SessionSettings())
        clock.set(t(11, 15))
        try engine.advance()
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9, 0), t(9, 50)), workedFor(t(9, 50), t(11, 15))])
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(11, 25)))
    }

    @Test func readingTheCountdownDoesNotChangeTheEngine() throws {
        var (engine, clock) = try started(allAuto)
        clock.set(t(11, 15))
        let before = engine.snapshot
        #expect(engine.remainingTime() == minutes(35))
        #expect(engine.snapshot == before)
        engine.tick()
        #expect(engine.remainingTime() == minutes(35))
    }
}
