import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct QuickSessionTests {
    // MARK: lengths

    @Test(arguments: [(QuickBlockLength.short, 25, 5), (.medium, 50, 10), (.long, 90, 15)])
    func lengthsAndTheirBreaks(length: QuickBlockLength, minutes: Int, breakMinutes: Int) {
        #expect(length.minutes == minutes)
        #expect(length.breakMinutes == breakMinutes)
    }

    @Test func theThreeLengthsAreOffered() {
        #expect(QuickBlockLength.allCases.map(\.minutes) == [25, 50, 90])
    }

    // MARK: the first block

    @Test(arguments: QuickBlockLength.allCases)
    func theFirstBlockIsOneWorkSegmentFromNow(length: QuickBlockLength) {
        let plan = QuickSession.plan(length: length, start: t(9, 7, 30))
        #expect(plan.count == 1)
        #expect(plan[0].kind == .work && plan[0].index == 0)
        #expect(plan[0].start == t(9, 7, 30))
        #expect(plan[0].duration == minutes(length.minutes))
    }

    // MARK: the next blocks

    @Test(arguments: [(QuickBlockLength.short, 5), (.medium, 10), (.long, 15)])
    func aBreakAndABlockOfTheSameLengthFollow(length: QuickBlockLength, breakMinutes: Int) {
        let plan = QuickSession.plan(length: length, start: t(9))
        let next = QuickSession.nextBlocks(after: plan)
        #expect(next.map(\.kind) == [.shortBreak, .work])
        #expect(next.map(\.index) == [1, 2])
        #expect(next[0].start == plan[0].end)
        #expect(next[0].duration == minutes(breakMinutes))
        #expect(next[1].start == next[0].end)
        #expect(next[1].duration == minutes(length.minutes))
    }

    @Test func indicesContinueAfterALongerPlan() {
        var plan = QuickSession.plan(length: .short, start: t(9))
        plan += QuickSession.nextBlocks(after: plan)
        let next = QuickSession.nextBlocks(after: plan)
        #expect(next.map(\.index) == [3, 4])
        #expect(next[0].start == plan.last?.end)
    }

    /// The new blocks follow the plan, not the clock: the plan's end may be long past.
    @Test func theyStartWhereThePlanEnds() {
        let plan = QuickSession.plan(length: .medium, start: t(9))
        #expect(QuickSession.nextBlocks(after: plan)[0].start == t(9, 50))
    }

    @Test func anUnexpectedFirstLengthGetsAFiveMinuteBreak() {
        let plan = makePlan([(.work, 30)])
        let next = QuickSession.nextBlocks(after: plan)
        #expect(next[0].duration == minutes(5))
        #expect(next[1].duration == minutes(30))
    }

    @Test func nothingFollowsAnEmptyPlan() {
        #expect(QuickSession.nextBlocks(after: []).isEmpty)
    }

    @Test func eachCallMakesNewIds() {
        let plan = QuickSession.plan(length: .short, start: t(9))
        let a = QuickSession.nextBlocks(after: plan), b = QuickSession.nextBlocks(after: plan)
        #expect(Set((a + b).map(\.id)).count == 4)
    }

    @Test func theEngineAcceptsWhatItMakes() throws {
        var engine = SessionEngine(clock: TestClock(t(9)))
        try engine.startDay(plan: QuickSession.plan(length: .short, start: t(9)), settings: SessionSettings(), kind: .quick)
        try engine.start()
        for _ in 0..<5 { try engine.appendSegments(QuickSession.nextBlocks(after: engine.snapshot.plan)) }
        #expect(engine.snapshot.plan.count == 11)
    }
}
