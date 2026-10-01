import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// End to end: a day planned in the form is started through the model, saved to real files,
/// and continued by a new controller, the way a relaunch goes.
@MainActor
struct SetupRelaunchTests {
    @MainActor private struct World {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-setup-\(UUID().uuidString)")
        let suite = "ripeline-tests-\(UUID().uuidString)"

        struct Launch {
            let controller: SessionController
            let model: DaySetupModel
            let settings: AppSettings
            let clock: TestClock
        }

        /// A fresh controller and model, as after a launch, over the same files and settings.
        func launch(at now: Date) -> Launch {
            let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
            let clock = TestClock(now)
            let controller = SessionController(
                clock: clock, store: FileDayStore(directory: directory, calendar: utc),
                notifier: SpyNotifier(), ticker: ManualTicker(), settings: settings, calendar: utc
            )
            controller.restore()
            let model = DaySetupModel(
                settings: settings, clock: clock, calendar: utc,
                canStart: { controller.isAllowed(.startDay) },
                start: { await controller.startDay(request: $0) }
            )
            return Launch(controller: controller, model: model, settings: settings, clock: clock)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: directory)
            UserDefaults().removePersistentDomain(forName: suite)
        }
    }

    private func configure(_ model: DaySetupModel) {
        model.form.presetChoice = .custom
        model.form.customPreset = Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15)
        model.form.mode = .netFocus
        model.form.focusMinutes = 100
        model.form.longBreak = .afterBlock(2)
    }

    @Test func aPlannedDayRunsExactlyAsPreviewedAndContinuesAfterRelaunch() async throws {
        let world = World(); defer { world.cleanUp() }
        let first = world.launch(at: t(9))
        configure(first.model)

        guard case let .ready(_, preview, _) = first.model.result else { Issue.record("not ready"); return }
        #expect(preview.segments.map(\.kind) == [.work, .shortBreak, .work, .longBreak, .work, .shortBreak, .work])

        #expect(await first.model.startDay())
        #expect(first.controller.plan.map(\.kind) == preview.segments.map(\.kind))
        #expect(first.controller.plan.map(\.start) == preview.segments.map(\.start))
        #expect(first.controller.plan.map(\.end) == preview.segments.map(\.end))

        // Relaunch ten minutes in: the same plan, the countdown continues, the form is remembered.
        let second = world.launch(at: t(9, 10))
        #expect(second.controller.phase == .working)
        #expect(second.controller.remaining == minutes(15))
        #expect(second.controller.plan.map(\.end) == preview.segments.map(\.end))
        #expect(second.settings.dayPlanForm == first.model.form)
        #expect(second.model.form.focusMinutes == 100)
    }

    @Test func aRunningDayBlocksPlanningAnother() async {
        let world = World(); defer { world.cleanUp() }
        let launch = world.launch(at: t(9))
        configure(launch.model)
        #expect(await launch.model.startDay())
        #expect(launch.model.isDayRunning)
        #expect(!launch.model.canStartNow)
        #expect(await launch.model.startDay() == false)
        #expect(launch.controller.plan.count == 7)
    }

    @Test func afterTheDayEndsAnotherCanBePlannedAndBothAreKept() async throws {
        let world = World(); defer { world.cleanUp() }
        let launch = world.launch(at: t(9))
        configure(launch.model)
        #expect(await launch.model.startDay())
        launch.clock.set(t(9, 30)); launch.controller.endDay()
        #expect(!launch.model.isDayRunning)

        launch.clock.set(t(13))
        launch.model.form.focusMinutes = 50
        #expect(await launch.model.startDay())
        #expect(launch.controller.plan[0].start == t(13))
        let files = try FileManager.default.contentsOfDirectory(atPath: world.directory.path).sorted()
        #expect(files == ["2026-01-15-2.json", "2026-01-15.json"])
    }
}
