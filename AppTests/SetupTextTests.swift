import Foundation
import RipelineCore
import Testing
@testable import Ripeline

struct SetupTextTests {
    private let en = Locale(identifier: "en_GB")
    private let uk = Locale(identifier: "uk")

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    // MARK: durations and times

    @Test(arguments: [(0.0, "0 min"), (600.0, "10 min"), (2700.0, "45 min"), (7200.0, "2 hr"), (22500.0, "6 hr, 15 min")])
    func englishDurations(seconds: Double, expected: String) {
        #expect(SetupText.duration(seconds, locale: Locale(identifier: "en")) == expected)
    }

    @Test(arguments: [(0.0, "0 хв"), (2700.0, "45 хв"), (7200.0, "2 год"), (22500.0, "6 год, 15 хв")])
    func ukrainianDurations(seconds: Double, expected: String) {
        #expect(SetupText.duration(seconds, locale: uk) == expected)
    }

    @Test func timesFollowTheLocaleAndTheTimeZone() {
        let utc = TimeZone(secondsFromGMT: 0)!, plus3 = TimeZone(secondsFromGMT: 3 * 3600)!
        #expect(SetupText.time(d(15, 9, 0), locale: uk, timeZone: utc) == "9:00")
        #expect(SetupText.time(d(15, 14, 0), locale: uk, timeZone: plus3) == "17:00")
        #expect(SetupText.time(d(15, 9, 0), locale: Locale(identifier: "en_US"), timeZone: utc) == "9:00\u{202F}AM")
    }

    // MARK: messages

    private let issues: [DaySetupIssue] = [.endNotAfterNow, .dayTooShort, .invalidInput]

    @Test(arguments: ["en", "uk"])
    func issueMessagesAreFilledIn(language: String) throws {
        let bundle = try bundle(language)
        for issue in issues {
            let text = SetupText.message(for: issue, bundle: bundle)
            #expect(!text.isEmpty)
            #expect(!text.hasPrefix("setup."), "\(issue) is an untranslated key")
        }
    }

    @Test func issueMessagesDifferBetweenLanguagesAndFromEachOther() throws {
        let english = try bundle("en"), ukrainian = try bundle("uk")
        for issue in issues {
            #expect(SetupText.message(for: issue, bundle: english) != SetupText.message(for: issue, bundle: ukrainian))
        }
        #expect(Set(issues.map { SetupText.message(for: $0, bundle: english) }).count == issues.count)
    }

    @Test func noticeMessages() throws {
        let english = try bundle("en"), ukrainian = try bundle("uk")
        let notLong = SetupText.message(for: .longBreakNotPlaced, locale: en, bundle: english)
        #expect(!notLong.isEmpty && !notLong.hasPrefix("setup."))
        #expect(notLong != SetupText.message(for: .longBreakNotPlaced, locale: uk, bundle: ukrainian))

        let passedEn = SetupText.message(for: .longBreakTimePassed, locale: en, bundle: english)
        let passedUk = SetupText.message(for: .longBreakTimePassed, locale: uk, bundle: ukrainian)
        #expect(!passedEn.isEmpty && !passedEn.hasPrefix("setup."))
        #expect(!passedUk.isEmpty && !passedUk.hasPrefix("setup.") && passedUk != passedEn)

        let freeEn = SetupText.message(for: .remainderLeftFree(minutes: 10), locale: Locale(identifier: "en"), bundle: english)
        #expect(freeEn.contains("10 min"))
        #expect(!freeEn.hasPrefix("setup."))
        let oneEn = SetupText.message(for: .remainderLeftFree(minutes: 1), locale: Locale(identifier: "en"), bundle: english)
        #expect(!oneEn.contains(" are "), "the notice must read correctly for 1 minute")
        let freeUk = SetupText.message(for: .remainderLeftFree(minutes: 75), locale: uk, bundle: ukrainian)
        #expect(freeUk.contains("1 год, 15 хв"))
    }

    // MARK: segment labels

    private func segment(_ kind: SegmentKind, _ start: Date, _ end: Date) -> PlannedSegment {
        PlannedSegment(index: 0, kind: kind, start: start, end: end)
    }

    @Test func englishSegmentLabels() throws {
        let english = try bundle("en"), utc = TimeZone(secondsFromGMT: 0)!
        #expect(SetupText.segmentLabel(segment(.work, t(9), t(9, 50)), locale: en, timeZone: utc, bundle: english) == "Work, from 9:00 to 9:50")
        #expect(SetupText.segmentLabel(segment(.shortBreak, t(9, 50), t(10)), locale: en, timeZone: utc, bundle: english) == "Short break, from 9:50 to 10:00")
        #expect(SetupText.segmentLabel(segment(.longBreak, t(12, 50), t(13, 35)), locale: en, timeZone: utc, bundle: english) == "Long break, from 12:50 to 13:35")
    }

    @Test func ukrainianSegmentLabels() throws {
        let ukrainian = try bundle("uk"), utc = TimeZone(secondsFromGMT: 0)!
        #expect(SetupText.segmentLabel(segment(.work, t(9), t(9, 50)), locale: uk, timeZone: utc, bundle: ukrainian) == "Робота, з 9:00 до 9:50")
        #expect(SetupText.segmentLabel(segment(.longBreak, t(12, 50), t(13, 35)), locale: uk, timeZone: utc, bundle: ukrainian) == "Довга перерва, з 12:50 до 13:35")
    }

    @Test func segmentLabelsUseTheTimeZone() throws {
        let english = try bundle("en"), plus3 = TimeZone(secondsFromGMT: 3 * 3600)!
        #expect(SetupText.segmentLabel(segment(.work, d(15, 6, 0), d(15, 6, 50)), locale: en, timeZone: plus3, bundle: english) == "Work, from 9:00 to 9:50")
    }
}
