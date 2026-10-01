import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// End to end: a quick session grows, is paused and has a break skipped over real files, and a new
/// launch restores exactly it; the history lists it as quick and deleting it leaves other days alone.
@MainActor
struct QuickRelaunchTests {
    @MainActor private struct World {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-quick-e2e-\(UUID().uuidString)")
        let suite = "ripeline-tests-\(UUID().uuidString)"

        struct Launch {
            let controller: SessionController
            let overview: DayOverviewModel
            let clock: TestClock
        }

        func launch(at now: Date) -> Launch {
            let clock = TestClock(now)
            let controller = SessionController(
                clock: clock, store: FileDayStore(directory: directory, calendar: utc), notifier: SpyNotifier(),
                ticker: ManualTicker(), settings: AppSettings(defaults: UserDefaults(suiteName: suite)!), calendar: utc
            )
            controller.restore()
            return Launch(controller: controller, overview: DayOverviewModel(source: controller, calendar: utc), clock: clock)
        }

        func history(activeDayID: @escaping @MainActor () -> UUID? = { nil }) -> HistoryModel {
            HistoryModel(store: FileDayStore(directory: directory, calendar: utc), activeDayID: activeDayID, calendar: utc)
        }

        func bytes(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        func names() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// An ordinary day the day before, then a quick session: two added blocks, a pause, a skipped break.
    private func playQuickSession(_ world: World) async -> World.Launch {
        let earlier = world.launch(at: d(14, 9))
        await earlier.controller.startStandardDay(at: d(14, 9))
        earlier.clock.set(d(14, 9, 30)); earlier.controller.endDay()

        let first = world.launch(at: t(9))
        #expect(await first.controller.startQuickSession(length: .short))
        first.clock.set(t(9, 10)); first.controller.pause()
        first.clock.set(t(9, 15)); first.controller.resume()
        first.clock.set(t(9, 20)); first.controller.addBlock()        // a break and a second block follow
        first.clock.set(t(9, 31)); first.controller.advance()         // the first block ran over, the break starts
        first.clock.set(t(9, 32)); first.controller.skip()            // the break is skipped
        first.clock.set(t(9, 40)); first.controller.addBlock()        // and one more
        first.clock.set(t(9, 41)); first.overview.refresh()
        return first
    }

    @Test func aNewLaunchRestoresTheSessionAndDrawsTheSameOverview() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = await playQuickSession(world)
        #expect(first.controller.plan.count == 5)                      // block, break, block, break, block
        #expect(first.controller.isQuickSession)

        let second = world.launch(at: t(9, 41))
        second.overview.refresh()

        #expect(second.controller.isQuickSession)
        #expect(second.controller.phase == first.controller.phase)
        #expect(second.controller.plan == first.controller.plan)
        #expect(second.overview.mode == .running)
        #expect(second.overview.isQuick)
        #expect(second.overview.planned == first.overview.planned)
        #expect(second.overview.actual == first.overview.actual)
        #expect(second.overview.segments == first.overview.segments)
        #expect(second.overview.summary == first.overview.summary)
        #expect(second.overview.nowX == first.overview.nowX)
        #expect(second.overview.lag == nil && first.overview.lag == nil)
        #expect(second.overview.segments[1].status == .skipped)
        #expect(second.overview.summary?.plannedEnd == nil)

        // The restored session still takes another block and ends like any other.
        second.controller.addBlock()
        #expect(second.controller.plan.count == 7)
        second.clock.set(t(9, 50)); second.controller.endDay()
        #expect(second.controller.phase == .finished)
    }

    @Test func theHistoryListsItAsQuickAndDeletingItLeavesOtherDaysAlone() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = await playQuickSession(world)
        first.clock.set(t(9, 50)); first.controller.endDay()
        let ordinary = ["2026-01-14.json"]
        let before = try ordinary.map { ($0, try world.bytes($0)) }

        let history = world.history()
        history.refresh()
        #expect(history.entries.map(\.id) == ["2026-01-15", "2026-01-14"])
        let quick = try #require(history.entries.first { $0.id == "2026-01-15" })
        #expect(quick.isQuick && quick.isFinished && quick.lag == nil)
        #expect(try #require(history.entries.first { $0.id == "2026-01-14" }).isQuick == false)
        history.select("2026-01-15")
        #expect(history.detail?.summary?.plannedEnd == nil)

        history.requestDelete("2026-01-15")
        history.confirmDelete()
        #expect(try world.names() == ordinary)
        for (name, data) in before { #expect(try world.bytes(name) == data, "\(name) changed") }
    }
}
