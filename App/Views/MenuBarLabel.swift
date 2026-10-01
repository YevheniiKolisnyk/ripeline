import SwiftUI

/// The menu bar item: an icon for the phase and, unless hidden, the time.
struct MenuBarLabel: View {
    let controller: SessionController
    let settings: AppSettings

    var body: some View {
        let model = MenuBarLabelModel(
            phase: controller.phase, remaining: controller.remaining,
            overtimeElapsed: controller.overtimeElapsed, showTime: settings.showTimeInMenuBar
        )
        HStack(spacing: 4) {
            Image(systemName: model.symbolName)
            if let text = model.text {
                Text(verbatim: text).monospacedDigit()
            }
        }
    }
}
