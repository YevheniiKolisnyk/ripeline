import Foundation

/// Everything the user chooses at the start of the day.
public struct DayPlanRequest: Codable, Sendable, Equatable {
    /// How the length of the day is defined.
    public enum Mode: Codable, Sendable, Equatable {
        /// Fit blocks between a start and an end time.
        case untilTime(start: Date, end: Date)
        /// Generate blocks until the total work time reaches `focusMinutes`.
        case netFocus(start: Date, focusMinutes: Int)
    }

    /// Where the long break goes. It replaces a short break between two work blocks.
    public enum LongBreak: Codable, Sendable, Equatable {
        case none
        /// The junction closest to this time (the earlier one on a tie).
        case atTime(Date)
        /// The junction after the n-th work block (1-based).
        case afterWorkBlock(Int)
    }

    /// What to do with time left over after the last full cycle (`.untilTime` only).
    public enum RemainderStrategy: Codable, Sendable, Equatable {
        /// A short break plus a work block filling the rest, if that block has at least
        /// `minMinutes`; otherwise the remainder is left free.
        case shortBlock(minMinutes: Int)
        case leaveFree
        /// Lengthen work blocks evenly so the plan ends exactly at the end time.
        case stretchBlocks
    }

    public var mode: Mode
    public var longBreak: LongBreak
    public var remainderStrategy: RemainderStrategy
    public var preset: Preset

    public init(mode: Mode, longBreak: LongBreak, remainderStrategy: RemainderStrategy, preset: Preset) {
        self.mode = mode
        self.longBreak = longBreak
        self.remainderStrategy = remainderStrategy
        self.preset = preset
    }
}
