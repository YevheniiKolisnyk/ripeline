import Foundation
import Testing
@testable import RipelineCore

struct PlanGeneratorTests {
    private func untilTime(
        _ start: Date, _ end: Date, _ remainder: DayPlanRequest.RemainderStrategy
    ) -> DayPlanRequest {
        DayPlanRequest(
            mode: .untilTime(start: start, end: end), longBreak: .none,
            remainderStrategy: remainder, preset: presetP
        )
    }

    private func netFocus(
        _ start: Date, _ focus: Int, _ remainder: DayPlanRequest.RemainderStrategy = .leaveFree
    ) -> DayPlanRequest {
        DayPlanRequest(
            mode: .netFocus(start: start, focusMinutes: focus), longBreak: .none,
            remainderStrategy: remainder, preset: presetP
        )
    }

    /// `count` work blocks of 50 minutes with 10-minute short breaks, from 09:00.
    private func standardCycle(count: Int) -> [Block] {
        var result: [Block] = []
        for i in 0..<count {
            result.append(work(t(9 + i, 0), t(9 + i, 50)))
            if i < count - 1 { result.append(shortBreak(t(9 + i, 50), t(10 + i, 0))) }
        }
        return result
    }

    // MARK: .untilTime

    @Test func leaveFreeFitsFullCyclesAndEndsOnWork() throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(17), .leaveFree))
        #expect(blocks(plan) == standardCycle(count: 8))
        #expect(plan.last?.end == t(16, 50))
    }

    @Test func shortBlockFillsRemainderWhenLongEnough() throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(17, 20), .shortBlock(minMinutes: 15)))
        #expect(blocks(plan) == standardCycle(count: 8) + [
            shortBreak(t(16, 50), t(17, 0)),
            work(t(17, 0), t(17, 20)),
        ])
    }

    @Test func shortBlockLeavesRemainderFreeBelowMinimum() throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(17, 10), .shortBlock(minMinutes: 15)))
        #expect(blocks(plan) == standardCycle(count: 8))
    }

    @Test func shortBlockAcceptsRemainderExactlyAtMinimum() throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(17, 15), .shortBlock(minMinutes: 15)))
        #expect(blocks(plan).last == work(t(17, 0), t(17, 15)))
    }

    @Test func stretchSpreadsExtraTimeEvenly() throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(17, 30), .stretchBlocks))
        let works = plan.filter { $0.kind == .work }
        #expect(works.count == 8)
        #expect(works.allSatisfy { $0.duration == minutes(55) })
        #expect(plan.last?.end == t(17, 30))
    }

    @Test func stretchGivesEarliestBlocksTheLeftoverMinutes() throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(16, 42), .stretchBlocks))
        let works = plan.filter { $0.kind == .work }.map { $0.duration / 60 }
        #expect(works == [58, 58, 58, 57, 57, 57, 57])
        #expect(plan.last?.end == t(16, 42))
    }

    @Test func stretchPutsSubMinuteResidueOnLastBlock() throws {
        // Start is not minute-aligned: 144.5 min window, 2 blocks + 1 break.
        let plan = try PlanGenerator.generate(untilTime(t(9, 0, 30), t(11, 25, 0), .stretchBlocks))
        #expect(blocks(plan) == [
            work(t(9, 0, 30), t(10, 7, 30)),
            shortBreak(t(10, 7, 30), t(10, 17, 30)),
            work(t(10, 17, 30), t(11, 25, 0)),
        ])
    }

    @Test(arguments: PlanGeneratorTests.shortDayCases)
    func dayShorterThanOneBlock(strategy: DayPlanRequest.RemainderStrategy, expected: [Block]) throws {
        let plan = try PlanGenerator.generate(untilTime(t(9), t(9, 30), strategy))
        #expect(blocks(plan) == expected)
    }

    static let shortDayCases: [(DayPlanRequest.RemainderStrategy, [Block])] = [
        (.shortBlock(minMinutes: 15), [work(t(9), t(9, 30))]),
        (.shortBlock(minMinutes: 45), []),
        (.leaveFree, []),
        (.stretchBlocks, []),
    ]

    // MARK: .netFocus

    @Test func netFocusShortensLastBlock() throws {
        let plan = try PlanGenerator.generate(netFocus(t(9), 120))
        #expect(blocks(plan) == [
            work(t(9, 0), t(9, 50)),
            shortBreak(t(9, 50), t(10, 0)),
            work(t(10, 0), t(10, 50)),
            shortBreak(t(10, 50), t(11, 0)),
            work(t(11, 0), t(11, 20)),
        ])
        #expect(focusMinutes(plan) == 120)
    }

    @Test func netFocusWithExactMultipleHasNoShortBlock() throws {
        let plan = try PlanGenerator.generate(netFocus(t(9), 150))
        #expect(plan.filter { $0.kind == .work }.count == 3)
        #expect(plan.last?.end == t(11, 50))
        #expect(focusMinutes(plan) == 150)
    }

    @Test(arguments: [
        DayPlanRequest.RemainderStrategy.shortBlock(minMinutes: 15), .leaveFree, .stretchBlocks,
    ])
    func netFocusIgnoresRemainderStrategy(strategy: DayPlanRequest.RemainderStrategy) throws {
        let reference = try PlanGenerator.generate(netFocus(t(9), 120, .leaveFree))
        let plan = try PlanGenerator.generate(netFocus(t(9), 120, strategy))
        #expect(blocks(plan) == blocks(reference))
    }

    // MARK: invariants

    @Test(arguments: PlanGeneratorTests.sampleRequests)
    func plansAreWellFormed(request: DayPlanRequest) throws {
        expectWellFormed(try PlanGenerator.generate(request))
    }

    static let sampleRequests: [DayPlanRequest] = {
        func req(_ mode: DayPlanRequest.Mode, _ remainder: DayPlanRequest.RemainderStrategy) -> DayPlanRequest {
            DayPlanRequest(mode: mode, longBreak: .none, remainderStrategy: remainder, preset: presetP)
        }
        return [
            req(.untilTime(start: t(9), end: t(17)), .leaveFree),
            req(.untilTime(start: t(9), end: t(17, 20)), .shortBlock(minMinutes: 15)),
            req(.untilTime(start: t(9), end: t(16, 42)), .stretchBlocks),
            req(.untilTime(start: t(9, 0, 30), end: t(11, 25)), .stretchBlocks),
            req(.untilTime(start: t(9), end: t(9, 30)), .shortBlock(minMinutes: 15)),
            req(.netFocus(start: t(9), focusMinutes: 120), .leaveFree),
            req(.netFocus(start: t(9), focusMinutes: 150), .leaveFree),
        ]
    }()

    // MARK: validation

    @Test func rejectsNonPositivePresetValues() {
        for preset in [
            Preset(workMinutes: 0, shortBreakMinutes: 10, longBreakMinutes: 45),
            Preset(workMinutes: 50, shortBreakMinutes: -1, longBreakMinutes: 45),
            Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 0),
        ] {
            let request = DayPlanRequest(
                mode: .untilTime(start: t(9), end: t(17)), longBreak: .none,
                remainderStrategy: .leaveFree, preset: preset
            )
            #expect(throws: PlanError.invalidPreset) { try PlanGenerator.generate(request) }
        }
    }

    @Test func rejectsEmptyOrReversedTimeRange() {
        #expect(throws: PlanError.invalidTimeRange) {
            try PlanGenerator.generate(untilTime(t(9), t(9), .leaveFree))
        }
        #expect(throws: PlanError.invalidTimeRange) {
            try PlanGenerator.generate(untilTime(t(17), t(9), .leaveFree))
        }
    }

    @Test func rejectsNonPositiveFocus() {
        #expect(throws: PlanError.invalidFocusMinutes) {
            try PlanGenerator.generate(netFocus(t(9), 0))
        }
    }

    @Test func rejectsNonPositiveMinimumBlock() {
        #expect(throws: PlanError.invalidMinimumBlock) {
            try PlanGenerator.generate(untilTime(t(9), t(17), .shortBlock(minMinutes: 0)))
        }
    }
}
