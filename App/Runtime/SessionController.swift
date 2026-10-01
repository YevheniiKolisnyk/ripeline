import Foundation
import Observation
import os
import RipelineCore

/// Hosts a `SessionEngine` for the interface: it restores the day at launch, carries out the
/// user's actions, and keeps the stored copy up to date.
///
/// All time comes from the injected clock through the engine, so what is shown is correct
/// whenever it is read, however late the last tick was.
@MainActor @Observable
final class SessionController {
    /// The temporary plan behind "Start day", until the setup screen exists (stage 2b).
    static let quickStartPreset = Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45)
    static let quickStartFocusMinutes = 240

    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let store: any DayStore
    @ObservationIgnored private let notifier: any Notifier
    @ObservationIgnored private let ticker: any Ticker
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "session")

    private var engine: SessionEngine
    /// The time of the last update. Views that read it redraw when it changes.
    private(set) var now: Date

    @ObservationIgnored private var lastSaved: SessionSnapshot?
    /// The notification currently arranged: what it says and when the segment ends.
    @ObservationIgnored private var scheduled: (kind: SignalKind, endsAt: Date)?
    /// Whether a notification request may be pending. True at launch: an earlier run may have left one.
    @ObservationIgnored private var mayHavePending = true
    @ObservationIgnored private var didRequestAuthorization = false

    init(
        clock: any WallClock, store: any DayStore, notifier: any Notifier, ticker: any Ticker,
        settings: AppSettings, calendar: Calendar = .current
    ) {
        self.clock = clock
        self.store = store
        self.notifier = notifier
        self.ticker = ticker
        self.settings = settings
        self.calendar = calendar
        engine = SessionEngine(clock: clock)
        now = clock.now
    }

    // MARK: What the interface shows

    /// The fixed plan of the current day; empty when no day is loaded.
    var plan: [PlannedSegment] { engine.snapshot.plan }

    /// The segment that is running, paused or in overtime.
    var currentSegment: PlannedSegment? {
        switch engine.state {
        case let .running(index, _), let .paused(index, _), let .overtime(index, _): plan[index]
        case .idle, .finished: nil
        }
    }

    var phase: Phase {
        let onBreak = currentSegment.map { $0.kind != .work } ?? false
        switch engine.state {
        case .idle: return .idle
        case .finished: return .finished
        case .running: return onBreak ? .onBreak : .working
        case .paused: return .paused(onBreak: onBreak)
        case .overtime: return .overtime(onBreak: onBreak)
        }
    }

    /// Seconds left in the current segment; zero in overtime; `nil` when none is counting down.
    var remaining: TimeInterval? {
        _ = now
        return engine.remainingTime()
    }

    /// Seconds past the planned end of the current segment; `nil` outside overtime.
    var overtimeElapsed: TimeInterval? {
        _ = now
        return engine.overtimeElapsed()
    }

    /// How far through the current segment, from 0 to 1; `nil` without a segment.
    var progress: Double? {
        _ = now
        guard let segment = currentSegment, let remaining else { return nil }
        return min(1, max(0, 1 - remaining / segment.duration))
    }

    var scheduleStatus: ScheduleStatus? {
        _ = now
        return engine.scheduleStatus()
    }

    func isAllowed(_ action: SessionAction) -> Bool { engine.isAllowed(action) }

    // MARK: Launch

    /// Loads the most recent day. Call once at launch.
    func restore() {
        let stored: StoredDay?
        do {
            stored = try store.loadLatest()
        } catch {
            logger.error("Could not load the stored day: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let stored, !isStale(stored.snapshot) else { return }
        do {
            engine = try SessionEngine(restoring: stored.snapshot, clock: clock)
        } catch {
            logger.error("Stored day is inconsistent; setting it aside")
            try? store.quarantine(stored)
            return
        }
        lastSaved = stored.snapshot
        engine.tick()
        if engine.snapshot != stored.snapshot, let ended = lastEndedSegmentSignal() {
            // Segments ended while the app was closed: tell the user once, about the latest one.
            notifier.deliverNow(ended)
        }
        didChange()
    }

    /// Brings the day up to the current time. Called by the ticker, on wake and when the clock changes.
    func refresh() {
        engine.tick()
        didChange()
    }

    /// A day is stale when it is finished, or its plan ended before today began.
    private func isStale(_ snapshot: SessionSnapshot) -> Bool {
        guard snapshot.state != .finished, let planEnd = snapshot.plan.last?.end else { return true }
        return planEnd < calendar.startOfDay(for: clock.now)
    }

    // MARK: Actions

    /// Starts a day with the default plan: net focus of four hours, 50/10 minutes.
    func startQuickDay() async {
        guard engine.isAllowed(.startDay) else { return }
        if !didRequestAuthorization {
            didRequestAuthorization = true
            await notifier.requestAuthorization()
        }
        guard engine.isAllowed(.startDay) else { return }
        let request = DayPlanRequest(
            mode: .netFocus(start: clock.now, focusMinutes: Self.quickStartFocusMinutes),
            longBreak: .none, remainderStrategy: .leaveFree, preset: Self.quickStartPreset
        )
        do {
            let plan = try PlanGenerator.generate(request)
            try engine.startDay(plan: plan, settings: settings.session)
            try engine.start()
        } catch {
            logger.error("Could not start the day: \(error.localizedDescription, privacy: .public)")
        }
        didChange()
    }

    func start() { act(.start) { try $0.start() } }
    func pause() { act(.pause) { try $0.pause() } }
    func resume() { act(.resume) { try $0.resume() } }
    func extend(minutes: Int) { act(.extend) { try $0.extend(minutes: minutes) } }
    func skip() { act(.skip) { try $0.skip() } }
    func advance() { act(.advance) { try $0.advance() } }
    func endDay() { act(.endDay) { try $0.endDay() } }

    /// Runs `body` on the engine if the action is allowed. The interface only offers allowed
    /// actions, so a refusal means a stale click: it is logged, not shown.
    private func act(_ action: SessionAction, _ body: (inout SessionEngine) throws -> Void) {
        guard engine.isAllowed(action) else {
            logger.notice("Ignored \(action.rawValue, privacy: .public): not allowed now")
            return
        }
        do { try body(&engine) } catch {
            logger.error("\(action.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        didChange()
    }

    // MARK: Bookkeeping

    private func didChange() {
        now = clock.now
        persistIfChanged()
        reconcileNotifier()
        reconcileTicker()
    }

    /// What a notification about the end of segment `index` should say.
    private func signalKind(endOfSegment index: Int) -> SignalKind {
        if index == plan.count - 1 { return .dayFinished }
        return plan[index].kind == .work ? .workEnded : .breakEnded
    }

    /// The signal for the segment that ended most recently, judging by the current state.
    private func lastEndedSegmentSignal() -> SignalKind? {
        switch engine.state {
        case .finished: .dayFinished
        case let .overtime(index, _): signalKind(endOfSegment: index)
        case let .running(index, _): index > 0 ? signalKind(endOfSegment: index - 1) : nil
        case .idle, .paused: nil
        }
    }

    /// Keeps exactly one notification arranged, for the end of the running segment, and none otherwise.
    private func reconcileNotifier() {
        guard case let .running(index, endsAt) = engine.state else {
            if mayHavePending {
                notifier.cancelPending()
                mayHavePending = false
            }
            scheduled = nil
            return
        }
        let kind = signalKind(endOfSegment: index)
        guard scheduled?.kind != kind || scheduled?.endsAt != endsAt else { return }
        notifier.schedule(kind, in: endsAt.timeIntervalSince(now))
        scheduled = (kind, endsAt)
        mayHavePending = true
    }

    /// The ticker runs only while there is something to count: a running segment or overtime.
    private func reconcileTicker() {
        switch engine.state {
        case .running, .overtime:
            ticker.start { [weak self] in self?.refresh() }
        case .idle, .paused, .finished:
            ticker.stop()
        }
    }

    /// Saves the snapshot if it differs from the last one saved. A failed save is retried on the next change.
    private func persistIfChanged() {
        let snapshot = engine.snapshot
        guard !snapshot.plan.isEmpty, snapshot != lastSaved else { return }
        do {
            try store.save(snapshot)
            lastSaved = snapshot
        } catch {
            logger.error("Could not save the day: \(error.localizedDescription, privacy: .public)")
        }
    }
}
