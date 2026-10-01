import Testing
@testable import Ripeline

struct PresentationTests {
    static let phases: [Phase] = [
        .idle, .working, .onBreak, .paused(onBreak: false), .paused(onBreak: true),
        .overtime(onBreak: false), .overtime(onBreak: true), .finished,
    ]

    @Test(arguments: [
        (Phase.idle, "circle.dashed"), (.working, "timer"), (.onBreak, "cup.and.saucer.fill"),
        (.paused(onBreak: false), "pause.circle.fill"), (.paused(onBreak: true), "pause.circle.fill"),
        (.overtime(onBreak: false), "exclamationmark.circle.fill"),
        (.overtime(onBreak: true), "exclamationmark.circle.fill"),
        (.finished, "checkmark.circle.fill"),
    ])
    func symbolNames(phase: Phase, expected: String) {
        #expect(phase.symbolName == expected)
    }

    @Test(arguments: [
        (Phase.idle, "phase.idle"), (.working, "phase.working"), (.onBreak, "phase.break"),
        (.paused(onBreak: false), "phase.paused"), (.overtime(onBreak: true), "phase.overtime"),
        (.finished, "phase.finished"),
    ])
    func labelKeys(phase: Phase, expected: String) {
        #expect(phase.labelKey.key == expected)
    }

    @Test func workingShowsCountdown() {
        let model = MenuBarLabelModel(phase: .working, remaining: 1930, overtimeElapsed: nil, showTime: true)
        #expect(model == MenuBarLabelModel(icon: .symbol("timer"), text: "32:10"))
    }

    @Test func breakShowsCountdownWithBreakSymbol() {
        let model = MenuBarLabelModel(phase: .onBreak, remaining: 90, overtimeElapsed: nil, showTime: true)
        #expect(model.icon == .symbol("cup.and.saucer.fill"))
        #expect(model.text == "1:30")
    }

    @Test func pausedShowsTheFrozenRemainingTime() {
        let model = MenuBarLabelModel(phase: .paused(onBreak: false), remaining: 600, overtimeElapsed: nil, showTime: true)
        #expect(model.text == "10:00")
    }

    @Test func overtimeShowsElapsedWithPlus() {
        let model = MenuBarLabelModel(phase: .overtime(onBreak: false), remaining: 0, overtimeElapsed: 135, showTime: true)
        #expect(model.text == "+2:15")
    }

    @Test(arguments: [Phase.idle, .finished])
    func idleAndFinishedShowNoTime(phase: Phase) {
        let model = MenuBarLabelModel(phase: phase, remaining: nil, overtimeElapsed: nil, showTime: true)
        #expect(model.text == nil)
    }

    @Test(arguments: PresentationTests.phases)
    func hidingTheTimeLeavesOnlyTheIcon(phase: Phase) {
        let model = MenuBarLabelModel(phase: phase, remaining: 600, overtimeElapsed: 60, showTime: false)
        #expect(model.text == nil)
    }

    /// With the time hidden, the icon alone must tell a day that is not running from one that is.
    @Test func idleAndWorkingLookDifferent() {
        #expect(Phase.idle.symbolName != Phase.working.symbolName)
    }

    @Test func eachKindOfPhaseHasItsOwnSymbol() {
        let symbols = [Phase.idle, .working, .onBreak, .paused(onBreak: false), .overtime(onBreak: false), .finished].map(\.symbolName)
        #expect(Set(symbols).count == symbols.count)
    }

    // MARK: the growing tomato

    @Test(arguments: [Phase.working, .overtime(onBreak: false)])
    func aWorkBlockShowsItsTomato(phase: Phase) {
        let model = MenuBarLabelModel(phase: phase, remaining: 600, overtimeElapsed: 60, showTime: true, tomatoGrowth: 0.4)
        #expect(model.icon == .tomato(growth: 0.4, frozen: false))
        #expect(model.text != nil)
    }

    @Test func aPausedWorkBlockShowsItsTomatoFrozen() {
        let model = MenuBarLabelModel(phase: .paused(onBreak: false), remaining: 600, overtimeElapsed: nil, showTime: true, tomatoGrowth: 0.7)
        #expect(model.icon == .tomato(growth: 0.7, frozen: true))
        #expect(model.text == "10:00")
    }

    @Test(arguments: [Phase.onBreak, .paused(onBreak: true), .overtime(onBreak: true), .idle, .finished])
    func otherStatesKeepTheirSymbolEvenIfATomatoIsGiven(phase: Phase) {
        let model = MenuBarLabelModel(phase: phase, remaining: 600, overtimeElapsed: 60, showTime: true, tomatoGrowth: 0.4)
        #expect(model.icon == .symbol(phase.symbolName))
    }

    @Test func aWorkBlockWithoutATomatoFallsBackToTheSymbol() {
        let model = MenuBarLabelModel(phase: .working, remaining: 600, overtimeElapsed: nil, showTime: true, tomatoGrowth: nil)
        #expect(model.icon == .symbol("timer"))
    }

    @Test func hidingTheTimeLeavesTheTomato() {
        let model = MenuBarLabelModel(phase: .working, remaining: 600, overtimeElapsed: nil, showTime: false, tomatoGrowth: 1.0)
        #expect(model.icon == .tomato(growth: 1.0, frozen: false))
        #expect(model.text == nil)
    }
}
