import Foundation
import RipelineCore
@testable import Ripeline

/// A `SessionController` wired to test doubles.
@MainActor
struct Harness {
    let controller: SessionController
    let clock: TestClock
    let store: MemoryDayStore
    let notifier: SpyNotifier
    let ticker: ManualTicker
    let settings: AppSettings
    private let suite: String

    init(
        now: Date = t(9), stored: SessionSnapshot? = nil, calendar: Calendar = utc,
        session: SessionSettings? = nil
    ) {
        suite = "ripeline-tests-\(UUID().uuidString)"
        clock = TestClock(now)
        store = MemoryDayStore(latest: stored.map { StoredDay(key: "stored", snapshot: $0) })
        notifier = SpyNotifier()
        ticker = ManualTicker()
        settings = AppSettings(defaults: UserDefaults(suiteName: suite)!)
        if let session { settings.session = session }
        controller = SessionController(
            clock: clock, store: store, notifier: notifier, ticker: ticker, settings: settings, calendar: calendar
        )
    }

    func cleanUp() { UserDefaults().removePersistentDomain(forName: suite) }

    /// Starts the standard day (four hours of focus, 50/10) at the harness clock.
    func startStandardDay() async { await controller.startDay(request: standardRequest(at: clock.now)) }
}

extension SessionController {
    /// Starts the standard day at `now`, for tests that build controllers by hand.
    func startStandardDay(at now: Date) async { await startDay(request: standardRequest(at: now)) }
}

/// A snapshot of a finished day.
func finishedSnapshot(plan: [PlannedSegment] = fivePlan()) throws -> SessionSnapshot {
    var engine = SessionEngine(clock: TestClock(plan[0].start.addingTimeInterval(600)))
    try engine.startDay(plan: plan, settings: SessionSettings())
    try engine.start()
    try engine.endDay()
    return engine.snapshot
}
