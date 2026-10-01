import RipelineCore
import SwiftUI

/// The app's one window: the planning form when there is no day, the day screen while one runs,
/// and after it ended the day screen until the user asks for a new day.
struct RipelineWindowView: View {
    let setupModel: DaySetupModel
    let overviewModel: DayOverviewModel
    let controller: SessionController
    let settings: AppSettings
    /// The user pressed "New day" on a finished day.
    @State private var planningNew = false

    private enum Screen { case setup, day }

    /// Read from the controller, not from the model, so the window follows a start at once.
    private var screen: Screen {
        switch controller.phase {
        case .idle: .setup
        case .finished: planningNew ? .setup : .day
        case .working, .onBreak, .paused, .overtime: .day
        }
    }

    var body: some View {
        Group {
            switch screen {
            case .setup:
                DaySetupView(model: setupModel, controller: controller, settings: settings)
            case .day:
                DayScreenView(model: overviewModel, controller: controller, settings: settings) {
                    planningNew = true
                }
            }
        }
        .frame(minWidth: 720, minHeight: 620)
        .onChange(of: controller.phase) { _, phase in
            // A new day started (or the old one was ended from elsewhere): leave the planning view.
            if phase != .finished { planningNew = false }
            overviewModel.refresh()
        }
    }
}
