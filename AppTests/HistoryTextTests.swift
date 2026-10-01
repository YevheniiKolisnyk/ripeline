import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct HistoryTextTests {
    private let en = Locale(identifier: "en_GB")
    private let uk = Locale(identifier: "uk")
    private let utcZone = TimeZone(secondsFromGMT: 0)!

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func entry(_ snapshot: SessionSnapshot) -> HistoryEntry {
        HistoryEntry(day: StoredDay(key: "2026-01-15", snapshot: snapshot))
    }

    // MARK: date title

    @Test func dateTitlesFollowTheLocale() {
        #expect(HistoryText.dateTitle(d(15, 12), locale: en, timeZone: utcZone) == "Thu 15 Jan")
        #expect(HistoryText.dateTitle(d(15, 12), locale: uk, timeZone: utcZone) == "чт, 15 січ.")
    }

    @Test func dateTitlesUseTheTimeZone() {
        let plus3 = TimeZone(secondsFromGMT: 3 * 3600)!
        // 22:30 UTC on the 14th is already the 15th at +03:00.
        #expect(HistoryText.dateTitle(d(14, 22, 30), locale: en, timeZone: plus3) == "Thu 15 Jan")
        #expect(HistoryText.dateTitle(d(14, 22, 30), locale: en, timeZone: utcZone) == "Wed 14 Jan")
    }

    // MARK: row subtitle

    @Test func rowSubtitleOfAFinishedDay() throws {
        let e = entry(try finishedDay())
        #expect(HistoryText.rowSubtitle(e, locale: en, timeZone: utcZone, bundle: try bundle("en")) == "9:00–9:30 · Focus 30 min / 2 hrs, 30 min")
        #expect(HistoryText.rowSubtitle(e, locale: uk, timeZone: utcZone, bundle: try bundle("uk")) == "9:00–9:30 · Фокус 30 хв / 2 год, 30 хв")
    }

    @Test func rowSubtitleWithoutAnEnd() throws {
        let e = entry(try playedDay { engine, _ in try engine.endDay() })
        #expect(HistoryText.rowSubtitle(e, locale: en, timeZone: utcZone, bundle: try bundle("en")) == "9:00 · Focus 0 min / 2 hrs, 30 min")
    }

    @Test func rowSubtitleUsesTheTimeZone() throws {
        let e = entry(try finishedDay(start: d(15, 6)))
        let plus3 = TimeZone(secondsFromGMT: 3 * 3600)!
        #expect(HistoryText.rowSubtitle(e, locale: en, timeZone: plus3, bundle: try bundle("en")).hasPrefix("9:00–9:30"))
    }

    // MARK: badge

    @Test(arguments: ["en", "uk"])
    func badges(language: String) throws {
        let b = try bundle(language)
        let finished = HistoryText.badge(entry(try finishedDay()), bundle: b)
        let open = HistoryText.badge(entry(try abandonedDay()), bundle: b)
        #expect(finished != open)
        #expect(!finished.hasPrefix("history.") && !open.hasPrefix("history."))
    }

    @Test func badgesDifferBetweenLanguages() throws {
        let day = entry(try finishedDay())
        #expect(HistoryText.badge(day, bundle: try bundle("en")) == "Finished")
        #expect(HistoryText.badge(day, bundle: try bundle("uk")) == "Завершено")
        let open = entry(try abandonedDay())
        #expect(HistoryText.badge(open, bundle: try bundle("en")) == "Not finished")
        #expect(HistoryText.badge(open, bundle: try bundle("uk")) == "Не завершено")
    }

    // MARK: VoiceOver

    @Test func accessibilityLabelOfAFinishedDay() throws {
        let e = entry(try finishedDay())
        #expect(HistoryText.accessibilityLabel(e, locale: en, timeZone: utcZone, bundle: try bundle("en"))
            == "Thursday 15 January, from 9:00 to 9:30, finished, focus 30 min of 2 hrs, 30 min, \u{2212}2 hrs, 20 min against plan")
        #expect(HistoryText.accessibilityLabel(e, locale: uk, timeZone: utcZone, bundle: try bundle("uk"))
            == "четвер, 15 січня, з 9:00 до 9:30, завершено, фокус 30 хв із 2 год, 30 хв, \u{2212}2 год, 20 хв відносно плану")
    }

    @Test func accessibilityLabelOfADayNeverEnded() throws {
        let e = entry(try abandonedDay())
        let label = HistoryText.accessibilityLabel(e, locale: en, timeZone: utcZone, bundle: try bundle("en"))
        #expect(label.contains("from 9:00 to 9:35"))
        #expect(label.contains("not finished"))
    }

    @Test func accessibilityLabelWithoutAnEnd() throws {
        let e = entry(try playedDay { engine, _ in try engine.endDay() })
        let label = HistoryText.accessibilityLabel(e, locale: en, timeZone: utcZone, bundle: try bundle("en"))
        #expect(label.contains("from 9:00,"))
        #expect(!label.contains(" to "))
    }

    // MARK: review finding: what a sighted user sees under the badge is heard too

    @Test func theAccessibilityLabelIncludesTheLagOfAFinishedDay() throws {
        let e = entry(try finishedDay())                      // ended 2 h 20 min before the plan
        let english = HistoryText.accessibilityLabel(e, locale: en, timeZone: utcZone, bundle: try bundle("en"))
        #expect(english.hasSuffix(", \u{2212}2 hrs, 20 min against plan"))
        let ukrainian = HistoryText.accessibilityLabel(e, locale: uk, timeZone: utcZone, bundle: try bundle("uk"))
        #expect(ukrainian.hasSuffix(", \u{2212}2 год, 20 хв відносно плану"))
    }

    @Test func aDayWithoutALagHasNoSuffix() throws {
        let label = HistoryText.accessibilityLabel(entry(try abandonedDay()), locale: en, timeZone: utcZone, bundle: try bundle("en"))
        #expect(!label.contains("against plan"))
    }
}
