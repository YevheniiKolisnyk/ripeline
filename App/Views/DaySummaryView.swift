import SwiftUI

/// Focus, rest and paused time (actual / planned) and the end of the day, planned and projected or final.
struct DaySummaryView: View {
    let model: DayOverviewModel
    @Environment(\.locale) private var locale

    var body: some View {
        if let summary = model.summary {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
                GridRow { Text("summary.focus"); value("\(duration(summary.focusActual)) / \(duration(summary.focusPlanned))") }
                GridRow { Text("summary.rest"); value("\(duration(summary.restActual)) / \(duration(summary.restPlanned))") }
                GridRow { Text("summary.untracked"); value(duration(summary.untracked)) }
                if !model.isQuick {
                    GridRow { Text("summary.plannedEnd"); value(time(summary.plannedEnd)) }
                }
                // A running quick session has no projected end; its final end is shown once it is over.
                if !(model.isQuick && summary.endKind == .projected) {
                    GridRow {
                        Text(endLabel(summary.endKind))
                        value(time(summary.endsAt))
                    }
                }
            }
        }
    }

    private func endLabel(_ kind: DaySummary.EndKind) -> LocalizedStringKey {
        switch kind {
        case .projected: "summary.projectedEnd"
        case .final: "summary.finishedAt"
        case .lastRecord: "history.lastRecord"
        }
    }

    private func value(_ text: String) -> some View {
        Text(verbatim: text).font(.body.weight(.medium)).monospacedDigit()
    }

    private func duration(_ seconds: TimeInterval) -> String { SetupText.duration(seconds, locale: locale) }

    private func time(_ date: Date?) -> String {
        guard let date else { return Bundle.main.localizedString(forKey: "overview.noValue", value: nil, table: nil) }
        return SetupText.time(date, locale: locale, timeZone: .autoupdatingCurrent)
    }
}
