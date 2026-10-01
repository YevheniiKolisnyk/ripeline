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
            TomatoPatchView(tomatoes: controller.tomatoes)
            if controller.isAllowed(.startDay) {
                QuickStartSection(controller: controller, settings: settings)
            }
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
        let visible = PopoverActions.visible(phase: controller.phase, isQuick: controller.isQuickSession, isAllowed: controller.isAllowed)
        let buttons = visible.filter { $0 != .overview && $0 != .history }
        // With the quick start above them, "Plan day…" is not the main button.
        let firstIsMain = !controller.isAllowed(.startDay)
        // Up to five buttons: laid out in rows of three so they fit.
        let rows = stride(from: 0, to: buttons.count, by: 3).map { Array(buttons[$0..<min($0 + 3, buttons.count)]) }
        return VStack(alignment: .leading, spacing: 10) {
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 8) {
                            ForEach(Array(row.enumerated()), id: \.offset) { index, action in
                                if rowIndex == 0 && index == 0 && firstIsMain {
                                    button(for: action).buttonStyle(.glassProminent)
                                } else {
                                    button(for: action).buttonStyle(.glass)
                                }
                            }
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
            router.showToday()
            openWindow(id: MainWindow.id)
            // An app without a Dock icon does not come to the front by itself.
            NSApplication.shared.activate()
        case .history:
            router.showHistory()
            openWindow(id: MainWindow.id)
            // An app without a Dock icon does not come to the front by itself.
            NSApplication.shared.activate()
        case .pause: controller.pause()
        case .resume: controller.resume()
        case .extend: controller.extend(minutes: 5)
        case .skip: controller.skip()
        case .next: controller.advance()
        case .endDay, .done: controller.endDay()
        case .addBlock: controller.addBlock()
        }
    }
}
