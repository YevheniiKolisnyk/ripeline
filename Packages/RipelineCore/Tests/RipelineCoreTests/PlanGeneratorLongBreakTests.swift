import Foundation
import Testing
@testable import RipelineCore

struct PlanGeneratorLongBreakTests {
    private func request(
        _ mode: DayPlanRequest.Mode,
        _ longBreak: DayPlanRequest.LongBreak,
        _ remainder: DayPlanRequest.RemainderStrategy = .shortBlock(minMinutes: 15)
    ) -> DayPlanRequest {
        DayPlanRequest(mode: mode, longBreak: longBreak, remainderStrategy: remainder, preset: presetP)
    }

    private let fullDay = DayPlanRequest.Mode.untilTime(start: t(9), end: t(17))

    private func longBreaks(_ plan: [PlannedSegment]) -> [Block] {
        blocks(plan).filter { $0.kind == .longBreak }
    }

    private func workCount(_ plan: [PlannedSegment]) -> Int {
        plan.filter { $0.kind == .work }.count
    }

    /// The case the specification requires: 09:00–17:00, 50/10/45, long break near 13:00.
    static let requiredBlocks: [Block] = [
        work(t(9, 0), t(9, 50)), shortBreak(t(9, 50), t(10, 0)),
        work(t(10, 0), t(10, 50)), shortBreak(t(10, 50), t(11, 0)),
        work(t(11, 0), t(11, 50)), shortBreak(t(11, 50), t(12, 0)),
        work(t(12, 0), t(12, 50)), longBreak(t(12, 50), t(13, 35)),
        work(t(13, 35), t(14, 25)), shortBreak(t(14, 25), t(14, 35)),
        work(t(14, 35), t(15, 25)), shortBreak(t(15, 25), t(15, 35)),
        work(t(15, 35), t(16, 25)), shortBreak(t(16, 25), t(16, 35)),
        work(t(16, 35), t(17, 0)),
    ]

    @Test func requiredDayWithLongBreakAtOneOClock() throws {
        let plan = try PlanGenerator.generate(request(fullDay, .atTime(t(13))))
        #expect(blocks(plan) == Self.requiredBlocks)
        #expect(longBreaks(plan) == [longBreak(t(12, 50), t(13, 35))])
        #expect(workCount(plan) == 8)
        #expect(focusMinutes(plan) == 375)
        expectWellFormed(plan)
    }

    @Test func longBreakRequestedBeforeFirstJunctionUsesFirstJunction() throws {
        let plan = try PlanGenerator.generate(request(fullDay, .atTime(t(8))))
        #expect(longBreaks(plan) == [longBreak(t(9, 50), t(10, 35))])
        #expect(blocks(plan).last == work(t(16, 35), t(17, 0)))
        #expect(focusMinutes(plan) == 375)
        expectWellFormed(plan)
    }

    @Test func longBreakRequestedAfterLastJunctionUsesLastJunction() throws {
        let plan = try PlanGenerator.generate(request(fullDay, .atTime(t(18))))
        #expect(longBreaks(plan) == [longBreak(t(15, 50), t(16, 35))])
        #expect(blocks(plan).last == work(t(16, 35), t(17, 0)))
        #expect(focusMinutes(plan) == 375)
        expectWellFormed(plan)
    }

    @Test func tieBetweenJunctionsPicksTheEarlierOne() throws {
        // 12:20 is exactly 30 minutes from both 11:50 and 12:50.
        let plan = try PlanGenerator.generate(request(fullDay, .atTime(t(12, 20))))
        #expect(longBreaks(plan) == [longBreak(t(11, 50), t(12, 35))])
        expectWellFormed(plan)
    }

