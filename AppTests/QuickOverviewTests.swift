import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct QuickOverviewTests {
    private func quickSource(kind: SessionKind = .quick) throws -> EngineSource {
        // A 25-minute block with a break and a second block added, as a quick session grows.
        var plan = QuickSession.plan(length: .short, start: t(9))
        plan += QuickSession.nextBlocks(after: plan)
        return try EngineSource(plan: plan, kind: kind)
    }

    private func model(_ source: EngineSource) -> DayOverviewModel { DayOverviewModel(source: source, calendar: utc) }

    // MARK: Review Focus 4: no plan-only figures

    @Test func aQuickSessionShowsNoLagPlannedEndOrProjection() throws {
        let source = try quickSource()
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 40))                                    // well past the first block: a day would be behind
        let m = model(source)
        #expect(m.isQuick)
        #expect(m.lag == nil)
        #expect(m.summary?.plannedEnd == nil)
        #expect(m.summary?.endsAt == nil)
        #expect(m.mode == .running)
    }

    @Test func thePlannedFiguresStayForAQuickSession() throws {
        let source = try quickSource()
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 20))
        let summary = try #require(model(source).summary)
        #expect(summary.focusPlanned == minutes(50))               // the two blocks chosen so far
        #expect(summary.restPlanned == minutes(5))
        #expect(summary.focusActual == minutes(20))
    }

    @Test func aFinishedQuickSessionKeepsItsFinalEnd() throws {
        let source = try quickSource()
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 40)) { try $0.endDay() }
        let m = model(source)
        #expect(m.mode == .finished && m.isQuick)
        #expect(m.summary?.endsAt == t(9, 40))
        #expect(m.summary?.endKind == .final)
        #expect(m.lag == nil)
    }

    @Test func anOrdinaryDayStillShowsEverything() throws {
        let source = try quickSource(kind: .day)
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 40))
        let m = model(source)
        #expect(!m.isQuick)
        #expect(m.lag != nil)
        #expect(m.summary?.plannedEnd != nil)
        #expect(m.summary?.endsAt != nil)
    }

    @Test func noDayIsNotQuick() throws {
        #expect(!model(try EngineSource()).isQuick)
    }

    // MARK: stored sessions and the history

    private func storedQuick() throws -> SessionSnapshot {
        var plan = QuickSession.plan(length: .short, start: t(9))
        plan += QuickSession.nextBlocks(after: plan)
        return try playedDay(plan: plan, kind: .quick) { engine, clock in
            try engine.start()
            clock.set(t(9, 40)); try engine.endDay()
        }
    }

    @Test func aStoredQuickSessionIsDrawnWithoutPlanOnlyFigures() throws {
        let m = DayOverviewModel(source: SnapshotSource(snapshot: try storedQuick()), calendar: utc)
        #expect(m.isQuick)
        #expect(m.summary?.plannedEnd == nil)
        #expect(m.lag == nil)
    }

    @Test func aHistoryEntryKnowsItIsQuickAndHasNoLag() throws {
        let quick = HistoryEntry(day: StoredDay(key: "2026-01-15", snapshot: try storedQuick()))
        #expect(quick.isQuick)
        #expect(quick.isFinished)
        #expect(quick.lag == nil)
        let day = HistoryEntry(day: StoredDay(key: "2026-01-15", snapshot: try finishedDay()))
        #expect(!day.isQuick)
        #expect(day.lag != nil)
    }

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func theSpokenLabelOfAQuickSessionEndsWithItsKind() throws {
        let entry = HistoryEntry(day: StoredDay(key: "2026-01-15", snapshot: try storedQuick()))
        let zone = TimeZone(secondsFromGMT: 0)!
        let english = HistoryText.accessibilityLabel(entry, locale: Locale(identifier: "en_GB"), timeZone: zone, bundle: try bundle("en"))
        #expect(english.hasSuffix(", quick session"))
        #expect(!english.contains("against plan"))
        let ukrainian = HistoryText.accessibilityLabel(entry, locale: Locale(identifier: "uk"), timeZone: zone, bundle: try bundle("uk"))
        #expect(ukrainian.hasSuffix(", швидка сесія"))
    }

    @Test func theQuickTextsExistInBothLanguages() throws {
        for language in ["en", "uk"] {
            let b = try bundle(language)
            for key in ["history.quick", "a11y.historyQuick", "ui.done"] {
                let text = b.localizedString(forKey: key, value: nil, table: nil)
                #expect(text != key && !text.isEmpty, "\(language) / \(key)")
            }
        }
        #expect(try bundle("en").localizedString(forKey: "ui.done", value: nil, table: nil) == "Done")
        #expect(try bundle("uk").localizedString(forKey: "history.quick", value: nil, table: nil) == "Швидка")
    }
}
