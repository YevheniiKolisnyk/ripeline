import SwiftUI

/// The popover under the menu bar item. A placeholder until the next task.
struct PopoverView: View {
    let controller: SessionController
    let settings: AppSettings

    var body: some View {
        Text(controller.phase.labelKey)
            .padding()
    }
}
