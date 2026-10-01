import Foundation
import RipelineCore

/// The presets offered by name.
enum BuiltInPreset: String, Codable, CaseIterable, Sendable {
    case classic
    case deepWork
    case longBlocks

    /// Work, short break and long break lengths in minutes.
    var preset: Preset {
        switch self {
        case .classic: Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15)
        case .deepWork: Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45)
        case .longBlocks: Preset(workMinutes: 90, shortBreakMinutes: 15, longBreakMinutes: 30)
        }
    }
}

enum PresetChoice: Codable, Equatable, Hashable, Sendable {
    case builtIn(BuiltInPreset)
    case custom
}

enum DayModeChoice: String, Codable, CaseIterable, Sendable {
    /// Fit blocks until a time of day.
    case untilTime
    /// Generate blocks until the focus time is reached.
    case netFocus
}

enum LongBreakChoice: Codable, Equatable, Sendable {
    case none
    case atTime(TimeOfDay)
    /// After the n-th work block (1-based).
    case afterBlock(Int)
}

enum RemainderChoice: String, Codable, CaseIterable, Sendable {
    case shortBlock
    case leaveFree
    case stretchBlocks
}

/// Everything the user enters to define a day. Stored as the last choice.
struct DayPlanForm: Codable, Equatable, Sendable {
    var presetChoice: PresetChoice
    /// Used when `presetChoice` is `.custom`.
    var customPreset: Preset
    var mode: DayModeChoice
    /// The end of the day, for `.untilTime`.
    var endTime: TimeOfDay
    /// The focus amount, for `.netFocus`.
    var focusMinutes: Int
    var longBreak: LongBreakChoice
    /// Ignored in `.netFocus` mode.
    var remainder: RemainderChoice
    /// The smallest leftover block worth adding, for `RemainderChoice.shortBlock`.
    var minBlockMinutes: Int

    static let standard = DayPlanForm(
        presetChoice: .builtIn(.deepWork),
        customPreset: BuiltInPreset.deepWork.preset,
        mode: .untilTime,
        endTime: TimeOfDay(hour: 17, minute: 0),
        focusMinutes: 240,
        longBreak: .none,
        remainder: .shortBlock,
        minBlockMinutes: 15
    )

    /// The preset the form selects.
    var preset: Preset {
        switch presetChoice {
        case let .builtIn(builtIn): builtIn.preset
        case .custom: customPreset
        }
    }

    /// The same form with every number brought into its allowed range. Values are clamped, never
    /// rounded, so nothing the user could have entered is altered.
    func normalized() -> DayPlanForm {
        var form = self
        form.customPreset = Preset(
            workMinutes: min(240, max(1, customPreset.workMinutes)),
            shortBreakMinutes: min(120, max(1, customPreset.shortBreakMinutes)),
            longBreakMinutes: min(120, max(1, customPreset.longBreakMinutes))
        )
        form.focusMinutes = min(720, max(15, focusMinutes))
        if case let .afterBlock(block) = longBreak { form.longBreak = .afterBlock(min(20, max(1, block))) }
        form.minBlockMinutes = min(120, max(1, minBlockMinutes))
        return form
    }
}
