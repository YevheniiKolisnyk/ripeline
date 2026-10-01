import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct DaySetupModelTests {
    /// Records what the model asks to start, and can hold a start open to model the permission prompt.
    @MainActor final class StartRecorder {
        var requests: [DayPlanRequest] = []
        var outcome = true
        var holdStart = false
        var pending: CheckedContinuation<Void, Never>?
        var canStart = true

        func start(_ request: DayPlanRequest) async -> Bool {
            requests.append(request)
            if holdStart { await withCheckedContinuation { pending = $0 } }
            return outcome
        }

        func release() { pending?.resume(); pending = nil }
    }

    private struct Fixture {
        let model: DaySetupModel
        let clock: TestClock
        let settings: AppSettings
        let recorder: StartRecorder
        let suite: String

        func cleanUp() { UserDefaults().removePersistentDomain(forName: suite) }
    }

    private func makeFixture(now: Date = t(9), suite: String = "ripeline-tests-\(UUID().uuidString)") -> Fixture {
        let clock = TestClock(now)
        let settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        let recorder = StartRecorder()
        let model = DaySetupModel(
            settings: settings, clock: clock, calendar: utc,
            canStart: { recorder.canStart }, start: { await recorder.start($0) }
        )
        return Fixture(model: model, clock: clock, settings: settings, recorder: recorder, suite: suite)
    }

    // MARK: form and persistence

    @Test func theFormIsLoadedFromSettings() {
        let suite = "ripeline-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        var stored = DayPlanForm.standard
        stored.mode = .netFocus
        stored.focusMinutes = 90
        AppSettings(defaults: UserDefaults(suiteName: suite)!).dayPlanForm = stored
        #expect(makeFixture(suite: suite).model.form == stored)
    }

    @Test func changesAreSavedAndRestored() {
        let f = makeFixture(); defer { f.cleanUp() }
        f.model.form.focusMinutes = 100
        f.model.form.longBreak = .afterBlock(2)
        #expect(f.settings.dayPlanForm.focusMinutes == 100)
        let restored = makeFixture(suite: f.suite).model.form
        #expect(restored.focusMinutes == 100)
        #expect(restored.longBreak == .afterBlock(2))
    }

    @Test func outOfRangeInputIsClampedEverywhere() {
        let f = makeFixture(); defer { f.cleanUp() }
        f.model.form.focusMinutes = 5000
        #expect(f.model.form.focusMinutes == 720)
        #expect(f.settings.dayPlanForm.focusMinutes == 720)
    }

    @Test func undecodableStoredDataGivesTheStandardForm() {
        let suite = "ripeline-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        UserDefaults(suiteName: suite)!.set(Data("garbage".utf8), forKey: "dayPlanForm")
        #expect(makeFixture(suite: suite).model.form == .standard)
    }

    // MARK: the preview

    @Test func theResultFollowsTheForm() throws {
        let f = makeFixture(); defer { f.cleanUp() }
        guard case let .ready(_, before, _) = f.model.result else { Issue.record("not ready"); return }
        f.model.form.mode = .netFocus
        f.model.form.focusMinutes = 120
        guard case let .ready(_, after, _) = f.model.result else { Issue.record("not ready"); return }
        #expect(before.endsAt == t(16, 50))
        #expect(after.endsAt == t(11, 20))
    }

    @Test func theStageOneDayIsPreviewedExactly() throws {
        let f = makeFixture(); defer { f.cleanUp() }
        f.model.form.longBreak = .atTime(TimeOfDay(hour: 13, minute: 0))
        guard case let .ready(_, preview, notices) = f.model.result else { Issue.record("not ready"); return }
        let longBreak = try #require(preview.segments.first { $0.kind == .longBreak })
        #expect(longBreak.start == t(12, 50))
        #expect(longBreak.end == t(13, 35))
        #expect(preview.focus == minutes(375))
        #expect(notices.isEmpty)
    }

    @Test func refreshingMovesThePreviewWithTheClock() {
        let f = makeFixture(now: t(16, 0)); defer { f.cleanUp() }
        #expect(f.model.result != .invalid(.endNotAfterNow))
        f.clock.set(t(17, 5))
        f.model.refresh()
        #expect(f.model.now == t(17, 5))
        #expect(f.model.result == .invalid(.endNotAfterNow))
    }

    // MARK: starting

    @Test func startingUsesTheRequestEvaluatedAtClickTime() async {
        let f = makeFixture(now: t(9)); defer { f.cleanUp() }
        f.clock.set(t(9, 1))                           // a minute passes without a refresh
        let started = await f.model.startDay()
        #expect(started)
        #expect(f.recorder.requests.count == 1)
        guard case let .untilTime(start, _) = f.recorder.requests[0].mode else { Issue.record("not untilTime"); return }
        #expect(start == t(9, 1))
    }

    /// Review Focus 2: ready in the preview, but the end time has passed by the click.
    @Test func aPreviewThatWentStaleDoesNotStart() async {
        let f = makeFixture(now: t(16, 0)); defer { f.cleanUp() }
        #expect(f.model.canStartNow)
        f.clock.set(t(17, 0, 30))
        let started = await f.model.startDay()
        #expect(!started)
        #expect(f.recorder.requests.isEmpty)
        #expect(f.model.result == .invalid(.endNotAfterNow))
    }

    @Test func anInvalidFormDoesNotStart() async {
        let f = makeFixture(now: t(17, 30)); defer { f.cleanUp() }
        #expect(!f.model.canStartNow)
        #expect(await f.model.startDay() == false)
        #expect(f.recorder.requests.isEmpty)
    }

    /// Review Focus 3: a day is already running.
    @Test func aRunningDayBlocksStarting() async {
        let f = makeFixture(); defer { f.cleanUp() }
        f.recorder.canStart = false
        #expect(f.model.isDayRunning)
        #expect(!f.model.canStartNow)
        #expect(await f.model.startDay() == false)
        #expect(f.recorder.requests.isEmpty)
    }

    /// Review Focus 3: a double click while the first start waits for the permission prompt.
    @Test func aSecondStartWhileOneIsInFlightIsIgnored() async {
        let f = makeFixture(); defer { f.cleanUp() }
        f.recorder.holdStart = true
        let first = Task { await f.model.startDay() }
        while f.recorder.pending == nil { await Task.yield() }
        f.recorder.holdStart = false        // so a missing guard fails the test instead of hanging it
        #expect(await f.model.startDay() == false)
        #expect(f.recorder.requests.count == 1)
        f.recorder.release()
        #expect(await first.value == true)

        #expect(await f.model.startDay() == true)        // usable again afterwards
        #expect(f.recorder.requests.count == 2)
    }

    @Test func aRefusedStartIsReportedAndTheModelStaysUsable() async {
        let f = makeFixture(); defer { f.cleanUp() }
        f.recorder.outcome = false
        #expect(await f.model.startDay() == false)
        f.recorder.outcome = true
        #expect(await f.model.startDay() == true)
    }
}
