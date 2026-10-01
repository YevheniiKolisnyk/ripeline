import RipelineCore
import SwiftUI

/// The app's one window. "Today": the planning form when there is no day, the day screen while one
/// runs, and after it ended the day screen until the user asks for a new day. "History": the past days.
struct RipelineWindowView: View {
    let setupModel: DaySetupModel
    let overviewModel: DayOverviewModel
    let historyModel: HistoryModel
    let router: AppRouter
    let controller: SessionController
    let settings: AppSettings
    private enum Screen { case setup, day }

    /// Read from the controller, not from the model, so the window follows a start at once.
    private var screen: Screen {
        switch controller.phase {
        case .idle: .setup
        case .finished: router.planningNewDay ? .setup : .day
        case .working, .onBreak, .paused, .overtime: .day
        }
    }

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            Picker("", selection: $router.tab) {
                Text("tab.today").tag(WindowTab.today)
                Text("tab.history").tag(WindowTab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.vertical, 10)
            Divider()
            switch router.tab {
            case .today: today
            case .history: HistoryView(model: historyModel)
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .onChange(of: controller.phase) { _, phase in
            // A new day started (or the old one was ended from elsewhere): leave the planning view.
            if phase != .finished { router.planningNewDay = false }
            overviewModel.refresh()
            // The history is re-read on its own tab (and when the tab appears), not at every segment change.
            if router.tab == .history { historyModel.refresh() }
        }
    }

    @ViewBuilder private var today: some View {
        switch screen {
        case .setup:
            DaySetupView(model: setupModel, controller: controller, settings: settings)
        case .day:
            DayScreenView(model: overviewModel, controller: controller, settings: settings) {
                router.planningNewDay = true
            }
        }
    }
}
