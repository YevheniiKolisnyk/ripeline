import Foundation
import RipelineCore
import Testing
@testable import Ripeline

struct OverviewTextTests {
    private let en = Locale(identifier: "en_GB")
    private let uk = Locale(identifier: "uk")
    private let utcZone = TimeZone(secondsFromGMT: 0)!

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    // MARK: lag

    @Test func lagInEnglish() throws {
        let b = try bundle("en")
        #expect(OverviewText.lag(.onSchedule, locale: en, bundle: b) == "On schedule")
        #expect(OverviewText.lag(.behind(180), locale: en, bundle: b) == "3 min behind schedule")
        #expect(OverviewText.lag(.ahead(7200), locale: en, bundle: b) == "2 hrs ahead of schedule")
    }

    @Test func lagInUkrainian() throws {
        let b = try bundle("uk")
        #expect(OverviewText.lag(.onSchedule, locale: uk, bundle: b) == "Вчасно")
        #expect(OverviewText.lag(.behind(180), locale: uk, bundle: b) == "Відстаєш на 3 хв")
        #expect(OverviewText.lag(.ahead(300), locale: uk, bundle: b) == "Випереджаєш на 5 хв")
    }

    // MARK: delta and status

    @Test(arguments: [(120.0, "+2 min"), (-1140.0, "\u{2212}19 min"), (0.0, "0 min"), (59.0, "0 min"), (-59.0, "0 min"), (3600.0, "+1 hr")])
    func deltaInEnglish(seconds: Double, expected: String) {
        #expect(OverviewText.delta(seconds, locale: Locale(identifier: "en")) == expected)
    }

    @Test func deltaInUkrainian() {
        #expect(OverviewText.delta(120, locale: uk) == "+2 хв")
        #expect(OverviewText.delta(-1140, locale: uk) == "\u{2212}19 хв")
    }

    @Test(arguments: ["en", "uk"])
    func everyStatusHasItsOwnText(language: String) throws {
        let b = try bundle(language)
        let statuses: [SegmentStatus] = [.notStarted, .active, .completed, .skipped]
        let texts = statuses.map { OverviewText.status($0, bundle: b) }
        #expect(Set(texts).count == statuses.count)
        #expect(texts.allSatisfy { !$0.isEmpty && !$0.hasPrefix("status.") })
    }

    @Test func statusesDifferBetweenLanguages() throws {
        let english = try bundle("en"), ukrainian = try bundle("uk")
        for status in [SegmentStatus.notStarted, .active, .completed, .skipped] {
            #expect(OverviewText.status(status, bundle: english) != OverviewText.status(status, bundle: ukrainian))
        }
    }

    // MARK: block labels and tooltips

    private func planned(_ kind: SegmentKind, _ start: Date, _ end: Date) -> BlockLayout<SegmentKind> {
        BlockLayout(kind: kind, start: start, end: end, x: 0, width: 0)
    }

    private func actual(_ kind: ActualKind, _ start: Date, _ end: Date) -> BlockLayout<ActualKind> {
        BlockLayout(kind: kind, start: start, end: end, x: 0, width: 0)
    }

    @Test func plannedBlockLabels() throws {
        let english = try bundle("en"), ukrainian = try bundle("uk")
        #expect(OverviewText.plannedBlockLabel(planned(.work, t(9), t(9, 50)), locale: en, timeZone: utcZone, bundle: english) == "Plan: Work, from 9:00 to 9:50")
        #expect(OverviewText.plannedBlockLabel(planned(.shortBreak, t(9, 50), t(10)), locale: en, timeZone: utcZone, bundle: english) == "Plan: Short break, from 9:50 to 10:00")
        #expect(OverviewText.plannedBlockLabel(planned(.longBreak, t(12, 50), t(13, 35)), locale: uk, timeZone: utcZone, bundle: ukrainian) == "План: Довга перерва, з 12:50 до 13:35")
    }

    @Test func actualBlockLabels() throws {
        let english = try bundle("en"), ukrainian = try bundle("uk")
        #expect(OverviewText.actualBlockLabel(actual(.work, t(9), t(9, 52)), locale: en, timeZone: utcZone, bundle: english) == "Actual: Work, from 9:00 to 9:52")
        #expect(OverviewText.actualBlockLabel(actual(.rest, t(9, 52), t(10, 4)), locale: en, timeZone: utcZone, bundle: english) == "Actual: Rest, from 9:52 to 10:04")
        #expect(OverviewText.actualBlockLabel(actual(.untracked, t(9, 30), t(9, 35)), locale: en, timeZone: utcZone, bundle: english) == "Actual: Paused (not counted), from 9:30 to 9:35")
        #expect(OverviewText.actualBlockLabel(actual(.work, t(9), t(9, 52)), locale: uk, timeZone: utcZone, bundle: ukrainian) == "Факт: Робота, з 9:00 до 9:52")
    }

    @Test func labelsUseTheTimeZone() throws {
        let english = try bundle("en"), plus3 = TimeZone(secondsFromGMT: 3 * 3600)!
        #expect(OverviewText.plannedBlockLabel(planned(.work, d(15, 6), d(15, 6, 50)), locale: en, timeZone: plus3, bundle: english) == "Plan: Work, from 9:00 to 9:50")
    }

    @Test func tooltip() {
        #expect(OverviewText.tooltip(kindName: "Work", start: t(9), end: t(9, 50), locale: en, timeZone: utcZone) == "9:00–9:50 · Work · 50 min")
        #expect(OverviewText.tooltip(kindName: "Робота", start: t(9), end: t(10, 5), locale: uk, timeZone: utcZone) == "9:00–10:05 · Робота · 1 год, 5 хв")
    }
}
