import Foundation

/// User settings that change how a session behaves.
public struct SessionSettings: Codable, Sendable, Equatable {
    /// Paused time is recorded as rest (`true`) or as untracked time (`false`).
    public var pausesCountAsRest: Bool
    /// When a work segment runs out, start the following break by itself.
    public var autoAdvanceWorkToBreak: Bool
    /// When a break runs out, start the following work block by itself.
    public var autoAdvanceBreakToWork: Bool

    public init(
        pausesCountAsRest: Bool = true,
        autoAdvanceWorkToBreak: Bool = false,
        autoAdvanceBreakToWork: Bool = false
    ) {
        self.pausesCountAsRest = pausesCountAsRest
        self.autoAdvanceWorkToBreak = autoAdvanceWorkToBreak
        self.autoAdvanceBreakToWork = autoAdvanceBreakToWork
    }
}
