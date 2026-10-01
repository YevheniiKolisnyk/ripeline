import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// End to end: a day with pauses, overtime and a skipped segment is recorded over real files, and a
/// new launch draws exactly the same overview.
@MainActor
struct OverviewRelaunchTests {
    @MainActor private struct World {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-overview-\(UUID().uuidString)")
        let suite = "ripeline-tests-\(UUID().uuidString)"

        struct Launch {
            let controller: SessionController
            let setup: DaySetupModel
            let overview: DayOverviewModel
            let settings: AppSettings
            let clock: TestClock
        }

        func launch(at now: Date) -> Launch {
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            let clock = TestClock(now)
            let controller = SessionController(
                clock: clock, store: FileDayStore(directory: directory, calendar: utc),
                notifier: SpyNotifier(), ticker: ManualTicker(), settings: settings, calendar: utc
            )
            controller.restore()
            let setup = DaySetupModel(
                settings: settings, clock: clock, calendar: utc,
                canStart: { controller.isAllowed(.startDay) },
                start: { await controller.startDay(request: $0) }
            )
            return Launch(
                controller: controller, setup: setup, overview: DayOverviewModel(source: controller, calendar: utc),
                settings: settings, clock: clock
            )
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    /// 25/5/15 blocks, 100 minutes of focus, long break after block 2; pauses count as untracked.
    private func plan(_ launch: World.Launch) {
        launch.controller.updateSessionSettings(SessionSettings(pausesCountAsRest: false))
        launch.setup.form.presetChoice = .custom
        launch.setup.form.customPreset = Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15)
        launch.setup.form.mode = .netFocus
        launch.setup.form.focusMinutes = 100
        launch.setup.form.longBreak = .afterBlock(2)
    }

    @Test func aNewLaunchDrawsTheSameOverview() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = world.launch(at: t(9))
        plan(first)
        #expect(await first.setup.startDay())
        first.clock.set(t(9, 10)); first.controller.pause()
        first.clock.set(t(9, 15)); first.controller.resume()
        first.clock.set(t(9, 33)); first.controller.advance()       // the first block ran 3 minutes over
        first.clock.set(t(9, 35)); first.controller.skip()           // the break is skipped
        first.clock.set(t(9, 36)); first.overview.refresh()

        let second = world.launch(at: t(9, 36))
        second.overview.refresh()

        #expect(second.overview.mode == .running)
        #expect(second.overview.planned == first.overview.planned)
        #expect(second.overview.actual == first.overview.actual)
        #expect(second.overview.segments == first.overview.segments)
        #expect(second.overview.summary == first.overview.summary)
        #expect(second.overview.lag == first.overview.lag)
        #expect(second.overview.nowX == first.overview.nowX)

        // And it is the day that was played: an untracked pause, a long first block, a skipped break.
        #expect(second.overview.actual.contains { $0.kind == .untracked })
        #expect(second.overview.segments[0].untracked == minutes(5))
        #expect(second.overview.segments[0].delta == minutes(8))      // 25 planned + 5 paused + 3 over
        #expect(second.overview.segments[1].status == .skipped)
    }

    @Test func settingsChosenDuringTheDayPersistAndApplyAtTheNextTransition() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = world.launch(at: t(9))
        plan(first)
        #expect(await first.setup.startDay())
        first.clock.set(t(9, 20))
        first.controller.updateSessionSettings(SessionSettings(pausesCountAsRest: false, autoAdvanceWorkToBreak: true))

        // The app is closed. The first block ended at 09:25; with the setting on, the break began by itself.
        let second = world.launch(at: t(9, 27))
        #expect(second.settings.session.autoAdvanceWorkToBreak)
        #expect(second.controller.phase == .onBreak)
        second.overview.refresh()
        #expect(second.overview.segments[0].status == .completed)
        #expect(second.overview.segments[1].status == .active)
    }

    /// A segment already in overtime is not advanced by a setting turned on afterwards.
    @Test func aSettingTurnedOnInOvertimeDoesNotAdvanceItAfterRelaunch() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = world.launch(at: t(9))
        plan(first)
        #expect(await first.setup.startDay())
        first.clock.set(t(9, 36)); first.controller.refresh()          // the ticker had seen 09:25 pass: overtime
        #expect(first.controller.phase == .overtime(onBreak: false))
        first.controller.updateSessionSettings(SessionSettings(pausesCountAsRest: false, autoAdvanceWorkToBreak: true))

        let second = world.launch(at: t(10, 2))
        #expect(second.controller.phase == .overtime(onBreak: false))
        #expect(second.controller.overtimeElapsed == minutes(37))
    }

    @Test func aFinishedDayIsNotRestoredAsTheActiveOneButItsFileIsKept() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = world.launch(at: t(9))
        plan(first)
        #expect(await first.setup.startDay())
        first.clock.set(t(9, 20)); first.controller.endDay()
        first.overview.refresh()
        #expect(first.overview.mode == .finished)
        #expect(first.overview.summary?.endIsFinal == true)

        let second = world.launch(at: t(12))
        #expect(second.controller.phase == .idle)
        second.overview.refresh()
        #expect(second.overview.mode == .noDay)
        #expect(try FileManager.default.contentsOfDirectory(atPath: world.directory.path).count == 1)
    }
}
