import Foundation
import Observation
import RipelineCore

/// The state behind the day setup window: the form, the plan it makes right now, and starting it.
///
/// Views only display this. The result is computed by `DaySetup.evaluate` and kept current by
/// `refresh()`, which the window calls as the minutes pass.
@MainActor @Observable
final class DaySetupModel {
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let canStart: @MainActor () -> Bool
    @ObservationIgnored private let start: @MainActor (DayPlanRequest) async -> Bool
    @ObservationIgnored private var isStarting = false

    /// What the user has entered. Every change is saved, clamped into range, and re-evaluated.
    var form: DayPlanForm {
        didSet {
            settings.dayPlanForm = form
            let stored = settings.dayPlanForm
            if stored != form { form = stored; return }
            result = DaySetup.evaluate(form: form, now: now, calendar: calendar)
        }
    }

    /// The moment the current `result` was computed for.
    private(set) var now: Date
    private(set) var result: DaySetupResult

    /// - Parameters:
    ///   - canStart: Whether a new day may start now (no day is running).
    ///   - start: Starts the day; returns whether one was started.
    init(
        settings: AppSettings, clock: any WallClock, calendar: Calendar = .autoupdatingCurrent,
        canStart: @escaping @MainActor () -> Bool,
        start: @escaping @MainActor (DayPlanRequest) async -> Bool
    ) {
        self.settings = settings
        self.clock = clock
        self.calendar = calendar
        self.canStart = canStart
        self.start = start
        let form = settings.dayPlanForm
        let now = clock.now
        self.form = form
        self.now = now
        self.result = DaySetup.evaluate(form: form, now: now, calendar: calendar)
    }

    /// A day is running, so a new one cannot be planned until it ends.
    var isDayRunning: Bool { !canStart() }

    var canStartNow: Bool {
        if case .ready = result { return canStart() }
        return false
    }

    /// Recomputes the plan for the current time.
    func refresh() {
        now = clock.now
        result = DaySetup.evaluate(form: form, now: now, calendar: calendar)
    }

    /// Starts the day from the form, as of this very moment. Returns `false`, and starts nothing,
    /// when the form is invalid, a day is running, or another start is still in flight.
    @discardableResult
    func startDay() async -> Bool {
        guard !isStarting else { return false }
        isStarting = true
        defer { isStarting = false }
        refresh()
        guard case let .ready(request, _, _) = result, canStart() else { return false }
        return await start(request)
    }
}
