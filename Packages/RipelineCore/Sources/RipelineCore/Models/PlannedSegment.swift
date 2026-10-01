import Foundation

/// One segment of the day plan. The plan is fixed once generated.
public struct PlannedSegment: Codable, Sendable, Equatable, Identifiable {
    /// Stable identity, so the UI can follow a segment across updates.
    public let id: UUID
    /// Position in the plan, starting at 0.
    public let index: Int
    /// Work, short break or long break.
    public let kind: SegmentKind
    /// When the segment is planned to start.
    public let start: Date
    /// When the segment is planned to end.
    public let end: Date

    /// Planned length in seconds.
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// `index` must equal the segment's position in its plan, and `end` must be after `start`.
    public init(id: UUID = UUID(), index: Int, kind: SegmentKind, start: Date, end: Date) {
        self.id = id
        self.index = index
        self.kind = kind
        self.start = start
        self.end = end
    }
}
