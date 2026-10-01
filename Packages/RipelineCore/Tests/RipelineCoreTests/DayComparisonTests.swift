import Foundation
import Testing
@testable import RipelineCore

struct DayComparisonTests {
    /// Work 50, break 10, work 50 (planned 09:00–10:50), pauses untracked, no auto-advance:
    /// start 09:00; pause 09:30–09:35; work overtime until 09:57; break 09:57–10:07 with
    /// overtime until 10:09; work from 10:09, skipped at 10:40.
    private func scriptedDay() throws -> SessionEngine {
        var (engine, clock) = try makeEngine(settings: SessionSettings(pausesCountAsRest: false))
        try engine.start()
        clock.set(t(9, 30)); try engine.pause()
        clock.set(t(9, 35)); try engine.resume()
        clock.set(t(9, 57)); try engine.advance()
        clock.set(t(10, 9)); try engine.advance()
        clock.set(t(10, 40)); try engine.skip()
        return engine
    }

    @Test func perSegmentFigures() throws {
        let comparison = try scriptedDay().comparison()
        let rows = comparison.rows
        #expect(rows.count == 3)

        #expect(rows[0].status == .completed)
        #expect(rows[0].planned == minutes(50))
        #expect(rows[0].work == minutes(52))
        #expect(rows[0].rest == 0)
        #expect(rows[0].untracked == minutes(5))
        #expect(rows[0].delta == minutes(7))

        #expect(rows[1].status == .completed)
        #expect(rows[1].planned == minutes(10))
        #expect(rows[1].rest == minutes(12))
        #expect(rows[1].delta == minutes(2))

        #expect(rows[2].status == .skipped)
        #expect(rows[2].work == minutes(31))
        #expect(rows[2].delta == minutes(-19))
    }

    @Test func totals() throws {
        let totals = try scriptedDay().comparison().totals
        #expect(totals.focusPlanned == minutes(100))
        #expect(totals.focusActual == minutes(83))
        #expect(totals.restPlanned == minutes(10))
        #expect(totals.restActual == minutes(12))
        #expect(totals.untracked == minutes(5))
        #expect(totals.plannedEnd == t(10, 50))
        #expect(totals.actualEnd == t(10, 40))
    }

    @Test func dayInProgressCountsTheOpenIntervalAndHasNoActualEnd() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 20))
        let comparison = engine.comparison()
        #expect(comparison.rows[0].work == minutes(20))
        #expect(comparison.rows[1].work == 0)
        #expect(comparison.totals.focusActual == minutes(20))
        #expect(comparison.totals.actualEnd == nil)
    }

    @Test func overtimeIsCountedEvenBeforeTheEngineIsTicked() throws {
        var (engine, clock) = try makeEngine()
        try engine.start()
        clock.set(t(9, 55))
        #expect(engine.comparison().rows[0].work == minutes(55))
    }

    @Test func unstartedDayHasZeroActuals() throws {
        let (engine, _) = try makeEngine()
        let comparison = engine.comparison()
        #expect(comparison.rows.map(\.status) == [.notStarted, .notStarted, .notStarted])
        #expect(comparison.totals.focusActual == 0)
        #expect(comparison.totals.focusPlanned == minutes(100))
        #expect(comparison.rows[0].delta == minutes(-50))
    }

    @Test func emptySnapshotHasNothingToCompare() {
        let comparison = SessionEngine(clock: ManualClock(t(9))).comparison()
        #expect(comparison.rows.isEmpty)
        #expect(comparison.totals.focusPlanned == 0)
        #expect(comparison.totals.focusActual == 0)
        #expect(comparison.totals.restPlanned == 0)
        #expect(comparison.totals.restActual == 0)
        #expect(comparison.totals.untracked == 0)
        #expect(comparison.totals.plannedEnd == nil)
        #expect(comparison.totals.actualEnd == nil)
    }
}
