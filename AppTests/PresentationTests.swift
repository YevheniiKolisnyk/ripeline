import Testing
@testable import Ripeline

struct PresentationTests {
    static let phases: [Phase] = [
        .idle, .working, .onBreak, .paused(onBreak: false), .paused(onBreak: true),
        .overtime(onBreak: false), .overtime(onBreak: true), .finished,
    ]

    @Test(arguments: [
        (Phase.idle, "timer"), (.working, "timer"), (.onBreak, "cup.and.saucer.fill"),
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
        #expect(model == MenuBarLabelModel(symbolName: "timer", text: "32:10"))
    }

    @Test func breakShowsCountdownWithBreakSymbol() {
        let model = MenuBarLabelModel(phase: .onBreak, remaining: 90, overtimeElapsed: nil, showTime: true)
        #expect(model.symbolName == "cup.and.saucer.fill")
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
        #expect(!model.symbolName.isEmpty)
    }
}
