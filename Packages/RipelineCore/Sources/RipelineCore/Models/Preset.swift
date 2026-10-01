import Foundation

/// Durations, in whole minutes, of the three kinds of segment in a day.
public struct Preset: Codable, Sendable, Equatable, Hashable {
    /// Length of a work block.
    public var workMinutes: Int
    /// Length of the break between two work blocks.
    public var shortBreakMinutes: Int
    /// Length of the long break, which replaces one short break.
    public var longBreakMinutes: Int

    /// All three values must be positive for `PlanGenerator` to accept the preset.
    public init(workMinutes: Int, shortBreakMinutes: Int, longBreakMinutes: Int) {
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
    }
}
