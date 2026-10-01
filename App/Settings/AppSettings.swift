import Foundation
import Observation
import RipelineCore

/// The user's preferences, kept in `UserDefaults`.
@MainActor @Observable
final class AppSettings {
    private enum Key {
        static let showTime = "showTimeInMenuBar"
        static let session = "sessionSettings"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the menu bar item shows the time next to its icon. On by default.
    var showTimeInMenuBar: Bool {
        didSet { defaults.set(showTimeInMenuBar, forKey: Key.showTime) }
    }

    /// How sessions behave: pauses and auto-advance. Has no screen of its own until stage 2c.
    var session: SessionSettings {
        didSet { defaults.set(try? JSONEncoder().encode(session), forKey: Key.session) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showTimeInMenuBar = defaults.object(forKey: Key.showTime) as? Bool ?? true
        session = defaults.data(forKey: Key.session)
            .flatMap { try? JSONDecoder().decode(SessionSettings.self, from: $0) } ?? SessionSettings()
    }
}
