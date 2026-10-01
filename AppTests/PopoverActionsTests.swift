import RipelineCore
import Testing
@testable import Ripeline

struct PopoverActionsTests {
    private let everything: (SessionAction) -> Bool = { _ in true }

    @Test(arguments: [
        (Phase.idle, [PopoverAction.startDay]),
        (.finished, [.startDay]),
        (.working, [.pause, .extend, .skip, .endDay]),
        (.onBreak, [.pause, .extend, .skip, .endDay]),
        (.paused(onBreak: false), [.resume, .extend, .skip, .endDay]),
        (.paused(onBreak: true), [.resume, .extend, .skip, .endDay]),
        (.overtime(onBreak: false), [.next, .extend, .endDay]),
        (.overtime(onBreak: true), [.next, .extend, .endDay]),
    ])
    func buttonsForEachPhase(phase: Phase, expected: [PopoverAction]) {
        #expect(PopoverActions.visible(phase: phase, isAllowed: everything) == expected)
    }

    @Test func onlyAllowedActionsAreShown() {
        let onlyPause: (SessionAction) -> Bool = { $0 == .pause }
        #expect(PopoverActions.visible(phase: .working, isAllowed: onlyPause) == [.pause])
    }

    @Test func nothingIsShownWhenStartingIsNotAllowed() {
        #expect(PopoverActions.visible(phase: .idle, isAllowed: { _ in false }).isEmpty)
    }

    @Test func nextIsTiedToAdvance() {
        let onlyAdvance: (SessionAction) -> Bool = { $0 == .advance }
        #expect(PopoverActions.visible(phase: .overtime(onBreak: false), isAllowed: onlyAdvance) == [.next])
    }

    @Test func skipIsHiddenInOvertimeEvenIfAllowed() {
        let actions = PopoverActions.visible(phase: .overtime(onBreak: false), isAllowed: everything)
        #expect(!actions.contains(.skip))
    }
}
