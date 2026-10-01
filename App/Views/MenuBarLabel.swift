import SwiftUI

/// The menu bar item: the growing tomato during work, an icon for the phase otherwise and, unless hidden, the time.
struct MenuBarLabel: View {
    let controller: SessionController
    let settings: AppSettings
    @Environment(\.locale) private var locale

    var body: some View {
        let model = MenuBarLabelModel(
            phase: controller.phase, remaining: controller.remaining,
            overtimeElapsed: controller.overtimeElapsed, showTime: settings.showTimeInMenuBar,
            tomatoGrowth: controller.currentTomatoGrowth
        )
        HStack(alignment: .center, spacing: 4) {
            icon(model.icon)
            if let text = model.text {
                Text(verbatim: text).monospacedDigit()
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: AccessibilityText.menuBarLabel(
            phase: controller.phase, remaining: controller.remaining,
            overtimeElapsed: controller.overtimeElapsed, locale: locale
        )))
    }

    @ViewBuilder private func icon(_ icon: MenuBarLabelModel.Icon) -> some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
        case let .tomato(growth, frozen):
            Image(nsImage: MenuBarTomato.image(growth: growth, frozen: frozen))
        }
    }
}
