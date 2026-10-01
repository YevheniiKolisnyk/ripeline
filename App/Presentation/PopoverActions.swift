import RipelineCore

/// A button in the popover.
enum PopoverAction: Equatable, Sendable {
    case planDay, overview, summary, history, pause, resume, extend, skip, next, endDay

    /// The engine action this button leads to, to ask whether it is allowed. "Plan day" opens the
    /// window, which starts the day. `nil` for buttons that only open the window: always shown.
    var sessionAction: SessionAction? {
        switch self {
        case .overview, .summary, .history: nil
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
        case .overview: "ui.overview"
        case .summary: "ui.summary"
        case .history: "ui.history"
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
    /// The buttons to show, in order, for `phase`, limited to what the engine allows. In overtime
    /// "Next" replaces "Skip", which would do the same thing. While a day runs the overview link
    /// comes last before the history link, which every phase offers; a finished day offers its summary;
    /// with no day, planning one.
    static func visible(phase: Phase, isAllowed: (SessionAction) -> Bool) -> [PopoverAction] {
        let candidates: [PopoverAction]
        switch phase {
        case .idle: candidates = [.planDay]
        case .finished: candidates = [.summary]
        case .working, .onBreak: candidates = [.pause, .extend, .skip, .endDay, .overview]
        case .paused: candidates = [.resume, .extend, .skip, .endDay, .overview]
        case .overtime: candidates = [.next, .extend, .endDay, .overview]
        }
        return (candidates + [.history]).filter { $0.sessionAction.map(isAllowed) ?? true }
    }
}
