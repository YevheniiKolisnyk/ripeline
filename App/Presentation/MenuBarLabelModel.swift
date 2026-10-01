import Foundation

/// What the menu bar item shows: an icon and, optionally, a time.
struct MenuBarLabelModel: Equatable {
    let symbolName: String
    /// `nil` when the time is hidden by the user or there is no running segment.
    let text: String?

    init(symbolName: String, text: String?) {
        self.symbolName = symbolName
        self.text = text
    }

    init(phase: Phase, remaining: TimeInterval?, overtimeElapsed: TimeInterval?, showTime: Bool) {
        symbolName = phase.symbolName
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
