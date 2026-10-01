import AppKit
import SwiftUI

/// The popover under the menu bar item: the current segment, the controls, and the settings.
struct PopoverView: View {
    let controller: SessionController
    let settings: AppSettings
    let router: AppRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 16) {
            header
            actions
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Toggle("ui.showTime", isOn: $settings.showTimeInMenuBar)
                Button("ui.quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: Header

    private var timerText: String? {
        MenuBarLabelModel(
            phase: controller.phase, remaining: controller.remaining,
            overtimeElapsed: controller.overtimeElapsed, showTime: true
        ).text
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(controller.phase.labelKey)
                .font(.headline)
                .foregroundStyle(.secondary)
            if let timerText {
                Text(verbatim: timerText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel(Text("a11y.timer"))
                    .accessibilityValue(Text(verbatim: AccessibilityText.timerValue(
                        phase: controller.phase, remaining: controller.remaining,
                        overtimeElapsed: controller.overtimeElapsed, locale: locale
                    ) ?? timerText))
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let progress = controller.progress {
                ProgressView(value: progress)
            }
        }
    }

    // MARK: Actions

    private var actions: some View {
        let visible = PopoverActions.visible(phase: controller.phase, isAllowed: controller.isAllowed)
        let buttons = visible.filter { $0 != .overview && $0 != .history }
        return VStack(alignment: .leading, spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { index, action in
                        if index == 0 {
                            button(for: action).buttonStyle(.glassProminent)
                        } else {
                            button(for: action).buttonStyle(.glass)
                        }
                    }
                }
            }
            if visible.contains(.overview) {
                button(for: .overview).buttonStyle(.link)
            }
            if visible.contains(.history) {
                button(for: .history).buttonStyle(.link)
            }
        }
    }

    private func button(for action: PopoverAction) -> some View {
        Button(LocalizedStringKey(action.titleKey)) { perform(action) }
    }

    private func perform(_ action: PopoverAction) {
        switch action {
        case .planDay, .overview, .summary:
            router.tab = .today
            openWindow(id: MainWindow.id)
            // An app without a Dock icon does not come to the front by itself.
            NSApplication.shared.activate()
        case .history:
            router.tab = .history
            openWindow(id: MainWindow.id)
            // An app without a Dock icon does not come to the front by itself.
            NSApplication.shared.activate()
        case .pause: controller.pause()
        case .resume: controller.resume()
        case .extend: controller.extend(minutes: 5)
        case .skip: controller.skip()
        case .next: controller.advance()
        case .endDay: controller.endDay()
        }
    }
}
