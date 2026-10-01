import Foundation

/// What the user is doing right now, in the terms the interface speaks.
enum Phase: Equatable, Sendable {
    case idle
    case working
    case onBreak
    case paused(onBreak: Bool)
    case overtime(onBreak: Bool)
    case finished

    /// SF Symbol shown in the menu bar.
    var symbolName: String {
        switch self {
        case .idle, .working: "timer"
        case .onBreak: "cup.and.saucer.fill"
        case .paused: "pause.circle.fill"
        case .overtime: "exclamationmark.circle.fill"
        case .finished: "checkmark.circle.fill"
        }
    }

    /// Localized name of the phase.
    var labelKey: LocalizedStringResource {
        switch self {
        case .idle: "phase.idle"
        case .working: "phase.working"
        case .onBreak: "phase.break"
        case .paused: "phase.paused"
        case .overtime: "phase.overtime"
        case .finished: "phase.finished"
        }
    }
}
