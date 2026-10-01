import Foundation
import RipelineCore
@testable import Ripeline

/// A `DayOverviewSource` over a real `SessionEngine` and a manual clock, so tests play out real days.
@MainActor
final class EngineSource: DayOverviewSource {
    private(set) var engine: SessionEngine
    let clock: TestClock
    /// Replaces the engine's schedule status, to test thresholds.
    var statusOverride: ScheduleStatus??

    init(plan: [PlannedSegment]? = nil, settings: SessionSettings = SessionSettings(), kind: SessionKind = .day, at now: Date = t(9)) throws {
        clock = TestClock(now)
        engine = SessionEngine(clock: clock)
        if let plan { try engine.startDay(plan: plan, settings: settings, kind: kind) }
    }

    /// Moves the clock to `date`, then runs `action` on the engine.
    func at(_ date: Date, _ action: (inout SessionEngine) throws -> Void = { _ in }) throws {
        clock.set(date)
        try action(&engine)
    }

    // MARK: DayOverviewSource

    var hasDay: Bool { !engine.snapshot.plan.isEmpty }

    var overviewPhase: Phase {
        let plan = engine.snapshot.plan
        func onBreak(_ index: Int) -> Bool { plan[index].kind != .work }
        switch engine.state {
        case .idle: return .idle
        case .finished: return .finished
        case let .running(index, _): return onBreak(index) ? .onBreak : .working
        case let .paused(index, _): return .paused(onBreak: onBreak(index))
        case let .overtime(index, _): return .overtime(onBreak: onBreak(index))
        }
    }

    var overviewTimeline: Timeline { engine.timeline() }
    var overviewComparison: DayComparison { engine.comparison() }
    var overviewStatus: ScheduleStatus? {
        if let override = statusOverride { return override }
        return engine.scheduleStatus()
    }
    var overviewNow: Date { clock.now }
    var overviewIsQuick: Bool { engine.snapshot.kind == .quick }
    var overviewTomatoes: [Tomato] { engine.tomatoes() }
}
