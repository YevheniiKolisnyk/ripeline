import SwiftUI
import RipelineCore

@main
struct RipelineApp: App {
    var body: some Scene {
        MenuBarExtra("Ripeline", systemImage: "timer") {
            Text(verbatim: "Ripeline")
        }
        .menuBarExtraStyle(.window)
    }
}