    @Test func longBreakThatPushesOutTheNextBlockIsDropped() throws {
        let mode = DayPlanRequest.Mode.untilTime(start: t(9), end: t(11))
        let plan = try PlanGenerator.generate(request(mode, .atTime(t(10)), .leaveFree))
        #expect(blocks(plan) == [
            work(t(9, 0), t(9, 50)), shortBreak(t(9, 50), t(10, 0)), work(t(10, 0), t(10, 50)),
        ])
    }

    @Test func remainderBelowMinimumIsLeftFreeAfterLongBreak() throws {
        let mode = DayPlanRequest.Mode.untilTime(start: t(9), end: t(16, 45))
        let plan = try PlanGenerator.generate(request(mode, .atTime(t(13))))
        #expect(longBreaks(plan) == [longBreak(t(12, 50), t(13, 35))])
        #expect(workCount(plan) == 7)
        #expect(plan.last?.end == t(16, 25))
        expectWellFormed(plan)
    }

    @Test func stretchedBlocksMoveTheLongBreakLater() throws {
        let plan = try PlanGenerator.generate(request(fullDay, .atTime(t(13)), .stretchBlocks))
        let works = plan.filter { $0.kind == .work }
        #expect(works.count == 7)
        #expect(works.allSatisfy { $0.duration == minutes(55) })
        #expect(longBreaks(plan) == [longBreak(t(13, 10), t(13, 55))])
        #expect(plan.last?.end == t(17))
        expectWellFormed(plan)
    }

    // MARK: afterWorkBlock

    @Test func longBreakAfterSecondWorkBlock() throws {
        let plan = try PlanGenerator.generate(request(fullDay, .afterWorkBlock(2)))
        #expect(longBreaks(plan) == [longBreak(t(10, 50), t(11, 35))])
        expectWellFormed(plan)
    }

    @Test func longBreakAfterNonexistentJunctionIsOmitted() throws {
        let plan = try PlanGenerator.generate(request(fullDay, .afterWorkBlock(8)))
        #expect(longBreaks(plan).isEmpty)
        #expect(workCount(plan) == 8)
        #expect(plan.last?.end == t(16, 50))
    }

    @Test(arguments: [0, -3])
    func rejectsLongBreakAfterBlockBelowOne(block: Int) {
        #expect(throws: PlanError.invalidLongBreakBlock) {
            try PlanGenerator.generate(request(fullDay, .afterWorkBlock(block)))
        }
    }

    // MARK: .netFocus

    @Test func netFocusWithLongBreakAtTimeMatchesTheRequiredDay() throws {
        let plan = try PlanGenerator.generate(
            request(.netFocus(start: t(9), focusMinutes: 375), .atTime(t(13)))
        )
        #expect(blocks(plan) == Self.requiredBlocks)
    }

    @Test func netFocusLongBreakAfterLastBlockIsOmitted() throws {
        let plan = try PlanGenerator.generate(
            request(.netFocus(start: t(9), focusMinutes: 100), .afterWorkBlock(2))
        )
        #expect(blocks(plan) == [
            work(t(9, 0), t(9, 50)), shortBreak(t(9, 50), t(10, 0)), work(t(10, 0), t(10, 50)),
        ])
    }

    @Test func netFocusWithLongBreakKeepsTotalFocus() throws {
        let plan = try PlanGenerator.generate(
            request(.netFocus(start: t(9), focusMinutes: 220), .afterWorkBlock(2))
        )
        #expect(focusMinutes(plan) == 220)
        #expect(longBreaks(plan).count == 1)
        expectWellFormed(plan)
    }

    /// Review finding: with a long break shorter than the short break, adding it makes room for
    /// one more work block, so the junction after the last block of the plain plan can exist.
    @Test func longBreakShorterThanShortBreakCanUseTheLastPlainJunction() throws {
        let preset = Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 5)
        let request = DayPlanRequest(
            mode: .untilTime(start: t(9), end: t(11, 45)), longBreak: .atTime(t(10, 50)),
            remainderStrategy: .leaveFree, preset: preset
        )
        let plan = try PlanGenerator.generate(request)
        #expect(longBreaks(plan) == [longBreak(t(10, 50), t(10, 55))])
        #expect(workCount(plan) == 3)
        expectWellFormed(plan)
    }
}
