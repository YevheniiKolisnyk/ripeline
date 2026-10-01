import Foundation

/// Where a planned segment stands.
public enum SegmentStatus: String, Codable, Sendable, Equatable {
    case notStarted
    case active
    case completed
    case skipped
}

/// What actually happened in one planned segment.
public struct SegmentActual: Codable, Sendable, Equatable {
    /// Where the segment stands.
    public internal(set) var status: SegmentStatus
    /// Closed intervals in chronological order. The interval being recorded right now is
    /// held by `SessionSnapshot.openInterval` until it closes.
    public internal(set) var intervals: [ActualInterval]

    public init(status: SegmentStatus = .notStarted, intervals: [ActualInterval] = []) {
        self.status = status
        self.intervals = intervals
    }
}
