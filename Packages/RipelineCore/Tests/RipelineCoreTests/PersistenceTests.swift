import Foundation
import Testing
@testable import RipelineCore

struct PersistenceTests {
    /// Work 50, break 10, work 50, break 10, work 50: 09:00–11:50.
    private let plan = makePlan([(.work, 50), (.shortBreak, 10), (.work, 50), (.shortBreak, 10), (.work, 50)])

    private func roundTrip(_ snapshot: SessionSnapshot) throws -> SessionSnapshot {
        let data = try JSONEncoder().encode(snapshot)
        return try JSONDecoder().decode(SessionSnapshot.self, from: data)
    }

    private func started(
        settings: SessionSettings = SessionSettings()
    ) throws -> (engine: SessionEngine, clock: ManualClock) {
        var (engine, clock) = try makeEngine(plan: plan, settings: settings)
        try engine.start()
        return (engine, clock)
    }

    // MARK: round trips

    @Test func snapshotsRoundTripInEveryState() throws {
        var snapshots: [SessionSnapshot] = [SessionSnapshot.empty]

        let (idle, _) = try makeEngine(plan: plan)
        snapshots.append(idle.snapshot)

        var (running, runningClock) = try started()
        runningClock.set(t(9, 20))
        snapshots.append(running.snapshot)

        try running.pause()
        snapshots.append(running.snapshot)

        runningClock.set(t(9, 25)); try running.resume()
        runningClock.set(t(10, 0)); running.tick()
        snapshots.append(running.snapshot)            // overtime

        try running.endDay()
        snapshots.append(running.snapshot)            // finished

        for snapshot in snapshots {
            #expect(try roundTrip(snapshot) == snapshot, "\(snapshot.state)")
        }
        #expect(Set(snapshots.map { "\($0.state)".prefix(4) }).count >= 5)
    }

    @Test func restoredEngineBehavesLikeOneThatNeverStopped() throws {
        var (original, clock) = try started()
        clock.set(t(9, 20)); try original.pause()

        var restored = try SessionEngine(restoring: roundTrip(original.snapshot), clock: clock)
        clock.set(t(9, 30))
        try original.resume()
        try restored.resume()
        clock.set(t(9, 40))
        #expect(restored.snapshot == original.snapshot)
        #expect(restored.remainingTime() == original.remainingTime())
    }

    // MARK: restore after a long gap

    @Test func restoringRunningSnapshotHoursLaterEndsInOvertime() throws {
        let (engine, _) = try started()
        let saved = try roundTrip(engine.snapshot)
        var restored = try SessionEngine(restoring: saved, clock: ManualClock(t(13)))
        restored.tick()
        #expect(restored.state == .overtime(segmentIndex: 0, since: t(9, 50)))
        #expect(restored.overtimeElapsed() == minutes(190))
    }

    @Test func restoringRunningSnapshotHoursLaterWithAutoAdvanceWalksTheSegments() throws {
        let (engine, _) = try started(settings: SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true))
        let saved = try roundTrip(engine.snapshot)
        var restored = try SessionEngine(restoring: saved, clock: ManualClock(t(11, 15)))
        restored.tick()
        #expect(restored.state == .running(segmentIndex: 4, endsAt: t(11, 50)))
        #expect(recorded(restored.snapshot.actuals[1]) == [rested(t(9, 50), t(10, 0))])
    }

    // MARK: validation

    @Test func rejectsActualsThatDoNotMatchThePlan() throws {
        var snapshot = try makeEngine(plan: plan).engine.snapshot
        snapshot.actuals.removeLast()
        #expect(throws: SessionError.invalidSnapshot) {
            try SessionEngine(restoring: snapshot, clock: ManualClock(t(9)))
        }
    }

    @Test func rejectsStateIndexOutsideThePlan() throws {
        var snapshot = try started().engine.snapshot
        snapshot.state = .running(segmentIndex: 9, endsAt: t(9, 50))
        #expect(throws: SessionError.invalidSnapshot) {
            try SessionEngine(restoring: snapshot, clock: ManualClock(t(9)))
        }
    }

    @Test func rejectsRunningSnapshotWithoutAnOpenInterval() throws {
        var snapshot = try started().engine.snapshot
        snapshot.openInterval = nil
        #expect(throws: SessionError.invalidSnapshot) {
            try SessionEngine(restoring: snapshot, clock: ManualClock(t(9)))
        }
    }

    @Test func rejectsIdleSnapshotWithAnOpenInterval() throws {
        var snapshot = try makeEngine(plan: plan).engine.snapshot
        snapshot.openInterval = OpenInterval(kind: .work, start: t(9))
        #expect(throws: SessionError.invalidSnapshot) {
            try SessionEngine(restoring: snapshot, clock: ManualClock(t(9)))
        }
    }

    @Test func acceptsEveryValidSnapshot() throws {
        let (idle, _) = try makeEngine(plan: plan)
        _ = try SessionEngine(restoring: SessionSnapshot.empty, clock: ManualClock(t(9)))
        _ = try SessionEngine(restoring: idle.snapshot, clock: ManualClock(t(9)))
        var (running, clock) = try started()
        _ = try SessionEngine(restoring: running.snapshot, clock: clock)
        clock.set(t(9, 10)); try running.pause()
        _ = try SessionEngine(restoring: running.snapshot, clock: clock)
        clock.set(t(9, 20)); try running.endDay()
        _ = try SessionEngine(restoring: running.snapshot, clock: clock)
    }
}
