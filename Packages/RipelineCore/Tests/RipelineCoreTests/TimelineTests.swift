import Foundation
import Testing
@testable import RipelineCore

struct TimelineTests {
    private func block<K: Sendable & Equatable>(_ kind: K, _ start: Date, _ end: Date) -> TimelineBlock<K> {
        TimelineBlock(kind: kind, start: start, end: end)
    }

    @Test func plannedBlocksMirrorThePlan() throws {
        let (engine, _) = try makeEngine()
        #expect(engine.timeline().planned == [
            block(SegmentKind.work, t(9, 0), t(9, 50)),
            block(.shortBreak, t(9, 50), t(10, 0)),
            block(.work, t(10, 0), t(10, 50)),
        ])
        #expect(engine.timeline().actual.isEmpty)
    }

    @Test func adjacentIntervalsOfTheSameKindMergeAcrossSegments() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 45)); try engine.pause()      // rest from 09:45
        clock.set(t(9, 50)); try engine.skip()       // break starts, rest until 10:00
        clock.set(t(10, 0))
        #expect(engine.timeline().actual == [
            block(ActualKind.work, t(9, 0), t(9, 45)),
            block(.rest, t(9, 45), t(10, 0)),
        ])
    }

    @Test func intervalsSplitByAPauseOfTheSameInstantMerge() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 10)); try engine.pause()
        try engine.resume()
        clock.set(t(9, 20))
        #expect(engine.timeline().actual == [block(ActualKind.work, t(9, 0), t(9, 20))])
    }

    @Test func untrackedPausesStayVisibleBetweenWork() throws {
        var (engine, clock) = try makeEngine(settings: SessionSettings(pausesCountAsRest: false))
        try engine.start()
        clock.set(t(9, 20)); try engine.pause()
        clock.set(t(9, 30)); try engine.resume()
        clock.set(t(9, 40))
        #expect(engine.timeline().actual == [
            block(ActualKind.work, t(9, 0), t(9, 20)),
            block(.untracked, t(9, 20), t(9, 30)),
            block(.work, t(9, 30), t(9, 40)),
        ])
    }

    @Test func gapsBeforeTheFirstStartAreNotFilled() throws {
        var (engine, clock) = try makeEngine(at: t(9, 15))
        try engine.start()
        clock.set(t(9, 30))
        #expect(engine.timeline().actual == [block(ActualKind.work, t(9, 15), t(9, 30))])
    }

    @Test func openIntervalRunsUpToNowIncludingOvertime() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 55))
        #expect(engine.timeline().actual == [block(ActualKind.work, t(9, 0), t(9, 55))])
    }

    @Test func boundsCoverBothRows() throws {
        var (engine, clock) = try makeEngine(plan: makePlan([(.work, 50)]), at: t(9, 15))
        try engine.start()
        clock.set(t(9, 30))
        #expect(engine.timeline().bounds == DateInterval(start: t(9, 0), end: t(9, 50)))
        clock.set(t(10, 20))
        #expect(engine.timeline().bounds == DateInterval(start: t(9, 0), end: t(10, 20)))
    }

    @Test func emptySnapshotHasNoBounds() {
        let timeline = SessionEngine(clock: ManualClock(t(9))).timeline()
        #expect(timeline.planned.isEmpty)
        #expect(timeline.actual.isEmpty)
        #expect(timeline.bounds == nil)
    }
}
