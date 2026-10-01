import Foundation

/// Durations, in whole minutes, of the three kinds of segment in a day.
public struct Preset: Codable, Sendable, Equatable, Hashable {
    public var workMinutes: Int
    public var shortBreakMinutes: Int
    public var longBreakMinutes: Int

    public init(workMinutes: Int, shortBreakMinutes: Int, longBreakMinutes: Int) {
        self.workMinutes = workMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
    }
}
