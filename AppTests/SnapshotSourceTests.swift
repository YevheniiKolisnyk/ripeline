import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SnapshotSourceTests {
    private func overview(_ snapshot: SessionSnapshot) -> DayOverviewModel {
        DayOverviewModel(source: SnapshotSource(snapshot: snapshot), calendar: utc)
    }

    // MARK: last recorded instant

    @Test func nothingRecordedHasNoLastInstant() throws {
        #expect(SnapshotSource.lastRecordedInstant(of: try idleSnapshot()) == nil)
        let notStarted = try playedDay { engine, _ in try engine.endDay() }
        #expect(SnapshotSource.lastRecordedInstant(of: notStarted) == nil)
    }

    @Test func aJustStartedDayIsRecordedFromItsStart() throws {
        #expect(SnapshotSource.lastRecordedInstant(of: try startedSnapshot()) == t(9))
    }

    @Test func aPausedAndResumedDayIsRecordedUpToTheLatestEvent() throws {
        #expect(SnapshotSource.lastRecordedInstant(of: try abandonedDay()) == t(9, 35))
    }

    @Test func aFinishedDayEndsWhereItEnded() throws {
        #expect(SnapshotSource.lastRecordedInstant(of: try finishedDay()) == t(9, 30))
    }

    // MARK: the same picture as the live model

    /// The scenario of the 2a review as a finished day.
    private func scripted(_ engine: inout SessionEngine, _ clock: TestClock) throws {
        try engine.start()
        clock.set(t(9, 30)); try engine.pause()
        clock.set(t(9, 35)); try engine.resume()
        clock.set(t(9, 57)); try engine.advance()
        clock.set(t(10, 9)); try engine.advance()
        clock.set(t(10, 40)); try engine.skip()
    }

    @Test func aStoredDayLooksLikeTheLiveOne() throws {
        let plan = makePlan([(.work, 50), (.shortBreak, 10), (.work, 50)])
        let settings = SessionSettings(pausesCountAsRest: false)
        let snapshot = try playedDay(plan: plan, settings: settings, scripted)

        let live = try EngineSource(plan: makePlan([(.work, 50), (.shortBreak, 10), (.work, 50)]), settings: settings)
        try live.at(t(9)) { try $0.start() }
        try live.at(t(9, 30)) { try $0.pause() }
        try live.at(t(9, 35)) { try $0.resume() }
        try live.at(t(9, 57)) { try $0.advance() }
        try live.at(t(10, 9)) { try $0.advance() }
        try live.at(t(10, 40)) { try $0.skip() }
        let liveModel = DayOverviewModel(source: live, calendar: utc)

        let stored = overview(snapshot)
        #expect(stored.mode == .finished)
        #expect(stored.planned == liveModel.planned)
        #expect(stored.actual == liveModel.actual)
        #expect(stored.segments == liveModel.segments)
        #expect(stored.summary == liveModel.summary)
        #expect(stored.summary?.endKind == .final)
        #expect(stored.summary?.endsAt == t(10, 40))
        #expect(stored.nowX == nil && stored.lag == nil)
    }

    // MARK: a day that was never ended (Review Focus 3)

    @Test func anAbandonedDayStopsAtItsLastRecordAndDoesNotGrow() throws {
        let snapshot = try abandonedDay()
        let model = overview(snapshot)
        #expect(model.mode == .finished)
        #expect(model.nowX == nil && model.lag == nil)
        #expect(model.actual.map(\.kind) == [.work, .rest])
        #expect(model.actual.last?.end == t(9, 35))
        #expect(model.summary?.endKind == .lastRecord)
        #expect(model.summary?.endsAt == t(9, 35))

        // Time passes; the stored picture does not.
        let before = (model.actual, model.summary, model.axis)
        model.refresh(); model.refresh()
        #expect(before.0 == model.actual && before.1 == model.summary && before.2 == model.axis)
    }

    @Test func aDayEndedBeforeAnythingWasRecordedHasNoEnd() throws {
        let snapshot = try playedDay { engine, _ in try engine.endDay() }
        let model = overview(snapshot)
        #expect(model.mode == .finished)
        #expect(model.actual.isEmpty)
        #expect(model.summary?.endKind == .final)
        #expect(model.summary?.endsAt == nil)
        #expect(model.axis != nil)
    }

    /// Review finding: a stored day that was never ended has a tomato for the block that was running; it can be picked.
    @Test func theTomatoOfABlockThatWasStillRunningCanBePicked() throws {
        let source = SnapshotSource(snapshot: try abandonedDay())
        let tomato = try #require(source.overviewTomatoes.first)
        #expect(tomato.availability == .pickable)
        #expect(tomato.workTime > 0)
    }
}
