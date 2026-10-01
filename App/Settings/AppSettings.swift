import Foundation
import Observation
import RipelineCore

/// The user's preferences, kept in `UserDefaults`.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let showTime = "showTimeInMenuBar"
        static let session = "sessionSettings"
        static let dayPlanForm = "dayPlanForm"
        static let quickBlockMinutes = "quickBlockMinutes"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the menu bar item shows the time next to its icon. On by default.
    var showTimeInMenuBar: Bool {
        didSet { defaults.set(showTimeInMenuBar, forKey: Key.showTime) }
    }

    /// How sessions behave: pauses and auto-advance. Changed from the Behaviour section of the window.
    var session: SessionSettings {
        didSet { defaults.set(try? JSONEncoder().encode(session), forKey: Key.session) }
    }

    /// The last day plan the user entered. Always within range: stored and read back clamped.
    var dayPlanForm: DayPlanForm {
        didSet {
            let clamped = dayPlanForm.normalized()
            if clamped != dayPlanForm { dayPlanForm = clamped; return }
            defaults.set(try? JSONEncoder().encode(clamped), forKey: Key.dayPlanForm)
        }
    }

    /// The block length last chosen for a quick start. The shortest by default.
    var quickBlockLength: QuickBlockLength {
        didSet { defaults.set(quickBlockLength.minutes, forKey: Key.quickBlockMinutes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showTimeInMenuBar = defaults.object(forKey: Key.showTime) as? Bool ?? true
        session = defaults.data(forKey: Key.session)
            .flatMap { try? JSONDecoder().decode(SessionSettings.self, from: $0) } ?? SessionSettings()
        quickBlockLength = QuickBlockLength(rawValue: defaults.integer(forKey: Key.quickBlockMinutes)) ?? .short
        dayPlanForm = defaults.data(forKey: Key.dayPlanForm)
            .flatMap { try? JSONDecoder().decode(DayPlanForm.self, from: $0) }?.normalized() ?? .standard
    }
}
