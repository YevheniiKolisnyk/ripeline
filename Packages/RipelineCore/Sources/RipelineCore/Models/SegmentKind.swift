import Foundation

/// What a planned segment is for.
public enum SegmentKind: String, Codable, Sendable, Equatable, CaseIterable {
    case work
    case shortBreak
    case longBreak

    /// `true` for both kinds of break.
    public var isBreak: Bool { self != .work }
}
