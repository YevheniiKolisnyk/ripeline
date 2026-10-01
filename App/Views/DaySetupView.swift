import RipelineCore
import SwiftUI

/// Identifies the day setup window scene.
enum DaySetupWindow {
    static let id = "day-setup"
}

/// The day setup window: a form on the left, the plan it makes on the right, and the start button.
struct DaySetupView: View {
    @Bindable var model: DaySetupModel
    let controller: SessionController
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            content
                .onChange(of: context.date) { model.refresh() }
        }
        .frame(width: 600, height: 640)
        .onAppear { model.refresh() }
    }

    @ViewBuilder private var content: some View {
        if model.isDayRunning {
            runningNotice
        } else {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    form.frame(width: 300)
                    Divider()
                    PlanPreviewView(result: model.result).frame(maxWidth: .infinity)
                }
                Divider()
                bottomBar
            }
        }
    }

    // MARK: A day is already running

    private var runningNotice: some View {
        VStack(spacing: 16) {
            Text("setup.dayRunning").font(.headline)
            Button("ui.endDay") { controller.endDay() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: The form

    private var form: some View {
        Form {
            Section {
                Picker("setup.preset", selection: $model.form.presetChoice) {
                    ForEach(BuiltInPreset.allCases, id: \.self) { preset in
                        Text(LocalizedStringKey(Self.titleKey(preset))).tag(PresetChoice.builtIn(preset))
                    }
                    Text("preset.custom").tag(PresetChoice.custom)
                }
                if model.form.presetChoice == .custom {
                    minutesStepper("setup.work", value: $model.form.customPreset.workMinutes, range: 1...240)
                    minutesStepper("setup.shortBreak", value: $model.form.customPreset.shortBreakMinutes, range: 1...120)
                    minutesStepper("setup.longBreak", value: $model.form.customPreset.longBreakMinutes, range: 1...120)
                }
            }

            Section {
                Picker("setup.mode", selection: $model.form.mode) {
                    Text("mode.untilTime").tag(DayModeChoice.untilTime)
                    Text("mode.netFocus").tag(DayModeChoice.netFocus)
                }
                .pickerStyle(.segmented)
                if model.form.mode == .untilTime {
                    DatePicker(
                        "setup.endTime",
                        selection: timeBinding(get: { model.form.endTime }, set: { model.form.endTime = $0 }),
                        displayedComponents: .hourAndMinute
                    )
                } else {
                    minutesStepper("setup.focus", value: $model.form.focusMinutes, range: 15...720, step: 15)
                }
            }

            Section {
                Picker("setup.longBreak", selection: $model.longBreakKind) {
                    Text("longBreak.none").tag(LongBreakKind.none)
                    Text("longBreak.atTime").tag(LongBreakKind.atTime)
                    Text("longBreak.afterBlock").tag(LongBreakKind.afterBlock)
                }
                if case .atTime = model.form.longBreak {
                    DatePicker(
                        "setup.longBreakTime",
                        selection: timeBinding(
                            get: { if case let .atTime(time) = model.form.longBreak { time } else { TimeOfDay(hour: 13, minute: 0) } },
                            set: { model.form.longBreak = .atTime($0) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }
                if case .afterBlock = model.form.longBreak {
                    Stepper(value: blockNumber, in: 1...20) {
                        LabeledContent("setup.longBreakBlock") { Text(verbatim: String(blockNumber.wrappedValue)) }
                    }
                }
            }

            Section {
                Picker("setup.remainder", selection: $model.form.remainder) {
                    Text("remainder.shortBlock").tag(RemainderChoice.shortBlock)
                    Text("remainder.leaveFree").tag(RemainderChoice.leaveFree)
                    Text("remainder.stretch").tag(RemainderChoice.stretchBlocks)
                }
                if model.form.remainder == .shortBlock {
                    minutesStepper("setup.minBlock", value: $model.form.minBlockMinutes, range: 1...120)
                }
            }
            .disabled(model.form.mode == .netFocus)
        }
        .formStyle(.grouped)
    }

    private static func titleKey(_ preset: BuiltInPreset) -> String {
        switch preset {
        case .classic: "preset.classic"
        case .deepWork: "preset.deepWork"
        case .longBlocks: "preset.longBlocks"
        }
    }

    private func minutesStepper(_ title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title) { Text(verbatim: SetupText.duration(TimeInterval(value.wrappedValue) * 60, locale: locale)) }
        }
    }

    /// A `Date` binding for a `TimeOfDay`, on the day of the preview.
    private func timeBinding(get: @escaping () -> TimeOfDay, set: @escaping (TimeOfDay) -> Void) -> Binding<Date> {
        Binding(
            get: { get().date(on: model.now, calendar: .autoupdatingCurrent) },
            set: { set(TimeOfDay(date: $0, calendar: .autoupdatingCurrent)) }
        )
    }

    private var blockNumber: Binding<Int> {
        Binding(
            get: { if case let .afterBlock(number) = model.form.longBreak { number } else { 2 } },
            set: { model.form.longBreak = .afterBlock($0) }
        )
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("setup.close") { dismissWindow(id: DaySetupWindow.id) }
            Button("ui.startDay") {
                Task {
                    if await model.startDay() { dismissWindow(id: DaySetupWindow.id) }
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canStartNow)
            .accessibilityHint(Text(model.canStartNow ? "" : "a11y.startBlocked"))
        }
        .padding(12)
    }
}
