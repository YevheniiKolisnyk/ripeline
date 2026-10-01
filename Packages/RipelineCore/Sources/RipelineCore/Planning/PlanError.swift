import Foundation

/// Why a `DayPlanRequest` cannot be turned into a plan.
public enum PlanError: Error, Sendable, Equatable {
    /// A preset duration is zero or negative.
    case invalidPreset
    /// The end of the day is not after its start.
    case invalidTimeRange
    /// The focus target is zero or negative.
    case invalidFocusMinutes
    /// `afterWorkBlock(n)` with `n < 1`.
    case invalidLongBreakBlock
    /// `shortBlock(minMinutes:)` with a minimum below one minute.
    case invalidMinimumBlock
}
