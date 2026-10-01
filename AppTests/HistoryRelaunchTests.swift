import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// End to end: days are recorded by controllers over real files, and a history over a fresh store
/// instance lists them, leaves the running day out, and deletes one without touching the others.
@MainActor
struct HistoryRelaunchTests {
    @MainActor private struct World {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-history-e2e-\(UUID().uuidString)")
        let suite = "ripeline-tests-\(UUID().uuidString)"

        func launch(at now: Date) -> (controller: SessionController, clock: TestClock) {
            let clock = TestClock(now)
            let controller = SessionController(
                clock: clock, store: FileDayStore(directory: directory, calendar: utc), notifier: SpyNotifier(),
                ticker: ManualTicker(), settings: AppSettings(defaults: UserDefaults(suiteName: suite)!), calendar: utc
            )
            controller.restore()
            return (controller, clock)
        }

        /// A history over a new store instance, as after a relaunch.
        func history(activeDayID: @escaping @MainActor () -> UUID?) -> HistoryModel {
            HistoryModel(store: FileDayStore(directory: directory, calendar: utc), activeDayID: activeDayID, calendar: utc)
        }

        func bytes(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// Three days on two dates: a finished one with a pause, one that was never ended, one more finished.
    private func recordThreeDays(_ world: World) async {
        let first = world.launch(at: t(9))
        await first.controller.startStandardDay(at: t(9))
        first.clock.set(t(9, 10)); first.controller.pause()
        first.clock.set(t(9, 15)); first.controller.resume()
        first.clock.set(t(9, 40)); first.controller.endDay()

        let second = world.launch(at: t(13))
        await second.controller.startStandardDay(at: t(13))
        second.clock.set(t(13, 30)); second.controller.pause()
        second.clock.set(t(13, 35)); second.controller.resume()      // the app is closed here, the day never ended

        let third = world.launch(at: d(16, 9))                         // next morning: yesterday's day is stale
        await third.controller.startStandardDay(at: d(16, 9))
        third.clock.set(d(16, 9, 30)); third.controller.endDay()
    }

    @Test func theHistoryListsTheRecordedDaysWithTheirFigures() async throws {
        let world = World(); defer { world.cleanUp() }
        await recordThreeDays(world)

        let history = world.history { nil }
        history.refresh()
        #expect(history.entries.map(\.id) == ["2026-01-16", "2026-01-15-2", "2026-01-15"])

        let finished = try #require(history.entries.first { $0.id == "2026-01-15" })
        #expect(finished.isFinished)
        #expect(finished.focusActual == minutes(35))                  // 10 + 25 minutes of work
        #expect(finished.restActual == minutes(5))                    // the pause counted as rest
        #expect(finished.startedAt == t(9) && finished.endedAt == t(9, 40))

        let never = try #require(history.entries.first { $0.id == "2026-01-15-2" })
        #expect(!never.isFinished)
        #expect(never.endedAt == t(13, 35))
        #expect(never.lag == nil)

        history.select("2026-01-15-2")
        #expect(history.detail?.summary?.endKind == .lastRecord)
        #expect(history.detail?.nowX == nil)
    }

    @Test func deletingOneDayLeavesTheOthersUntouched() async throws {
        let world = World(); defer { world.cleanUp() }
        await recordThreeDays(world)
        let before = try (world.names().filter { $0 != "2026-01-15-2.json" }).map { ($0, try world.bytes($0)) }

        let history = world.history { nil }
        history.refresh()
        history.requestDelete("2026-01-15-2")
        history.confirmDelete()

        #expect(try world.names() == ["2026-01-15.json", "2026-01-16.json"])
        for (name, data) in before { #expect(try world.bytes(name) == data, "\(name) changed") }
        #expect(history.entries.map(\.id) == ["2026-01-16", "2026-01-15"])

        // After a relaunch the rest is what is listed.
        let again = world.history { nil }
        again.refresh()
        #expect(again.entries.map(\.id) == ["2026-01-16", "2026-01-15"])
    }

    @Test func theRunningDayIsNotListedAndCannotBeDeleted() async throws {
        let world = World(); defer { world.cleanUp() }
        await recordThreeDays(world)
        let live = world.launch(at: d(17, 9))
        await live.controller.startStandardDay(at: d(17, 9))          // running, not ended
        #expect(live.controller.activeDayID != nil)
        let filesBefore = try world.names()

        let history = world.history { live.controller.activeDayID }
        history.refresh()
        #expect(history.entries.map(\.id) == ["2026-01-16", "2026-01-15-2", "2026-01-15"])
        history.requestDelete("2026-01-17")
        #expect(history.pendingDelete == nil)
        history.confirmDelete()
        #expect(try world.names() == filesBefore)
    }
}
