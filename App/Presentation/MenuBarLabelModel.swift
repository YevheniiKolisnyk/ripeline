import Foundation

/// What the menu bar item shows: an icon and, optionally, a time.
struct MenuBarLabelModel: Equatable {
    /// The picture in the menu bar.
    enum Icon: Equatable {
        /// An SF Symbol for the phase.
        case symbol(String)
        /// The tomato of the work block that is running, drawn as grown so far; `frozen` while it is paused.
        case tomato(growth: Double, frozen: Bool)
    }

    let icon: Icon
    /// `nil` when the time is hidden by the user or there is no running segment.
    let text: String?

    init(icon: Icon, text: String?) {
        self.icon = icon
        self.text = text
    }

    /// - Parameter tomatoGrowth: How grown the tomato of the current work block is, if there is one.
    init(phase: Phase, remaining: TimeInterval?, overtimeElapsed: TimeInterval?, showTime: Bool, tomatoGrowth: Double? = nil) {
        switch (phase, tomatoGrowth) {
        case let (.working, growth?), let (.overtime(onBreak: false), growth?):
            icon = .tomato(growth: growth, frozen: false)
        case let (.paused(onBreak: false), growth?):
            icon = .tomato(growth: growth, frozen: true)
        default:
            icon = .symbol(phase.symbolName)
        }
        guard showTime else {
            text = nil
            return
        }
        switch phase {
        case .working, .onBreak, .paused:
            text = remaining.map(TimerText.countdown)
        case .overtime:
            text = overtimeElapsed.map(TimerText.overtime)
        case .idle, .finished:
            text = nil
        }
    }
}
