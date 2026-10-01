import Foundation
import Testing
@testable import RipelineCore

struct AppendSegmentsTests {
    /// A quick session of one 25-minute block from 09:00, with the given settings; not started.
    private func session(
        kind: SessionKind = .quick, plan: [PlannedSegment]? = nil, settings: SessionSettings = SessionSettings()
    ) throws -> (engine: SessionEngine, clock: ManualClock) {
        let clock = ManualClock(t(9))
        var engine = SessionEngine(clock: clock)
        try engine.startDay(plan: plan ?? makePlan([(.work, 25)]), settings: settings, kind: kind)
        return (engine, clock)
    }

    /// Segments that follow the engine's plan exactly: indices continue, the first starts where the plan ends.
    private func following(_ engine: SessionEngine, _ items: [(SegmentKind, Int)]) -> [PlannedSegment] {
        let plan = engine.snapshot.plan
        var cursor = plan.last!.end
        return items.enumerated().map { offset, item in
            let end = cursor.addingTimeInterval(minutes(item.1))
            defer { cursor = end }
            return PlannedSegment(index: plan.count + offset, kind: item.0, start: cursor, end: end)
        }
    }

    private func nextBlock(_ engine: SessionEngine) -> [PlannedSegment] { following(engine, [(.shortBreak, 5), (.work, 25)]) }

