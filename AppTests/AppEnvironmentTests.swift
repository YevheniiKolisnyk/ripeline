import Foundation
import Testing
@testable import Ripeline

@MainActor
struct AppEnvironmentTests {
    @Test func detectsATestRun() {
        #expect(AppEnvironment.isRunningTests(["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(AppEnvironment.isRunningTests(["XCTestBundlePath": "/tmp/x.xctest"]))
        #expect(!AppEnvironment.isRunningTests([:]))
        #expect(!AppEnvironment.isRunningTests(["HOME": "/Users/someone"]))
    }

    /// If a runner change ever hid the XCTest variables, the hosted tests would silently switch to
    /// the developer's real days and the real notification center. This pins the detection.
    @Test func theHostedTestProcessIsRecognisedAsATestRun() {
        #expect(AppEnvironment.isRunningTests(ProcessInfo.processInfo.environment))
    }

    @Test func underTestsTheEnvironmentIsInert() {
        let environment = AppEnvironment.make(processEnvironment: ["XCTestConfigurationFilePath": "x"])
        #expect(environment.isInert)
        #expect(!(environment.store is FileDayStore))
        #expect(!(environment.notifier is SystemNotifier))
    }

    /// Review Focus 1: a hosted test run must never touch the developer's real days.
    @Test func theInertEnvironmentLeavesTheRealDayDirectoryAlone() async throws {
        let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let days = support.appendingPathComponent("Ripeline/days")
        func listing() -> [String]? { try? FileManager.default.contentsOfDirectory(atPath: days.path).sorted() }
        let before = listing()

        let environment = AppEnvironment.make(processEnvironment: ["XCTestConfigurationFilePath": "x"])
        environment.controller.restore()
        await environment.controller.startStandardDay(at: Date())
        environment.controller.pause()
        environment.controller.endDay()

        // Starting through the setup model is just as inert (net focus works at any time of day).
        environment.setupModel.form.mode = .netFocus
        #expect(await environment.setupModel.startDay())

        #expect(listing() == before)
        #expect(environment.controller.phase == .working)    // it still works, in memory

        environment.overviewModel.refresh()
        #expect(environment.overviewModel.mode == .running)
        // Starting a day never hops tabs by itself, and the running day is not in the history.
        #expect(environment.router.tab == .today)
        environment.historyModel.refresh()
        #expect(environment.historyModel.entries.isEmpty)
        #expect(listing() == before)
    }

    @Test func theRouterStartsOnToday() {
        #expect(AppRouter().tab == .today)
        #expect(AppEnvironment.make(processEnvironment: ["XCTestConfigurationFilePath": "x"]).router.tab == .today)
    }
}
