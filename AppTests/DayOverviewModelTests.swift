import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct DayOverviewModelTests {
    private func model(_ source: EngineSource) -> DayOverviewModel {
        DayOverviewModel(source: source, calendar: utc)
    }

    /// The day the core specification describes, as the setup screen makes it.
    private func stageOneDayPlan() throws -> [PlannedSegment] {
        var form = DayPlanForm.standard
        form.longBreak = .atTime(TimeOfDay(hour: 13, minute: 0))
        guard case let .ready(_, preview, _) = DaySetup.evaluate(form: form, now: t(9), calendar: utc) else {
            Issue.record("the stage 1 day did not evaluate"); throw CancellationError()
        }
        return preview.segments
    }

    private func expectWellFormed(_ m: DayOverviewModel) {
        for block in m.planned.map({ ($0.x, $0.width) }) + m.actual.map({ ($0.x, $0.width) }) {
            #expect(block.0 >= 0 && block.0 <= 1)
            #expect(block.1 >= 0 && block.0 + block.1 <= 1 + 1e-9)
        }
        if let nowX = m.nowX { #expect(nowX >= 0 && nowX <= 1) }
    }

    // MARK: modes

    @Test func noDayShowsNothing() throws {
        let m = model(try EngineSource())
        #expect(m.mode == .noDay)
        #expect(m.axis == nil && m.nowX == nil && m.lag == nil && m.summary == nil)
        #expect(m.planned.isEmpty && m.actual.isEmpty && m.segments.isEmpty)
    }

    @Test func anIdleEngineWithAPlanLoadedIsStillNoDay() throws {
        #expect(model(try EngineSource(plan: fivePlan())).mode == .noDay)
    }

    @Test func modesFollowTheDay() throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        try source.at(t(9)) { try $0.start() }
        m.refresh()
        #expect(m.mode == .running)
        try source.at(t(9, 30)) { try $0.endDay() }
        m.refresh()
        #expect(m.mode == .finished)
        try source.at(t(10)) { try $0.startDay(plan: fivePlan(start: t(10)), settings: SessionSettings()); try $0.start() }
        m.refresh()
        #expect(m.mode == .running)
        #expect(m.planned.first?.start == t(10))
    }

    // MARK: layout

    @Test func theStageOneDayIsLaidOutOnTheAxis() throws {
        let source = try EngineSource(plan: stageOneDayPlan())
        let m = model(source)
        #expect(m.mode == .noDay)
        try source.at(t(9)) { try $0.start() }
        m.refresh()
        #expect(m.planned.count == 15)
        #expect(m.axis?.start == t(9) && m.axis?.end == t(17))
        let longBreak = try #require(m.planned.first { $0.kind == .longBreak })
        #expect(abs(longBreak.x - 230.0 / 480.0) < 1e-9)
        #expect(abs(longBreak.width - 45.0 / 480.0) < 1e-9)
        expectWellFormed(m)
    }

    @Test func theNowMarkerIsOnlyShownWhileRunning() throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        #expect(m.nowX == nil)
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 20))
        m.refresh()
        #expect(m.nowX == m.axis?.x(for: t(9, 20)))
        try source.at(t(9, 30)) { try $0.endDay() }
        m.refresh()
        #expect(m.nowX == nil)
    }

    @Test func aSegmentThatRanLongShowsAsALongerActualBlock() throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 52)) { try $0.advance() }       // the work segment took 52 minutes
        m.refresh()
        #expect(m.axis?.step == 1800)
        #expect(abs(m.planned[0].width - 50.0 / 180.0) < 1e-9)
        #expect(abs(m.actual[0].width - 52.0 / 180.0) < 1e-9)
        #expect(m.actual[0].width > m.planned[0].width)
        expectWellFormed(m)
    }

    @Test func startingBeforeThePlanExtendsTheAxisAndTheActualRowStartsFirst() throws {
        let source = try EngineSource(plan: fivePlan(), at: t(8, 40))
        let m = model(source)
        try source.at(t(8, 40)) { try $0.start() }
        try source.at(t(8, 50))
        m.refresh()
        #expect(m.axis?.start == t(8, 30))
        #expect(m.actual[0].x > 0)
        #expect(m.actual[0].x < m.planned[0].x)
        expectWellFormed(m)
    }

    @Test func aSkippedSegmentLeavesItsRecordedTimeAndTheNextOneBegins() throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 20)) { try $0.skip() }
        try source.at(t(9, 25))
        m.refresh()
        #expect(m.actual.map(\.kind) == [.work, .rest])
        #expect(m.actual[0].end == t(9, 20))
        #expect(m.segments[0].status == .skipped)
        #expect(m.segments[1].status == .active)
    }

    @Test func anUntrackedPauseIsItsOwnBlock() throws {
        let source = try EngineSource(plan: fivePlan(), settings: SessionSettings(pausesCountAsRest: false))
        let m = model(source)
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 30)) { try $0.pause() }
        try source.at(t(9, 35)) { try $0.resume() }
        try source.at(t(9, 40))
        m.refresh()
        #expect(m.actual.map(\.kind) == [.work, .untracked, .work])
    }

    // MARK: lag

    @Test(arguments: [(59.0, LagState.onSchedule), (60.0, .behind(60)), (-59.0, .onSchedule), (-60.0, .ahead(60)), (0.0, .onSchedule), (300.0, .behind(300))])
    func lagThresholds(lag: Double, expected: LagState) throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        try source.at(t(9)) { try $0.start() }
        source.statusOverride = .some(ScheduleStatus(plannedEnd: t(11, 50), projectedEnd: t(11, 50).addingTimeInterval(lag)))
        m.refresh()
        #expect(m.lag == expected)
    }

    // MARK: summary and table

    /// The scenario of the 2a review: untracked pauses, overtime in a work and a break, a skipped segment.
    private func scriptedDay() throws -> EngineSource {
        let plan = makePlan([(.work, 50), (.shortBreak, 10), (.work, 50)])
        let source = try EngineSource(plan: plan, settings: SessionSettings(pausesCountAsRest: false))
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 30)) { try $0.pause() }
        try source.at(t(9, 35)) { try $0.resume() }
        try source.at(t(9, 57)) { try $0.advance() }
        try source.at(t(10, 9)) { try $0.advance() }
        try source.at(t(10, 40)) { try $0.skip() }
        return source
    }

    @Test func theSummaryOfAFinishedDay() throws {
        let m = model(try scriptedDay())
        let summary = try #require(m.summary)
        #expect(m.mode == .finished)
        #expect(summary.focusPlanned == minutes(100) && summary.focusActual == minutes(83))
        #expect(summary.restPlanned == minutes(10) && summary.restActual == minutes(12))
        #expect(summary.untracked == minutes(5))
        #expect(summary.plannedEnd == t(10, 50))
        #expect(summary.endsAt == t(10, 40))
        #expect(summary.endIsFinal)
    }

    @Test func theTableOfAFinishedDay() throws {
        let m = model(try scriptedDay())
        #expect(m.segments.map(\.delta) == [minutes(7), minutes(2), minutes(-19)])
        #expect(m.segments.map(\.status) == [.completed, .completed, .skipped])
        #expect(m.segments.map(\.kind) == [.work, .shortBreak, .work])
        #expect(m.segments[0].start == t(9))
        #expect(m.segments[0].untracked == minutes(5))
    }

    @Test func aRunningDayEndsAtTheProjectedTime() throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        try source.at(t(9, 15)) { try $0.start() }
        try source.at(t(9, 30))
        m.refresh()
        let summary = try #require(m.summary)
        #expect(!summary.endIsFinal)
        #expect(summary.endsAt == source.engine.scheduleStatus()?.projectedEnd)
    }

    // MARK: finished days (review)

    /// A day cut short is not "ahead of schedule": the chip is for a day that is still going.
    @Test func aFinishedDayHasNoLagChip() throws {
        let finished = model(try scriptedDay())
        #expect(finished.mode == .finished)
        #expect(finished.lag == nil)

        let source = try EngineSource(plan: fivePlan())
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 30)) { try $0.endDay() }          // ended two hours before the plan
        #expect(model(source).lag == nil)
    }

    @Test func aRunningDayStillHasIt() throws {
        let source = try EngineSource(plan: fivePlan(), at: t(9, 15))
        try source.at(t(9, 15)) { try $0.start() }
        try source.at(t(9, 30))
        #expect(model(source).lag == .behind(minutes(15)))
    }

    // MARK: odd data (Review Focus 4)

    @Test func aDayEndedBeforeAnythingWasRecorded() throws {
        let source = try EngineSource(plan: fivePlan())
        try source.at(t(9)) { try $0.endDay() }
        let m = model(source)
        #expect(m.mode == .finished)
        #expect(m.actual.isEmpty)
        #expect(m.summary?.endsAt == nil)
        #expect(m.axis != nil)
        #expect(m.segments.map(\.status) == Array(repeating: .notStarted, count: 5))
        expectWellFormed(m)
    }

    // MARK: refreshing

    @Test func refreshingFollowsTheClockAndIsIdempotent() throws {
        let source = try EngineSource(plan: fivePlan())
        let m = model(source)
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 10))
        m.refresh()
        let first = m.nowX
        try source.at(t(9, 40))
        m.refresh()
        let second = m.nowX
        #expect(try #require(second) > #require(first))
        let before = (m.mode, m.axis, m.planned, m.actual, m.nowX)
        let beforeRest = (m.lag, m.summary, m.segments)
        m.refresh(); m.refresh()
        #expect(before == (m.mode, m.axis, m.planned, m.actual, m.nowX))
        #expect(beforeRest == (m.lag, m.summary, m.segments))
    }
}
