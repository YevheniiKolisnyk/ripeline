import RipelineCore
import SwiftUI

/// The day screen: lag and ends, the two timelines, the summary, the segment table and the settings.
struct DayScreenView: View {
    let model: DayOverviewModel
    let controller: SessionController
    let settings: AppSettings
    /// Called when the user asks to plan a new day after this one finished.
    let onNewDay: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            content
                .onChange(of: context.date) { model.refresh() }
        }
        .onAppear { model.refresh() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                TimelineRowsView(model: model)
                DaySummaryView(model: model)
                SegmentTableView(model: model)
                Divider()
                BehaviourSection(controller: controller, settings: settings)
                actions
            }
            .padding(20)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(controller.phase.labelKey).font(.title2.weight(.semibold))
            if let lag = model.lag {
                Text(verbatim: OverviewText.lag(lag, locale: locale))
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(chipColour(lag).opacity(0.18), in: Capsule())
                    .foregroundStyle(chipColour(lag))
            }
            Spacer()
        }
    }

    private func chipColour(_ lag: LagState) -> Color {
        switch lag {
        case .onSchedule: .secondary
        case .behind: .orange
        case .ahead: .green
        }
    }

    // MARK: Actions

    @ViewBuilder private var actions: some View {
        switch model.mode {
        case .running:
            Button(LocalizedStringKey(model.isQuick ? "ui.done" : "ui.endDay")) { controller.endDay() }
        case .finished:
            Button("overview.newDay", action: onNewDay).buttonStyle(.borderedProminent)
        case .noDay:
            EmptyView()
        }
    }
}
