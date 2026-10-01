import SwiftUI

/// Identifies the day setup window scene.
enum DaySetupWindow {
    static let id = "day-setup"
}

/// The day setup window. A placeholder until the form and the preview are built.
struct DaySetupView: View {
    let model: DaySetupModel
    let controller: SessionController

    var body: some View {
        Text("window.setup.title")
            .padding(40)
    }
}
