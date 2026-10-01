import Foundation
import RipelineCore

/// Localized text for the day screen. Locale, time zone and bundle are explicit so tests can ask
/// for either language.
enum OverviewText {
    /// The lag chip: `On schedule`, `3 min behind schedule`, `2 min ahead of schedule`.
    static func lag(_ state: LagState, locale: Locale, bundle: Bundle = .main) -> String {
        switch state {
        case .onSchedule:
            return bundle.localizedString(forKey: "lag.onSchedule", value: nil, table: nil)
        case let .behind(seconds):
            let format = bundle.localizedString(forKey: "lag.behind", value: nil, table: nil)
            return String(format: format, SetupText.duration(seconds, locale: locale))
        case let .ahead(seconds):
            let format = bundle.localizedString(forKey: "lag.ahead", value: nil, table: nil)
            return String(format: format, SetupText.duration(seconds, locale: locale))
        }
    }

    /// A difference with its sign: `+2 min`, `−19 min`; under a minute it is `0 min`.
    static func delta(_ seconds: TimeInterval, locale: Locale) -> String {
        guard abs(seconds) >= 60 else { return SetupText.duration(0, locale: locale) }
        let sign = seconds > 0 ? "+" : "\u{2212}"
        return sign + SetupText.duration(abs(seconds), locale: locale)
    }

    static func status(_ status: SegmentStatus, bundle: Bundle = .main) -> String {
        let key: String
        switch status {
        case .notStarted: key = "status.notStarted"
        case .active: key = "status.active"
        case .completed: key = "status.completed"
        case .skipped: key = "status.skipped"
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    /// What VoiceOver reads for a planned block: `Plan: Work, from 9:00 to 9:50`.
    static func plannedBlockLabel(
        _ block: BlockLayout<SegmentKind>, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main
    ) -> String {
        blockLabel(
            rowKey: "overview.plan", kindName: SetupText.kindName(block.kind, bundle: bundle),
            start: block.start, end: block.end, locale: locale, timeZone: timeZone, bundle: bundle
        )
    }

    /// What VoiceOver reads for an actual block: `Actual: Rest, from 9:52 to 10:04`.
    static func actualBlockLabel(
        _ block: BlockLayout<ActualKind>, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main
    ) -> String {
        blockLabel(
            rowKey: "overview.actual", kindName: actualKindName(block.kind, bundle: bundle),
            start: block.start, end: block.end, locale: locale, timeZone: timeZone, bundle: bundle
        )
    }

    static func actualKindName(_ kind: ActualKind, bundle: Bundle = .main) -> String {
        switch kind {
        case .work: SetupText.kindName(.work, bundle: bundle)
        case .rest: bundle.localizedString(forKey: "overview.kind.rest", value: nil, table: nil)
        case .untracked: bundle.localizedString(forKey: "summary.untracked", value: nil, table: nil)
        }
    }

    /// The hover text of a block: `9:00–9:50 · Work · 50 min`.
    static func tooltip(kindName: String, start: Date, end: Date, locale: Locale, timeZone: TimeZone) -> String {
        let from = SetupText.time(start, locale: locale, timeZone: timeZone)
        let to = SetupText.time(end, locale: locale, timeZone: timeZone)
        return "\(from)–\(to) · \(kindName) · \(SetupText.duration(end.timeIntervalSince(start), locale: locale))"
    }

    private static func blockLabel(
        rowKey: String, kindName: String, start: Date, end: Date, locale: Locale, timeZone: TimeZone, bundle: Bundle
    ) -> String {
        let format = bundle.localizedString(forKey: "a11y.block", value: nil, table: nil)
        return String(
            format: format, bundle.localizedString(forKey: rowKey, value: nil, table: nil), kindName,
            SetupText.time(start, locale: locale, timeZone: timeZone), SetupText.time(end, locale: locale, timeZone: timeZone)
        )
    }
}
