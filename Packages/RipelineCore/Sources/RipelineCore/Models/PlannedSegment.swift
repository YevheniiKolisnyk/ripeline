import Foundation

/// One segment of the day plan. The plan is fixed once generated.
public struct PlannedSegment: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    /// Position in the plan, starting at 0.
    public let index: Int
    public let kind: SegmentKind
    public let start: Date
    public let end: Date

    /// Planned length in seconds.
    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public init(id: UUID = UUID(), index: Int, kind: SegmentKind, start: Date, end: Date) {
        self.id = id
        self.index = index
        self.kind = kind
        self.start = start
        self.end = end
    }
}
