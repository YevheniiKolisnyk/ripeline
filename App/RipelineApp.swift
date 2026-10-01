import SwiftUI

@main
struct RipelineApp: App {
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(controller: environment.controller, settings: environment.settings)
        } label: {
            MenuBarLabel(controller: environment.controller, settings: environment.settings)
        }
        .menuBarExtraStyle(.window)

        Window("window.setup.title", id: DaySetupWindow.id) {
            DaySetupView(model: environment.setupModel, controller: environment.controller)
        }
        .defaultSize(width: 600, height: 640)
        .windowResizability(.contentSize)
    }
}
