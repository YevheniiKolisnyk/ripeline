import RipelineCore

/// A button in the popover.
enum PopoverAction: Equatable, Sendable {
    case planDay, pause, resume, extend, skip, next, endDay

    /// The engine action this button leads to, to ask whether it is allowed. "Plan day" opens the
    /// setup window, which starts the day.
    var sessionAction: SessionAction {
        switch self {
        case .planDay: .startDay
        case .pause: .pause
        case .resume: .resume
        case .extend: .extend
        case .skip: .skip
        case .next: .advance
        case .endDay: .endDay
        }
    }

    /// Key of the button's title in the String Catalog.
    var titleKey: String {
        switch self {
        case .planDay: "ui.planDay"
        case .pause: "ui.pause"
        case .resume: "ui.resume"
        case .extend: "ui.extend"
        case .skip: "ui.skip"
        case .next: "ui.next"
        case .endDay: "ui.endDay"
        }
    }
}

enum PopoverActions {
    /// The buttons to show, in order, for `phase`, limited to what the engine allows.
    /// In overtime "Next" replaces "Skip", which would do the same thing.
    static func visible(phase: Phase, isAllowed: (SessionAction) -> Bool) -> [PopoverAction] {
        let candidates: [PopoverAction]
        switch phase {
        case .idle, .finished: candidates = [.planDay]
        case .working, .onBreak: candidates = [.pause, .extend, .skip, .endDay]
        case .paused: candidates = [.resume, .extend, .skip, .endDay]
        case .overtime: candidates = [.next, .extend, .endDay]
        }
        return candidates.filter { isAllowed($0.sessionAction) }
    }
}
