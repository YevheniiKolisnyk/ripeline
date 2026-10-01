import Foundation
import Testing
@testable import RipelineCore

struct SegmentExpiryTests {
    private func started(
        plan: [PlannedSegment] = shortPlan(), settings: SessionSettings = SessionSettings()
    ) throws -> (engine: SessionEngine, clock: ManualClock) {
        var (engine, clock) = try makeEngine(plan: plan, settings: settings)
        try engine.start()
        return (engine, clock)
    }

    private func total(_ actual: SegmentActual, _ kind: ActualKind) -> TimeInterval {
        actual.intervals.filter { $0.kind == kind }.reduce(0) { $0 + $1.duration }
    }

    // MARK: overtime

    @Test func workSegmentThatRunsOutEntersOvertimeAndKeepsRecordingWork() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 52))
        engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
        #expect(engine.snapshot.actuals[0].status == .active)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 50))])
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .work, start: t(9, 50)))
        #expect(recorded(engine.snapshot.actuals(at: t(9, 52))[0]) == [
            workedFor(t(9), t(9, 50)), workedFor(t(9, 50), t(9, 52)),
        ])
        #expect(engine.overtimeElapsed() == minutes(2))
        #expect(engine.remainingTime() == 0)
    }

    @Test func breakOvertimeIsRecordedAsRest() throws {
        var (engine, clock) = try started(plan: makePlan([(.shortBreak, 10), (.work, 50)]))
        clock.set(t(9, 13))
        engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 10)))
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .rest, start: t(9, 10)))
    }

    @Test func fortyFiveMinuteBreakThatTookFortySeven() throws {
        let plan = makePlan([(.work, 50), (.longBreak, 45), (.work, 50)])
        var (engine, clock) = try started(plan: plan)
        clock.set(t(9, 50)); try engine.advance()
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 35)))
        clock.set(t(10, 37)); try engine.advance()
        #expect(engine.snapshot.actuals[1].status == .completed)
        #expect(total(engine.snapshot.actuals[1], .rest) == minutes(47))
        #expect(engine.state == .running(segmentIndex: 2, endsAt: t(11, 27)))
    }

    // MARK: auto-advance

    @Test func workToBreakAutoAdvanceStartsTheBreakAtTheExactEndTime() throws {
        var (engine, clock) = try started(settings: SessionSettings(autoAdvanceWorkToBreak: true))
        clock.set(t(9, 50))
        engine.tick()
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 0)))
        #expect(engine.snapshot.actuals[0].status == .completed)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 50))])
        #expect(engine.snapshot.actuals[1].status == .active)
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .rest, start: t(9, 50)))
    }

    @Test func breakToWorkAutoAdvanceAppliesOnlyToBreaks() throws {
        var (engine, clock) = try started(settings: SessionSettings(autoAdvanceBreakToWork: true))
        clock.set(t(9, 50)); engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
        try engine.advance()
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 0)))
        clock.set(t(10, 0)); engine.tick()
        #expect(engine.state == .running(segmentIndex: 2, endsAt: t(10, 50)))
        #expect(engine.snapshot.actuals[1].status == .completed)
    }

    @Test func lastSegmentWithAutoAdvanceFinishesTheDay() throws {
        var (engine, clock) = try started(
            plan: makePlan([(.work, 50)]), settings: SessionSettings(autoAdvanceWorkToBreak: true)
        )
        clock.set(t(9, 50)); engine.tick()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals[0].status == .completed)
        #expect(engine.snapshot.openInterval == nil)
    }

    @Test func lastSegmentWithoutAutoAdvanceWaitsInOvertimeThenFinishes() throws {
        var (engine, clock) = try started(plan: makePlan([(.work, 50)]))
        clock.set(t(9, 55)); engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
        try engine.advance()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals[0].status == .completed)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 50)), workedFor(t(9, 50), t(9, 55))])
    }

    // MARK: extend

    @Test func extendWhileRunningMovesTheEnd() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 10)); try engine.extend(minutes: 5)
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 55)))
    }

    @Test func extendWhilePausedAddsToRemainingTime() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 10)); try engine.pause()
        try engine.extend(minutes: 5)
        #expect(engine.state == .paused(segmentIndex: 0, remaining: minutes(45)))
    }

    @Test func extendFromOvertimeResumesCountdownFromNow() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 53)); try engine.extend(minutes: 5)
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 58)))
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 50)), workedFor(t(9, 50), t(9, 53))])
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .work, start: t(9, 53)))
        #expect(engine.snapshot.actuals[0].status == .active)
    }

    @Test(arguments: [0, -5])
    func extendRejectsNonPositiveMinutes(value: Int) throws {
        var (engine, _) = try started()
        #expect(throws: SessionError.nonPositiveExtension) { try engine.extend(minutes: value) }
    }

    // MARK: skip

    @Test func skipWhileRunningKeepsTimeSpentAndStartsNextSegment() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 20)); try engine.skip()
        #expect(engine.snapshot.actuals[0].status == .skipped)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 20))])
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(9, 30)))
        #expect(engine.snapshot.actuals[1].status == .active)
    }

    @Test func skipWhilePausedKeepsThePauseAndStartsNextSegment() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 20)); try engine.pause()
        clock.set(t(9, 25)); try engine.skip()
        #expect(engine.snapshot.actuals[0].status == .skipped)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 20)), rested(t(9, 20), t(9, 25))])
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(9, 35)))
    }

    @Test func skipFromOvertimeCompletesTheSegment() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 53)); try engine.skip()
        #expect(engine.snapshot.actuals[0].status == .completed)
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 3)))
    }

    @Test func skippingTheLastSegmentFinishesTheDay() throws {
        var (engine, clock) = try started(plan: makePlan([(.work, 50)]))
        clock.set(t(9, 10)); try engine.skip()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals[0].status == .skipped)
    }

    // MARK: advance and endDay in overtime

    @Test func advanceLeavesOvertimeAndStartsTheNextSegment() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 53)); try engine.advance()
        #expect(engine.snapshot.actuals[0].status == .completed)
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 3)))
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .rest, start: t(9, 53)))
    }

    @Test func advanceIsNotAllowedWhileRunning() throws {
        var (engine, _) = try started()
        #expect(throws: SessionError.notAllowed(.advance)) { try engine.advance() }
    }

    @Test func endDayFromOvertimeCompletesTheSegment() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 53)); try engine.endDay()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals[0].status == .completed)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 50)), workedFor(t(9, 50), t(9, 53))])
    }

    // MARK: clock going backwards

    @Test func clockSetBackNeverProducesNegativeIntervals() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 20)); try engine.pause()
        clock.set(t(9, 10)); try engine.resume()
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 50)))
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 20))])
        clock.set(t(9, 30))
        #expect(recorded(engine.snapshot.actuals(at: t(9, 30))[0]).allSatisfy { $0.end > $0.start })
    }

    @Test func tickWithAnEarlierClockChangesNothing() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 30)); try engine.pause()
        let before = engine.snapshot
        clock.set(t(8, 0))
        engine.tick()
        #expect(engine.snapshot == before)
    }

    // MARK: reads reflect the current time without a tick

    /// Review finding: the UI reads `state` and `isAllowed` between ticks and after waking.
    @Test func stateAndAllowedActionsAreCurrentEvenBeforeATick() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 51))
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
        #expect(engine.isAllowed(.pause) == false)
        #expect(engine.isAllowed(.advance) == true)
        #expect(engine.isAllowed(.extend) == true)
    }

    // MARK: settings changed mid-day

    @Test func turningAutoAdvanceOffMidDayAppliesToTheNextExpiry() throws {
        var (engine, clock) = try started(settings: SessionSettings(autoAdvanceWorkToBreak: true))
        clock.set(t(9, 20))
        engine.updateSettings(SessionSettings(autoAdvanceWorkToBreak: false))
        clock.set(t(9, 55)); engine.tick()
        #expect(engine.state == .overtime(segmentIndex: 0, since: t(9, 50)))
    }

    @Test func turningAutoAdvanceOnMidDayAppliesToTheNextExpiry() throws {
        var (engine, clock) = try started()
        clock.set(t(9, 20))
        engine.updateSettings(SessionSettings(autoAdvanceWorkToBreak: true))
        clock.set(t(9, 50)); engine.tick()
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 0)))
    }

    @Test(arguments: [(true, ActualKind.rest), (false, ActualKind.untracked)])
    func pausingRightAfterABreakAutoAdvancesIntoWorkFollowsThePauseSetting(restOn: Bool, kind: ActualKind) throws {
        let plan = makePlan([(.shortBreak, 10), (.work, 50)])
        var (engine, clock) = try started(
            plan: plan, settings: SessionSettings(pausesCountAsRest: restOn, autoAdvanceBreakToWork: true)
        )
        clock.set(t(9, 10)); engine.tick()
        #expect(engine.state == .running(segmentIndex: 1, endsAt: t(10, 0)))
        try engine.pause()
        clock.set(t(9, 15)); try engine.resume()
        #expect(recorded(engine.snapshot.actuals[1]) == [Recorded(kind: kind, start: t(9, 10), end: t(9, 15))])
    }
}
