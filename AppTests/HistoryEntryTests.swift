import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct HistoryEntryTests {
    private func entry(_ snapshot: SessionSnapshot, key: String = "2026-01-15") -> HistoryEntry {
        HistoryEntry(day: StoredDay(key: key, snapshot: snapshot))
    }

    @Test func aFinishedDayWithAnUntrackedPause() throws {
        let snapshot = try playedDay(settings: SessionSettings(pausesCountAsRest: false)) { engine, clock in
            try engine.start()
            clock.set(t(9, 10)); try engine.pause()
            clock.set(t(9, 15)); try engine.resume()
            clock.set(t(9, 30)); try engine.endDay()
        }
        let e = entry(snapshot)
        #expect(e.id == "2026-01-15")
        #expect(e.startedAt == t(9) && e.endedAt == t(9, 30))
        #expect(e.isFinished)
        #expect(e.focusActual == minutes(25))
        #expect(e.focusPlanned == minutes(150))
        #expect(e.restActual == 0)
        #expect(e.lag == t(9, 30).timeIntervalSince(t(11, 50)))
    }

    @Test func theReviewScenarioFigures() throws {
        let plan = makePlan([(.work, 50), (.shortBreak, 10), (.work, 50)])
        let snapshot = try playedDay(plan: plan, settings: SessionSettings(pausesCountAsRest: false)) { engine, clock in
            try engine.start()
            clock.set(t(9, 30)); try engine.pause()
            clock.set(t(9, 35)); try engine.resume()
            clock.set(t(9, 57)); try engine.advance()
            clock.set(t(10, 9)); try engine.advance()
            clock.set(t(10, 40)); try engine.skip()
        }
        let e = entry(snapshot)
        #expect(e.focusActual == minutes(83) && e.focusPlanned == minutes(100))
        #expect(e.restActual == minutes(12))
        #expect(e.lag == minutes(-10))
    }

    @Test func aDayThatWasNeverEnded() throws {
        let e = entry(try abandonedDay())
        #expect(!e.isFinished)
        #expect(e.startedAt == t(9))
        #expect(e.endedAt == t(9, 35))
        #expect(e.lag == nil)
    }

    @Test func aDayEndedBeforeItBeganShowsNoRecordedTimes() throws {
        let e = entry(try playedDay { engine, _ in try engine.endDay() })
        #expect(e.isFinished)
        #expect(e.startedAt == t(9))                 // falls back to the plan's start
        #expect(e.endedAt == nil)
        #expect(e.lag == nil)
        #expect(e.focusActual == 0)
    }

    @Test func aDayCrossingMidnight() throws {
        let plan = fivePlan(start: d(14, 22))
        let snapshot = try playedDay(plan: plan) { engine, clock in
            try engine.start()
            clock.set(d(15, 0, 30)); try engine.endDay()
        }
        let e = entry(snapshot, key: "2026-01-14")
        #expect(e.startedAt == d(14, 22) && e.endedAt == d(15, 0, 30))
        #expect(e.isFinished)
    }
}
