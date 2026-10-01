import SwiftUI

@main
struct RipelineApp: App {
    @State private var environment = AppEnvironment.make()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(controller: environment.controller, settings: environment.settings, router: environment.router)
        } label: {
            MenuBarLabel(controller: environment.controller, settings: environment.settings)
        }
        .menuBarExtraStyle(.window)

        Window("app.name", id: MainWindow.id) {
            RipelineWindowView(
                setupModel: environment.setupModel, overviewModel: environment.overviewModel,
                historyModel: environment.historyModel, router: environment.router,
                controller: environment.controller, settings: environment.settings
            )
        }
        .defaultSize(width: 760, height: 700)
        .windowResizability(.contentMinSize)
    }
}
