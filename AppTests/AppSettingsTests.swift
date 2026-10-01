import Foundation
import Observation
import RipelineCore
import Synchronization
import Testing
@testable import Ripeline

@MainActor
struct AppSettingsTests {
    /// A throwaway `UserDefaults` suite, removed again by `cleanUp`.
    private struct Suite {
        let name = "ripeline-tests-\(UUID().uuidString)"
        var defaults: UserDefaults { UserDefaults(suiteName: name)! }
        func cleanUp() { UserDefaults().removePersistentDomain(forName: name) }
    }

    @Test func defaults() {
        let suite = Suite(); defer { suite.cleanUp() }
        let settings = AppSettings(defaults: suite.defaults)
        #expect(settings.showTimeInMenuBar == true)
        #expect(settings.session == SessionSettings())
    }

    @Test func showTimePersists() {
        let suite = Suite(); defer { suite.cleanUp() }
        AppSettings(defaults: suite.defaults).showTimeInMenuBar = false
        #expect(AppSettings(defaults: suite.defaults).showTimeInMenuBar == false)
    }

    @Test func sessionSettingsPersist() {
        let suite = Suite(); defer { suite.cleanUp() }
        let chosen = SessionSettings(pausesCountAsRest: false, autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true)
        AppSettings(defaults: suite.defaults).session = chosen
        #expect(AppSettings(defaults: suite.defaults).session == chosen)
    }

    @Test func undecodableSessionDataFallsBackToDefaults() {
        let suite = Suite(); defer { suite.cleanUp() }
        suite.defaults.set(Data("garbage".utf8), forKey: "sessionSettings")
        #expect(AppSettings(defaults: suite.defaults).session == SessionSettings())
    }

    @Test func changesAreObservable() {
        let suite = Suite(); defer { suite.cleanUp() }
        let settings = AppSettings(defaults: suite.defaults)
        let changes = Mutex(0)
        withObservationTracking {
            _ = settings.showTimeInMenuBar
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        settings.showTimeInMenuBar = false
        #expect(changes.withLock { $0 } == 1)
    }
}