    private func json(_ snapshot: SessionSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    // MARK: when it is allowed

    @Test func onlyARunningPausedOrOvertimeQuickSessionAcceptsMoreSegments() throws {
        var (quick, clock) = try session()
        #expect(!quick.isAllowed(.append))                              // idle
        try quick.start()
        #expect(quick.isAllowed(.append))                               // running
        clock.set(t(9, 10)); try quick.pause()
        #expect(quick.isAllowed(.append))                               // paused
        clock.set(t(9, 12)); try quick.resume()
        clock.set(t(9, 40)); quick.tick()
        #expect(quick.isAllowed(.append))                               // overtime
        try quick.endDay()
        #expect(!quick.isAllowed(.append))                              // finished
        #expect(throws: SessionError.notAllowed(.append)) { try quick.appendSegments(self.following(quick, [(.work, 25)])) }
    }

    @Test func anOrdinaryDayNeverAcceptsMoreSegments() throws {
        var (day, clock) = try session(kind: .day)
        try day.start()
        #expect(!day.isAllowed(.append))
        #expect(throws: SessionError.notAllowed(.append)) { try day.appendSegments(self.following(day, [(.work, 25)])) }
        clock.set(t(9, 40)); day.tick()
        #expect(!day.isAllowed(.append))                                  // not even in overtime
        #expect(day.snapshot.plan.count == 1)
    }

    // MARK: what appending does

    @Test func aBreakAndABlockAreQueuedBehindTheRunningOne() throws {
        var (quick, _) = try session()
        try quick.start()
        let stateBefore = quick.snapshot.state
        try quick.appendSegments(nextBlock(quick))
        #expect(quick.snapshot.plan.count == 3)
        #expect(quick.snapshot.actuals.count == 3)
        #expect(quick.snapshot.actuals.dropFirst().allSatisfy { $0.status == .notStarted && $0.intervals.isEmpty })
        #expect(quick.snapshot.state == stateBefore)
        #expect(quick.snapshot.plan.map(\.kind) == [.work, .shortBreak, .work])
    }

    @Test func appendingDuringAPauseDoesNotDisturbTheCountdown() throws {
        var (quick, clock) = try session()
        try quick.start()
        clock.set(t(9, 10)); try quick.pause()
        try quick.appendSegments(nextBlock(quick))
        clock.set(t(9, 15)); try quick.resume()
        #expect(quick.state == .running(segmentIndex: 0, endsAt: t(9, 30)))     // 15 minutes were left
    }

    @Test func appendingInOvertimeThenAdvancingStartsTheAddedBreakNow() throws {
        var (quick, clock) = try session()
        try quick.start()
        clock.set(t(9, 28)); quick.tick()
        #expect(quick.state == .overtime(segmentIndex: 0, since: t(9, 25)))
        try quick.appendSegments(nextBlock(quick))
        try quick.advance()
        #expect(quick.state == .running(segmentIndex: 1, endsAt: t(9, 33)))
        #expect(quick.snapshot.openInterval == OpenInterval(kind: .rest, start: t(9, 28)))
    }

    @Test func appendingFromABreakQueuesBothInOrder() throws {
        var (quick, clock) = try session(plan: makePlan([(.work, 25), (.shortBreak, 5)]))
        try quick.start()
        clock.set(t(9, 25)); quick.tick()
        try quick.advance()                                                     // now on the break
        try quick.appendSegments(following(quick, [(.work, 25)]))
        try quick.appendSegments(following(quick, [(.shortBreak, 5), (.work, 25)]))
        #expect(quick.snapshot.plan.map(\.kind) == [.work, .shortBreak, .work, .shortBreak, .work])
        #expect(quick.snapshot.plan.map(\.index) == [0, 1, 2, 3, 4])
    }

    /// Review Focus 2.
    @Test func manyAppendsStayContiguousAndRestorable() throws {
        var (quick, _) = try session()
        try quick.start()
        for _ in 0..<20 { try quick.appendSegments(nextBlock(quick)) }
        #expect(quick.snapshot.plan.count == 41)
        #expect(SessionSnapshot.isWellFormed(quick.snapshot.plan))
        _ = try SessionEngine(restoring: quick.snapshot, clock: ManualClock(t(9, 10)))
    }

    // MARK: refusals leave everything as it was

    @Test func badSegmentsAreRefusedAndChangeNothing() throws {
        var (quick, _) = try session()
        try quick.start()
        let good = nextBlock(quick)
        func moved(_ s: PlannedSegment, start: TimeInterval = 0, end: TimeInterval = 0, index: Int? = nil) -> PlannedSegment {
            PlannedSegment(index: index ?? s.index, kind: s.kind, start: s.start.addingTimeInterval(start), end: s.end.addingTimeInterval(end))
        }
        let cases: [(String, [PlannedSegment], SessionError)] = [
            ("gap", [moved(good[0], start: 60, end: 60)] + Array(good.dropFirst()), .invalidPlan),
            ("overlap", [moved(good[0], start: -60, end: -60)] + Array(good.dropFirst()), .invalidPlan),
            ("wrong index", [moved(good[0], index: 5)] + Array(good.dropFirst()), .invalidPlan),
            ("zero length", [moved(good[0], end: -300)], .invalidPlan),
            ("negative length", [moved(good[0], end: -400)], .invalidPlan),
            ("empty", [], .emptyPlan),
            ("second does not follow the first", [good[0], moved(good[1], start: 120, end: 120)], .invalidPlan),
        ]
        for (label, segments, expected) in cases {
            let before = try json(quick.snapshot)
            #expect(throws: expected, Comment(rawValue: label)) { try quick.appendSegments(segments) }
            #expect(try json(quick.snapshot) == before, Comment(rawValue: label))
        }
    }

    // MARK: awkward moments (Review Focus 2)

    @Test func appendingInTheInstantTheLastBlockEndsWithAutoAdvanceIsRefusedNotLost() throws {
        var (quick, clock) = try session(settings: SessionSettings(autoAdvanceWorkToBreak: true))
        try quick.start()
        clock.set(t(9, 25))                                                     // exactly the end
        #expect(throws: SessionError.notAllowed(.append)) { try quick.appendSegments(self.nextBlock(quick)) }
        #expect(quick.state == .finished)
        #expect(quick.snapshot.actuals[0].status == .completed)
        #expect(quick.snapshot.plan.count == 1)
    }

    @Test func appendingInTheSameInstantWithoutAutoAdvanceWorks() throws {
        var (quick, clock) = try session()
        try quick.start()
        clock.set(t(9, 25))
        try quick.appendSegments(nextBlock(quick))
        #expect(quick.state == .overtime(segmentIndex: 0, since: t(9, 25)))
        #expect(quick.snapshot.plan.count == 3)
    }

    @Test func theAddedSegmentsFollowThePlansEndEvenWhenNowIsFarAhead() throws {
        var (quick, clock) = try session()
        try quick.start()
        clock.set(t(11, 25)); quick.tick()                                       // two hours into overtime
        let added = nextBlock(quick)
        #expect(added[0].start == t(9, 25))                                      // the plan's end, in the past
        try quick.appendSegments(added)
        try quick.advance()
        #expect(quick.state == .running(segmentIndex: 1, endsAt: t(11, 30)))     // runs for its length from now
    }

    // MARK: the read models follow

    @Test func lagAndProjectionCountTheAddedSegments() throws {
        var (quick, clock) = try session()
        try quick.start()
        try quick.appendSegments(nextBlock(quick))
        clock.set(t(9, 10))
        let status = try #require(quick.scheduleStatus())
        #expect(status.plannedEnd == t(9, 55))
        #expect(status.projectedEnd == t(9, 55))
        #expect(status.lag == 0)
        #expect(quick.comparison().rows.count == 3)
    }

    @Test func catchUpWalksThroughAddedSegments() throws {
        var (quick, clock) = try session(settings: SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true))
        try quick.start()
        clock.set(t(9, 20))
        try quick.appendSegments(nextBlock(quick))
        clock.set(t(11))
        quick.tick()
        #expect(quick.state == .finished)
        let actuals = quick.snapshot.actuals
        #expect(actuals.map(\.status) == [.completed, .completed, .completed])
        #expect(actuals[0].intervals.last?.end == t(9, 25))
        #expect(actuals[1].intervals.first?.start == t(9, 25) && actuals[1].intervals.last?.end == t(9, 30))
        #expect(actuals[2].intervals.last?.end == t(9, 55))
    }

    @Test func aGrownSessionPersistsAndKeepsGrowing() throws {
        var (quick, _) = try session()
        try quick.start()
        try quick.appendSegments(nextBlock(quick))
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(quick.snapshot))
        #expect(decoded == quick.snapshot)
        var restored = try SessionEngine(restoring: decoded, clock: ManualClock(t(9, 10)))
        #expect(restored.isAllowed(.append))
        try restored.appendSegments(nextBlock(restored))
        #expect(restored.snapshot.plan.count == 5)
    }
}
