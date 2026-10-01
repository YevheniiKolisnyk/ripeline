import Foundation

/// What VoiceOver says about the timer. Coarser than what is drawn: it changes once a minute, so
/// it is not announced every second.
enum AccessibilityText {
    /// The time left, rounded up to whole minutes; or the time over the plan, rounded down.
    /// `nil` when there is no running segment.
    static func timerValue(
        phase: Phase, remaining: TimeInterval?, overtimeElapsed: TimeInterval?,
        locale: Locale, bundle: Bundle = .main
    ) -> String? {
        switch phase {
        case .working, .onBreak, .paused:
            guard let remaining else { return nil }
            return SetupText.duration((max(0, remaining) / 60).rounded(.up) * 60, locale: locale)
        case .overtime:
            guard let overtimeElapsed else { return nil }
            let format = bundle.localizedString(forKey: "a11y.overtime", value: nil, table: nil)
            return String(format: format, SetupText.duration((max(0, overtimeElapsed) / 60).rounded(.down) * 60, locale: locale))
        case .idle, .finished:
            return nil
        }
    }

    /// The menu bar item as a whole: `Ripeline, Work, 33 min`.
    static func menuBarLabel(
        phase: Phase, remaining: TimeInterval?, overtimeElapsed: TimeInterval?,
        locale: Locale, bundle: Bundle = .main
    ) -> String {
        var parts = [
            bundle.localizedString(forKey: "app.name", value: nil, table: nil),
            bundle.localizedString(forKey: Self.phaseKey(phase), value: nil, table: nil),
        ]
        if let value = timerValue(phase: phase, remaining: remaining, overtimeElapsed: overtimeElapsed, locale: locale, bundle: bundle) {
            parts.append(value)
        }
        return parts.joined(separator: ", ")
    }

    private static func phaseKey(_ phase: Phase) -> String {
        switch phase {
        case .idle: "phase.idle"
        case .working: "phase.working"
        case .onBreak: "phase.break"
        case .paused: "phase.paused"
        case .overtime: "phase.overtime"
        case .finished: "phase.finished"
        }
    }
}
