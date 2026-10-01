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

    // MARK: day plan form

    @Test func theFormDefaultsToStandard() {
        let suite = Suite(); defer { suite.cleanUp() }
        #expect(AppSettings(defaults: suite.defaults).dayPlanForm == .standard)
    }

    @Test func aChangedFormPersists() {
        let suite = Suite(); defer { suite.cleanUp() }
        var form = DayPlanForm.standard
        form.presetChoice = .custom
        form.mode = .netFocus
        form.focusMinutes = 100
        form.longBreak = .afterBlock(2)
        AppSettings(defaults: suite.defaults).dayPlanForm = form
        #expect(AppSettings(defaults: suite.defaults).dayPlanForm == form)
    }

    @Test func outOfRangeStoredNumbersComeBackClamped() throws {
        let suite = Suite(); defer { suite.cleanUp() }
        var form = DayPlanForm.standard
        form.focusMinutes = 5000
        form.longBreak = .afterBlock(0)
        suite.defaults.set(try JSONEncoder().encode(form), forKey: "dayPlanForm")
        let restored = AppSettings(defaults: suite.defaults).dayPlanForm
        #expect(restored.focusMinutes == 720)
        #expect(restored.longBreak == .afterBlock(1))
    }

    @Test func undecodableFormDataGivesTheStandardForm() {
        let suite = Suite(); defer { suite.cleanUp() }
        suite.defaults.set(Data("garbage".utf8), forKey: "dayPlanForm")
        #expect(AppSettings(defaults: suite.defaults).dayPlanForm == .standard)
    }

    @Test func anUnknownCaseGivesTheStandardForm() throws {
        let suite = Suite(); defer { suite.cleanUp() }
        let json = try String(decoding: JSONEncoder().encode(DayPlanForm.standard), as: UTF8.self)
            .replacingOccurrences(of: "deepWork", with: "removedInALaterVersion")
        suite.defaults.set(Data(json.utf8), forKey: "dayPlanForm")
        #expect(AppSettings(defaults: suite.defaults).dayPlanForm == .standard)
    }

    @Test func writingAnOutOfRangeFormStoresTheClampedOne() throws {
        let suite = Suite(); defer { suite.cleanUp() }
        let settings = AppSettings(defaults: suite.defaults)
        var form = DayPlanForm.standard
        form.focusMinutes = 5000
        settings.dayPlanForm = form
        #expect(settings.dayPlanForm.focusMinutes == 720)
        let stored = try #require(suite.defaults.data(forKey: "dayPlanForm"))
        #expect(try JSONDecoder().decode(DayPlanForm.self, from: stored).focusMinutes == 720)
    }
}
