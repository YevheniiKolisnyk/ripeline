import Foundation
import Testing
@testable import RipelineCore

struct SessionTransitionTests {
    // MARK: transitions that are allowed

    @Test func startDayLoadsPlanAndStaysIdle() throws {
        let plan = shortPlan()
        let (engine, _) = try makeEngine(plan: plan)
        #expect(engine.state == .idle)
        #expect(engine.snapshot.plan == plan)
        #expect(engine.snapshot.actuals.count == 3)
        #expect(engine.snapshot.actuals.allSatisfy { $0.status == .notStarted && $0.intervals.isEmpty })
        #expect(engine.snapshot.openInterval == nil)
    }

    @Test func startDayRejectsEmptyPlan() {
        var engine = SessionEngine(clock: ManualClock(t(9)))
        #expect(throws: SessionError.emptyPlan) {
            try engine.startDay(plan: [], settings: SessionSettings())
        }
    }

    @Test func startRunsFirstSegmentUntilItsPlannedEnd() throws {
        var (engine, _) = try makeEngine()
        try engine.start()
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 50)))
        #expect(engine.snapshot.actuals[0].status == .active)
        #expect(engine.snapshot.actuals[1].status == .notStarted)
        #expect(engine.snapshot.openInterval == OpenInterval(kind: .work, start: t(9)))
    }

    @Test func startUsesPlannedDurationEvenWhenStartedLate() throws {
        var (engine, clock) = try makeEngine()
        clock.set(t(9, 15))
        try engine.start()
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(10, 5)))
    }

    @Test func pauseFreezesRemainingTime() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 20))
        try engine.pause()
        #expect(engine.state == .paused(segmentIndex: 0, remaining: minutes(30)))
        #expect(engine.remainingTime() == minutes(30))
        clock.set(t(9, 45))
        #expect(engine.remainingTime() == minutes(30))
    }

    @Test func resumeRestartsCountdownFromRemainingTime() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 20))
        try engine.pause()
        clock.set(t(9, 25))
        try engine.resume()
        #expect(engine.state == .running(segmentIndex: 0, endsAt: t(9, 55)))
        #expect(engine.remainingTime() == minutes(30))
    }

    @Test func endDayFromIdleFinishesWithoutTouchingSegments() throws {
        var (engine, _) = try makeEngine()
        try engine.endDay()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals.allSatisfy { $0.status == .notStarted && $0.intervals.isEmpty })
    }

    @Test func endDayWhileRunningSkipsCurrentSegmentAndKeepsItsTime() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 20))
        try engine.endDay()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals[0].status == .skipped)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 20))])
        #expect(engine.snapshot.openInterval == nil)
    }

    @Test func endDayWhilePausedSkipsCurrentSegmentAndKeepsPause() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 20))
        try engine.pause()
        clock.set(t(9, 25))
        try engine.endDay()
        #expect(engine.state == .finished)
        #expect(engine.snapshot.actuals[0].status == .skipped)
        #expect(recorded(engine.snapshot.actuals[0]) == [workedFor(t(9), t(9, 20)), rested(t(9, 20), t(9, 25))])
    }

    @Test func startDayAfterFinishBeginsAFreshDay() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 10))
        try engine.endDay()
        let newPlan = makePlan(start: t(13), [(.work, 25)])
        try engine.startDay(plan: newPlan, settings: SessionSettings(autoAdvanceWorkToBreak: true))
        #expect(engine.state == .idle)
        #expect(engine.snapshot.plan == newPlan)
        #expect(engine.snapshot.actuals.count == 1)
        #expect(engine.snapshot.actuals[0].intervals.isEmpty)
        #expect(engine.snapshot.settings.autoAdvanceWorkToBreak)
    }

    @Test func startDayWhileIdleReplacesThePlan() throws {
        var (engine, _) = try makeEngine()
        let newPlan = makePlan(start: t(13), [(.work, 25)])
        try engine.startDay(plan: newPlan, settings: SessionSettings())
        #expect(engine.snapshot.plan == newPlan)
    }

    // MARK: the full transition table

    enum Setup: CaseIterable, CustomTestStringConvertible {
        case emptyIdle, idle, running, paused, overtime, finished

        var testDescription: String { "\(self)" }

        func engine() throws -> SessionEngine {
            let clock = ManualClock(t(9))
            var engine = SessionEngine(clock: clock)
            guard self != .emptyIdle else { return engine }
            try engine.startDay(plan: shortPlan(), settings: SessionSettings())
            switch self {
            case .emptyIdle, .idle: break
            case .running: try engine.start()
            case .paused: try engine.start(); clock.set(t(9, 10)); try engine.pause()
            case .overtime: try engine.start(); clock.set(t(9, 55)); engine.tick()
            case .finished: try engine.endDay()
            }
            return engine
        }

        /// Actions allowed in this setup.
        var allowed: Set<SessionAction> {
            switch self {
            case .emptyIdle: [.startDay]
            case .idle: [.startDay, .start, .endDay]
            case .running: [.pause, .extend, .skip, .endDay]
            case .paused: [.resume, .extend, .skip, .endDay]
            case .overtime: [.extend, .skip, .advance, .endDay]
            case .finished: [.startDay]
            }
        }
    }

    static let coveredActions = SessionAction.allCases

    static func apply(_ action: SessionAction, to engine: inout SessionEngine) throws(SessionError) {
        switch action {
        case .startDay: try engine.startDay(plan: makePlan(start: t(9), [(.work, 25)]), settings: SessionSettings())
        case .start: try engine.start()
        case .pause: try engine.pause()
        case .resume: try engine.resume()
        case .extend: try engine.extend(minutes: 5)
        case .skip: try engine.skip()
        case .advance: try engine.advance()
        case .endDay: try engine.endDay()
        case .append: try engine.appendSegments(makePlan(start: t(10, 50), [(.shortBreak, 5)]))
        }
    }

    @Test(arguments: Setup.allCases)
    func isAllowedMatchesTheTransitionTable(setup: Setup) throws {
        let engine = try setup.engine()
        for action in Self.coveredActions {
            #expect(engine.isAllowed(action) == setup.allowed.contains(action), "\(setup) / \(action)")
        }
    }

    @Test(arguments: Setup.allCases)
    func disallowedActionsThrowAndLeaveTheEngineUntouched(setup: Setup) throws {
        for action in Self.coveredActions where !setup.allowed.contains(action) {
            var engine = try setup.engine()
            let before = engine.snapshot
            #expect(throws: SessionError.notAllowed(action), "\(setup) / \(action)") {
                try Self.apply(action, to: &engine)
            }
            #expect(engine.snapshot == before, "\(setup) / \(action)")
        }
    }

    // MARK: plan validation

    private func segment(_ index: Int, _ start: Date, _ end: Date) -> PlannedSegment {
        PlannedSegment(index: index, kind: .work, start: start, end: end)
    }

    @Test(arguments: [
        ("segment ends before it starts", [PlannedSegment(index: 0, kind: .work, start: t(9, 30), end: t(9))]),
        ("zero-length segment", [PlannedSegment(index: 0, kind: .work, start: t(9), end: t(9))]),
        ("index does not match position", [PlannedSegment(index: 5, kind: .work, start: t(9), end: t(9, 50))]),
        ("gap between segments", [
            PlannedSegment(index: 0, kind: .work, start: t(9), end: t(9, 50)),
            PlannedSegment(index: 1, kind: .shortBreak, start: t(9, 55), end: t(10)),
        ]),
        ("overlapping segments", [
            PlannedSegment(index: 0, kind: .work, start: t(9), end: t(9, 50)),
            PlannedSegment(index: 1, kind: .shortBreak, start: t(9, 45), end: t(10)),
        ]),
    ])
    func startDayRejectsMalformedPlans(_ label: String, plan: [PlannedSegment]) throws {
        var (engine, _) = try makeEngine()
        let before = engine.snapshot
        #expect(throws: SessionError.invalidPlan, Comment(rawValue: label)) {
            try engine.startDay(plan: plan, settings: SessionSettings())
        }
        #expect(engine.snapshot == before)
    }
}
