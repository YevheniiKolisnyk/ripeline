import RipelineCore
import SwiftUI

/// The segment table: planned start, kind, plan, actual, the difference and the status.
struct SegmentTableView: View {
    let model: DayOverviewModel
    @Environment(\.locale) private var locale

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                header("table.start"); header("table.segment"); header("table.plan")
                header("table.actual"); header("table.delta"); header("table.status")
            }
            Divider().gridCellColumns(6)
            ForEach(model.segments, id: \.index) { row in
                GridRow {
                    Text(verbatim: SetupText.time(row.start, locale: locale, timeZone: .autoupdatingCurrent)).monospacedDigit()
                    Text(verbatim: SetupText.kindName(row.kind))
                    Text(verbatim: SetupText.duration(row.planned, locale: locale))
                    Text(verbatim: row.status == .notStarted ? Bundle.main.localizedString(forKey: "overview.noValue", value: nil, table: nil) : SetupText.duration(row.actual, locale: locale))
                    // A segment still to come or still running has no difference yet.
                    Text(verbatim: hasDifference(row) ? OverviewText.delta(row.delta, locale: locale) : "")
                        .foregroundStyle(Self.deltaColour(row.delta, status: row.status))
                    Text(verbatim: OverviewText.status(row.status))
                        .foregroundStyle(row.status == .skipped ? .secondary : .primary)
                }
                .fontWeight(row.status == .active ? .semibold : .regular)
            }
        }
    }

    private func hasDifference(_ row: SegmentRow) -> Bool {
        row.status == .completed || row.status == .skipped
    }

    private func header(_ key: LocalizedStringKey) -> some View {
        Text(key).font(.caption).foregroundStyle(.secondary)
    }

    /// Later than planned is orange, earlier is green; within a minute is plain. A skipped segment
    /// was cut short on purpose, so its difference is not a win and stays plain.
    static func deltaColour(_ delta: TimeInterval, status: SegmentStatus) -> Color {
        if status == .skipped || abs(delta) < 60 { return .secondary }
        return delta > 0 ? .orange : .green
    }
}
