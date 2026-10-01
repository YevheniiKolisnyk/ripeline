import Foundation
import Testing
@testable import RipelineCore

struct PauseTests {
    /// Work 09:00, pause 09:35, resume 09:37, read at 09:40.
    private func spec(pausesCountAsRest: Bool) throws -> (SessionEngine, ManualClock) {
        var (engine, clock) = try makeEngine(settings: SessionSettings(pausesCountAsRest: pausesCountAsRest))
        try engine.start()
        clock.set(t(9, 35)); try engine.pause()
        clock.set(t(9, 37)); try engine.resume()
        clock.set(t(9, 40))
        return (engine, clock)
    }

    @Test func pauseCountsAsRestWhenConfigured() throws {
        let (engine, _) = try spec(pausesCountAsRest: true)
        let first = engine.snapshot.actuals(at: t(9, 40))[0]
        #expect(recorded(first) == [
            workedFor(t(9, 0), t(9, 35)), rested(t(9, 35), t(9, 37)), workedFor(t(9, 37), t(9, 40)),
        ])
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 52)))
        #expect(engine.remainingTime() == minutes(12))
    }

    @Test func pauseIsUntrackedWhenRestIsOff() throws {
        let (engine, _) = try spec(pausesCountAsRest: false)
        let first = engine.snapshot.actuals(at: t(9, 40))[0]
        #expect(recorded(first) == [
            workedFor(t(9, 0), t(9, 35)), untracked(t(9, 35), t(9, 37)), workedFor(t(9, 37), t(9, 40)),
        ])
        #expect(engine.remainingTime() == minutes(12))
    }

    @Test(arguments: [(true, ActualKind.rest), (false, ActualKind.untracked)])
    func pausingABreakKeepsItsRemainingTime(restOn: Bool, pauseKind: ActualKind) throws {
        let plan = makePlan([(.shortBreak, 10), (.work, 50)])
        var (engine, clock) = try makeEngine(plan: plan, settings: SessionSettings(pausesCountAsRest: restOn))
        try engine.start()
        clock.set(t(9, 5)); try engine.pause()
        #expect(engine.state == .paused(segmentIndex: 0, remaining: minutes(5)))
        clock.set(t(9, 8)); try engine.resume()
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 13)))
        #expect(recorded(engine.snapshot.actuals(at: t(9, 9))[0])[0] == rested(t(9, 0), t(9, 5)))
        let kinds = engine.snapshot.actuals(at: t(9, 9))[0].intervals.map(\.kind)
        #expect(kinds == [.rest, pauseKind, .rest])
    }

    @Test func changingSettingsDuringAPauseDoesNotRewriteIt() throws {
        var (engine, clock) = try makeEngine(settings: SessionSettings(pausesCountAsRest: true))
        try engine.start()
        clock.set(t(9, 20)); try engine.pause()
        engine.updateSettings(SessionSettings(pausesCountAsRest: false))
        clock.set(t(9, 25)); try engine.resume()
        clock.set(t(9, 30)); try engine.pause()
        clock.set(t(9, 32)); try engine.resume()
        let intervals = recorded(engine.snapshot.actuals[0])
        #expect(intervals == [
            workedFor(t(9, 0), t(9, 20)), rested(t(9, 20), t(9, 25)),
            workedFor(t(9, 25), t(9, 30)), untracked(t(9, 30), t(9, 32)),
        ])
    }

    @Test func pauseAndResumeAtTheSameInstantRecordNoZeroLengthInterval() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 10))
        try engine.pause()
        try engine.resume()
        clock.set(t(9, 20))
        let first = engine.snapshot.actuals(at: t(9, 20))[0]
        #expect(recorded(first) == [workedFor(t(9, 0), t(9, 10)), workedFor(t(9, 10), t(9, 20))])
        #expect(first.intervals.allSatisfy { $0.duration > 0 })
    }
}
