import SwiftUI

/// A chosen day, read only: its date and times, the two timelines, the summary and the segment table,
/// and a button to delete it.
struct HistoryDetailView: View {
    let model: DayOverviewModel
    let entry: HistoryEntry
    let onDelete: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                TimelineRowsView(model: model)
                DaySummaryView(model: model)
                SegmentTableView(model: model)
                Divider()
                Button("history.delete", role: .destructive, action: onDelete)
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: HistoryText.dateTitle(entry.startedAt, locale: locale, timeZone: .autoupdatingCurrent))
                    .font(.title2.weight(.semibold))
                Text(verbatim: HistoryText.badge(entry))
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background((entry.isFinished ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                    .foregroundStyle(entry.isFinished ? Color.green : Color.orange)
            }
            Text(verbatim: HistoryText.rowSubtitle(entry, locale: locale, timeZone: .autoupdatingCurrent))
                .foregroundStyle(.secondary)
        }
    }
}
