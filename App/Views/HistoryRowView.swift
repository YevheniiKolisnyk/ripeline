import SwiftUI

/// One day in the history list: its date, the times and focus, a badge and, for a finished day, its lag.
struct HistoryRowView: View {
    let entry: HistoryEntry
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: HistoryText.dateTitle(entry.startedAt, locale: locale, timeZone: .autoupdatingCurrent))
                    .font(.headline)
                Text(verbatim: HistoryText.rowSubtitle(entry, locale: locale, timeZone: .autoupdatingCurrent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(verbatim: HistoryText.badge(entry))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(entry.isFinished ? Color.green : Color.orange)
                if let lag = entry.lag {
                    Text(verbatim: OverviewText.delta(lag, locale: locale))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistoryText.accessibilityLabel(entry, locale: locale, timeZone: .autoupdatingCurrent))
    }
}
