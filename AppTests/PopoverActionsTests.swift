import RipelineCore
import Testing
@testable import Ripeline

struct PopoverActionsTests {
    private let everything: (SessionAction) -> Bool = { _ in true }

    @Test(arguments: [
        (Phase.idle, [PopoverAction.planDay, .history]),
        (.finished, [.summary, .history]),
        (.working, [.pause, .extend, .skip, .endDay, .overview, .history]),
        (.onBreak, [.pause, .extend, .skip, .endDay, .overview, .history]),
        (.paused(onBreak: false), [.resume, .extend, .skip, .endDay, .overview, .history]),
        (.paused(onBreak: true), [.resume, .extend, .skip, .endDay, .overview, .history]),
        (.overtime(onBreak: false), [.next, .extend, .endDay, .overview, .history]),
        (.overtime(onBreak: true), [.next, .extend, .endDay, .overview, .history]),
    ])
    func buttonsForEachPhase(phase: Phase, expected: [PopoverAction]) {
        #expect(PopoverActions.visible(phase: phase, isAllowed: everything) == expected)
    }

    @Test func onlyAllowedActionsAreShown() {
        let onlyPause: (SessionAction) -> Bool = { $0 == .pause }
        #expect(PopoverActions.visible(phase: .working, isAllowed: onlyPause) == [.pause, .overview, .history])
    }

    @Test func nothingIsShownWhenStartingIsNotAllowed() {
        #expect(PopoverActions.visible(phase: .idle, isAllowed: { _ in false }) == [.history])
    }

    @Test func nextIsTiedToAdvance() {
        let onlyAdvance: (SessionAction) -> Bool = { $0 == .advance }
        #expect(PopoverActions.visible(phase: .overtime(onBreak: false), isAllowed: onlyAdvance) == [.next, .overview, .history])
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
        #expect(shown == (phase == .finished ? [.summary, .history] : [.overview, .history]))
    }

    @Test func theOverviewActionsAreNotEngineActions() {
        #expect(PopoverAction.overview.sessionAction == nil)
        #expect(PopoverAction.summary.sessionAction == nil)
        #expect(PopoverAction.history.sessionAction == nil)
        #expect(PopoverAction.pause.sessionAction == .pause)
        #expect(PopoverAction.next.sessionAction == .advance)
    }

    @Test func titles() {
        #expect(PopoverAction.overview.titleKey == "ui.overview")
        #expect(PopoverAction.summary.titleKey == "ui.summary")
        #expect(PopoverAction.history.titleKey == "ui.history")
    }
}

struct QuickPopoverActionsTests {
    private let everything: (SessionAction) -> Bool = { _ in true }

    @Test(arguments: [
        (Phase.working, [PopoverAction.pause, .extend, .addBlock, .skip, .done, .overview, .history]),
        (.onBreak, [.pause, .extend, .addBlock, .skip, .done, .overview, .history]),
        (.paused(onBreak: false), [.resume, .extend, .addBlock, .skip, .done, .overview, .history]),
        (.paused(onBreak: true), [.resume, .extend, .addBlock, .skip, .done, .overview, .history]),
        (.overtime(onBreak: false), [.next, .extend, .addBlock, .done, .overview, .history]),
        (.overtime(onBreak: true), [.next, .extend, .addBlock, .done, .overview, .history]),
        (.idle, [.planDay, .history]),
        (.finished, [.summary, .history]),
    ])
    func buttonsOfAQuickSession(phase: Phase, expected: [PopoverAction]) {
        #expect(PopoverActions.visible(phase: phase, isQuick: true, isAllowed: everything) == expected)
    }

    @Test func anotherBlockAndDoneFollowTheEngine() {
        let onlyPause: (SessionAction) -> Bool = { $0 == .pause }
        #expect(PopoverActions.visible(phase: .working, isQuick: true, isAllowed: onlyPause) == [.pause, .overview, .history])
        let noAppend: (SessionAction) -> Bool = { $0 != .append }
        let shown = PopoverActions.visible(phase: .working, isQuick: true, isAllowed: noAppend)
        #expect(!shown.contains(.addBlock) && shown.contains(.done))
    }

    @Test func anOrdinaryDayNeverOffersThem() {
        for phase in [Phase.working, .onBreak, .paused(onBreak: false), .overtime(onBreak: false), .idle, .finished] {
            let shown = PopoverActions.visible(phase: phase, isQuick: false, isAllowed: everything)
            #expect(!shown.contains(.addBlock) && !shown.contains(.done), "\(phase)")
        }
    }

    @Test func theNewActionsMapToEngineActionsAndTitles() {
        #expect(PopoverAction.addBlock.sessionAction == .append)
        #expect(PopoverAction.done.sessionAction == .endDay)
        #expect(PopoverAction.addBlock.titleKey == "ui.addBlock")
        #expect(PopoverAction.done.titleKey == "ui.done")
    }
}
