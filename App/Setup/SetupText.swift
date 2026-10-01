import Foundation
import RipelineCore

/// Localized text for the setup window: messages, durations, times and accessibility labels.
/// Everything takes its locale and bundle explicitly so tests can ask for either language.
enum SetupText {
    static func message(for issue: DaySetupIssue, bundle: Bundle = .main) -> String {
        switch issue {
        case .endNotAfterNow: bundle.localizedString(forKey: "setup.issue.endNotAfterNow", value: nil, table: nil)
        case .dayTooShort: bundle.localizedString(forKey: "setup.issue.dayTooShort", value: nil, table: nil)
        case .invalidInput: bundle.localizedString(forKey: "setup.issue.invalidInput", value: nil, table: nil)
        }
    }

    static func message(for notice: DaySetupNotice, locale: Locale, bundle: Bundle = .main) -> String {
        switch notice {
        case .longBreakNotPlaced:
            return bundle.localizedString(forKey: "setup.notice.longBreakNotPlaced", value: nil, table: nil)
        case .longBreakTimePassed:
            return bundle.localizedString(forKey: "setup.notice.longBreakTimePassed", value: nil, table: nil)
        case let .remainderLeftFree(minutes):
            let format = bundle.localizedString(forKey: "setup.notice.remainderLeftFree", value: nil, table: nil)
            return String(format: format, duration(TimeInterval(minutes) * 60, locale: locale))
        }
    }

    /// Hours and minutes in the locale's abbreviated style: `6 hr, 15 min` or `6 год, 15 хв`.
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String {
        Duration.seconds(Int(seconds.rounded()))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale))
    }

    /// A time of day in the locale's short style, in `timeZone`.
    static func time(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
    }

    /// The name of a segment's kind.
    static func kindName(_ kind: SegmentKind, bundle: Bundle = .main) -> String {
        let key: String
        switch kind {
        case .work: key = "setup.work"
        case .shortBreak: key = "setup.shortBreak"
        case .longBreak: key = "setup.longBreak"
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// What VoiceOver reads for a segment: `Work, from 9:00 to 9:50`.
    static func segmentLabel(_ segment: PlannedSegment, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String {
        let format = bundle.localizedString(forKey: "a11y.segment", value: nil, table: nil)
        return String(
            format: format, kindName(segment.kind, bundle: bundle),
            time(segment.start, locale: locale, timeZone: timeZone),
            time(segment.end, locale: locale, timeZone: timeZone)
        )
    }
}
