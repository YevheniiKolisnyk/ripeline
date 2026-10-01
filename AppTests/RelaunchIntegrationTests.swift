import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// End to end: a day is saved by one controller and continued by a new one over the same files,
/// the way a quit and relaunch (or a long sleep) goes.
@MainActor
struct RelaunchIntegrationTests {
    @MainActor private struct World {
        let directory: URL
        let suite: String

        init() {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-e2e-\(UUID().uuidString)")
            suite = "ripeline-tests-\(UUID().uuidString)"
        }

        /// A fresh controller, as after a launch, over the same directory, at `now`.
        func launch(at now: Date, session: SessionSettings? = nil) -> (SessionController, SpyNotifier, TestClock) {
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            if let session { settings.session = session }
            let notifier = SpyNotifier()
            let clock = TestClock(now)
            let controller = SessionController(
                clock: clock, store: FileDayStore(directory: directory, calendar: utc),
                notifier: notifier, ticker: ManualTicker(), settings: settings, calendar: utc
            )
            controller.restore()
            return (controller, notifier, clock)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    @Test func aPausedDayContinuesAfterRelaunch() async {
        let world = World(); defer { world.cleanUp() }
        let (first, _, clock) = world.launch(at: t(9))
        await first.startQuickDay()
        clock.set(t(9, 20)); first.pause()

        let (second, _, _) = world.launch(at: t(9, 40))
        #expect(second.phase == .paused(onBreak: false))
        #expect(second.remaining == minutes(30))
        second.resume()
        #expect(second.phase == .working)
        #expect(second.remaining == minutes(30))
    }

    @Test func aRunningDayCountsTheTimeTheAppWasClosed() async {
        let world = World(); defer { world.cleanUp() }
        let (first, _, _) = world.launch(at: t(9))
        await first.startQuickDay()

        let (second, notifier, _) = world.launch(at: t(9, 20))
        #expect(second.phase == .working)
        #expect(second.remaining == minutes(30))
        #expect(notifier.calls == [.schedule(.workEnded, 1800)])
    }

    @Test func sleepingThroughASegmentEndLandsInOvertimeWithASummary() async {
        let world = World(); defer { world.cleanUp() }
        let (first, _, _) = world.launch(at: t(9))
        await first.startQuickDay()

        let (second, notifier, _) = world.launch(at: t(9, 55))
        #expect(second.phase == .overtime(onBreak: false))
        #expect(second.overtimeElapsed == minutes(5))
        #expect(notifier.calls == [.deliver(.workEnded), .cancelAll])
    }

    @Test func autoAdvanceWalksThroughSegmentsClosedInTheMeantime() async {
        let world = World(); defer { world.cleanUp() }
        let auto = SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true)
        let (first, _, _) = world.launch(at: t(9), session: auto)
        await first.startQuickDay()

        let (second, notifier, _) = world.launch(at: t(11, 15))
        // 09:00 W50, 09:50 B10, 10:00 W50, 10:50 B10, 11:00 W50 → third work block, 11:00–11:50.
        #expect(second.phase == .working)
        #expect(second.currentSegment?.index == 4)
        #expect(second.remaining == minutes(35))
        #expect(notifier.calls.first == .deliver(.breakEnded))
    }

    @Test func aFinishedDayStartsFreshButIsKeptOnDisk() async throws {
        let world = World(); defer { world.cleanUp() }
        let (first, _, clock) = world.launch(at: t(9))
        await first.startQuickDay()
        clock.set(t(9, 30)); first.endDay()

        let (second, _, _) = world.launch(at: t(12))
        #expect(second.phase == .idle)
        #expect(second.plan.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.directory.path) == ["2026-01-15.json"])

        // Starting another day the same date keeps the first.
        await second.startQuickDay()
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.directory.path).sorted() == ["2026-01-15-2.json", "2026-01-15.json"])
    }
}
