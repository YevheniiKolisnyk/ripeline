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
    /// The snapshot a save last failed for, and when; it is not retried for a while.
    @ObservationIgnored private var failedSave: (snapshot: SessionSnapshot, at: Date)?
    private static let saveRetryInterval: TimeInterval = 30
    /// The notification currently arranged: what it says, when the segment ends, and its id
    /// (the segment's id, so each segment has its own request).
    @ObservationIgnored private var scheduled: (kind: SignalKind, endsAt: Date, id: String)?
    /// Whether requests an earlier run left behind may still be pending. True at launch.
    @ObservationIgnored private var mayHavePending = true
    @ObservationIgnored private var didRequestAuthorization = false

    init(
        clock: any WallClock, store: any DayStore, notifier: any Notifier, ticker: any Ticker,
        settings: AppSettings, calendar: Calendar = .autoupdatingCurrent
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

    /// The planned and actual blocks of the day as of the current time.
    var timeline: Timeline {
        _ = now
        return engine.timeline()
    }

    /// Plan versus reality, per segment and for the day, as of the current time.
    var comparison: DayComparison {
        _ = now
        return engine.comparison()
    }

    /// The id of the first segment of the day that is running, paused or in overtime; `nil` otherwise.
    /// The history leaves that day out.
    var activeDayID: UUID? {
        switch engine.state {
        case .running, .paused, .overtime: engine.snapshot.plan.first?.id
        case .idle, .finished: nil
        }
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
            discardEarlierRequests()
            return
        }
        guard let stored, !isStale(stored.snapshot) else { return }
        do {
            engine = try SessionEngine(restoring: stored.snapshot, clock: clock)
        } catch {
            logger.error("Stored day is inconsistent; setting it aside")
            try? store.quarantine(stored)
            discardEarlierRequests()
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

    /// A day the app cannot show must not leave a notification from an earlier run to fire for it.
    private func discardEarlierRequests() {
        notifier.cancelAllPending()
        mayHavePending = false
    }

    /// A day is stale when it is finished, or its plan ended before today began.
    private func isStale(_ snapshot: SessionSnapshot) -> Bool {
        guard snapshot.state != .finished, let planEnd = snapshot.plan.last?.end else { return true }
        return planEnd < calendar.startOfDay(for: clock.now)
    }

    // MARK: Actions

    /// Starts a day from `request`, at once. The plan is generated first, so a request the
    /// generator rejects never triggers the permission prompt. Does nothing, and returns `false`,
    /// when starting is not allowed now.
    ///
    /// The permission prompt is requested after the day has started and does not hold it up: it
    /// can stay unanswered for minutes, and the countdown must begin at the click.
    @discardableResult
    func startDay(request: DayPlanRequest) async -> Bool {
        guard engine.isAllowed(.startDay) else { return false }
        let plan: [PlannedSegment]
        do { plan = try PlanGenerator.generate(request) } catch {
            logger.error("Could not generate the plan: \(error.localizedDescription, privacy: .public)")
            return false
        }
        do {
            try engine.startDay(plan: plan, settings: settings.session)
            try engine.start()
        } catch {
            logger.error("Could not start the day: \(error.localizedDescription, privacy: .public)")
            didChange()
            return false
        }
        didChange()
        requestAuthorizationOnce()
        return true
    }

    /// Asks for notification permission the first time a day starts, without waiting for the answer.
    private func requestAuthorizationOnce() {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        let notifier = notifier
        Task { @MainActor in await notifier.requestAuthorization() }
    }

    /// Changes how sessions behave. Effective from the next transition: recorded time is not
    /// rewritten and an open pause keeps its kind. Also applies to the next day.
    func updateSessionSettings(_ new: SessionSettings) {
        // Settle any segment whose end has already passed with the settings that were in force then,
        // not the new ones.
        engine.tick()
        settings.session = new
        // A day that has ended (or none) keeps the settings it ran with: changing them would rewrite
        // a day that is already history, and bring back one the user deleted. They apply to the next day.
        switch engine.state {
        case .idle, .finished: break
        case .running, .paused, .overtime: engine.updateSettings(new)
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

    /// Keeps one notification arranged, for the end of the running segment.
    ///
    /// A request that is due (the segment's time ran out) is never cancelled or replaced: it is
    /// firing right now. Only a request the user made obsolete before it was due, by pausing,
    /// skipping or ending the day, is cancelled.
    private func reconcileNotifier() {
        guard case let .running(index, endsAt) = engine.state else {
            if let pending = scheduled {
                if pending.endsAt > now { notifier.cancel(id: pending.id) }
                scheduled = nil
            } else if mayHavePending {
                notifier.cancelAllPending()
            }
            mayHavePending = false
            return
        }
        let id = plan[index].id.uuidString
        guard scheduled?.id != id || scheduled?.endsAt != endsAt else { return }
        if let old = scheduled, old.id != id, old.endsAt > now { notifier.cancel(id: old.id) }
        let kind = signalKind(endOfSegment: index)
        notifier.schedule(kind, in: endsAt.timeIntervalSince(now), id: id)
        scheduled = (kind, endsAt, id)
        mayHavePending = false
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

    /// Saves the snapshot if it differs from the last one saved. A save that fails is retried
    /// only after a while, not on every tick, and logged once per attempt; a new change is
    /// always tried at once.
    private func persistIfChanged() {
        let snapshot = engine.snapshot
        guard !snapshot.plan.isEmpty, snapshot != lastSaved else { return }
        if let failed = failedSave, failed.snapshot == snapshot,
           now.timeIntervalSince(failed.at) < Self.saveRetryInterval { return }
        do {
            try store.save(snapshot)
            lastSaved = snapshot
            failedSave = nil
        } catch {
            failedSave = (snapshot, now)
            logger.error("Could not save the day: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension SessionController: DayOverviewSource {
    var hasDay: Bool { !plan.isEmpty }
    var overviewPhase: Phase { phase }
    var overviewTimeline: Timeline { timeline }
    var overviewComparison: DayComparison { comparison }
    var overviewStatus: ScheduleStatus? { scheduleStatus }
    var overviewNow: Date {
        _ = now
        return clock.now
    }
}
