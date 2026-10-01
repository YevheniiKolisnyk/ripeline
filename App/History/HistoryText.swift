import Foundation

/// Localized text for the history list: the date, the row line, the badge and what VoiceOver reads.
/// Locale, time zone and bundle are explicit so tests can ask for either language.
enum HistoryText {
    /// The weekday, day and month in the locale's short form: `Thu 15 Jan`, `чт, 15 січ.`.
    static func dateTitle(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
                .weekday(.abbreviated).day().month(.abbreviated)
        )
    }

    /// The row's second line: `9:00–9:30 · Focus 30 min / 2 hr, 30 min`. Without a recorded end it
    /// shows only the start.
    static func rowSubtitle(_ entry: HistoryEntry, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String {
        let focus = bundle.localizedString(forKey: "summary.focus", value: nil, table: nil)
        return "\(times(entry, locale: locale, timeZone: timeZone)) · \(focus) \(figures(entry, locale: locale))"
    }

    /// `Finished`, or `Not finished` for a day that was never ended.
    static func badge(_ entry: HistoryEntry, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: entry.isFinished ? "history.finished" : "history.notFinished", value: nil, table: nil)
    }

    /// What VoiceOver reads for a row, as a sentence.
    static func accessibilityLabel(_ entry: HistoryEntry, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String {
        let date = entry.startedAt.formatted(
            Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: timeZone)
                .weekday(.wide).day().month(.wide)
        )
        let status = badge(entry, bundle: bundle).lowercased(with: locale)
        let start = SetupText.time(entry.startedAt, locale: locale, timeZone: timeZone)
        let actual = SetupText.duration(entry.focusActual, locale: locale)
        let planned = SetupText.duration(entry.focusPlanned, locale: locale)
        var label: String
        if let end = entry.endedAt {
            let format = bundle.localizedString(forKey: "a11y.historyRow", value: nil, table: nil)
            label = String(format: format, date, start, SetupText.time(end, locale: locale, timeZone: timeZone), status, actual, planned)
        } else {
            let format = bundle.localizedString(forKey: "a11y.historyRowStarted", value: nil, table: nil)
            label = String(format: format, date, start, status, actual, planned)
        }
        // What a sighted user reads under the badge is heard too.
        if entry.isQuick {
            label += ", " + bundle.localizedString(forKey: "a11y.historyQuick", value: nil, table: nil)
        } else if let lag = entry.lag {
            let format = bundle.localizedString(forKey: "a11y.historyLag", value: nil, table: nil)
            label += ", " + String(format: format, OverviewText.delta(lag, locale: locale))
        }
        return label
    }

    private static func times(_ entry: HistoryEntry, locale: Locale, timeZone: TimeZone) -> String {
        let start = SetupText.time(entry.startedAt, locale: locale, timeZone: timeZone)
        guard let end = entry.endedAt else { return start }
        return "\(start)–\(SetupText.time(end, locale: locale, timeZone: timeZone))"
    }

    private static func figures(_ entry: HistoryEntry, locale: Locale) -> String {
        "\(SetupText.duration(entry.focusActual, locale: locale)) / \(SetupText.duration(entry.focusPlanned, locale: locale))"
    }
}
