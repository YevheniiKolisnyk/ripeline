import RipelineCore
import Testing
@testable import Ripeline

struct PopoverActionsTests {
    private let everything: (SessionAction) -> Bool = { _ in true }

    @Test(arguments: [
        (Phase.idle, [PopoverAction.planDay]),
        (.finished, [.summary]),
        (.working, [.pause, .extend, .skip, .endDay, .overview]),
        (.onBreak, [.pause, .extend, .skip, .endDay, .overview]),
        (.paused(onBreak: false), [.resume, .extend, .skip, .endDay, .overview]),
        (.paused(onBreak: true), [.resume, .extend, .skip, .endDay, .overview]),
        (.overtime(onBreak: false), [.next, .extend, .endDay, .overview]),
        (.overtime(onBreak: true), [.next, .extend, .endDay, .overview]),
    ])
    func buttonsForEachPhase(phase: Phase, expected: [PopoverAction]) {
        #expect(PopoverActions.visible(phase: phase, isAllowed: everything) == expected)
    }

    @Test func onlyAllowedActionsAreShown() {
        let onlyPause: (SessionAction) -> Bool = { $0 == .pause }
        #expect(PopoverActions.visible(phase: .working, isAllowed: onlyPause) == [.pause, .overview])
    }

    @Test func nothingIsShownWhenStartingIsNotAllowed() {
        #expect(PopoverActions.visible(phase: .idle, isAllowed: { _ in false }).isEmpty)
    }

    @Test func nextIsTiedToAdvance() {
        let onlyAdvance: (SessionAction) -> Bool = { $0 == .advance }
        #expect(PopoverActions.visible(phase: .overtime(onBreak: false), isAllowed: onlyAdvance) == [.next, .overview])
    }

    @Test func skipIsHiddenInOvertimeEvenIfAllowed() {
        let actions = PopoverActions.visible(phase: .overtime(onBreak: false), isAllowed: everything)
        #expect(!actions.contains(.skip))
    }
}

struct PlanDayActionTests {
    @Test func planDayIsTiedToStartDay() {
        #expect(PopoverAction.planDay.sessionAction == .startDay)
        #expect(PopoverAction.planDay.titleKey == "ui.planDay")
    }
}

struct OverviewActionTests {
    @Test(arguments: [Phase.working, .onBreak, .paused(onBreak: false), .overtime(onBreak: false), .finished])
    func theOverviewIsAlwaysOffered(phase: Phase) {
        let shown = PopoverActions.visible(phase: phase, isAllowed: { _ in false })
        #expect(shown == (phase == .finished ? [.summary] : [.overview]))
    }

    @Test func theOverviewActionsAreNotEngineActions() {
        #expect(PopoverAction.overview.sessionAction == nil)
        #expect(PopoverAction.summary.sessionAction == nil)
        #expect(PopoverAction.pause.sessionAction == .pause)
        #expect(PopoverAction.next.sessionAction == .advance)
    }

    @Test func titles() {
        #expect(PopoverAction.overview.titleKey == "ui.overview")
        #expect(PopoverAction.summary.titleKey == "ui.summary")
    }
}
