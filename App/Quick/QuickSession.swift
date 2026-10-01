import Foundation
import RipelineCore

/// The block lengths offered for a quick start, each with the break that goes before a further block.
enum QuickBlockLength: Int, CaseIterable, Codable, Sendable {
    case short = 25
    case medium = 50
    case long = 90

    var minutes: Int { rawValue }

    /// The short break added with another block: 5, 10 or 15 minutes.
    var breakMinutes: Int {
        switch self {
        case .short: 5
        case .medium: 10
        case .long: 15
        }
    }
}

/// The plan of a quick session, which starts as one block and grows a break and a block at a time.
enum QuickSession {
    /// One work block of `length` starting at `start`.
    static func plan(length: QuickBlockLength, start: Date) -> [PlannedSegment] {
        [PlannedSegment(
            index: 0, kind: .work, start: start, end: start.addingTimeInterval(TimeInterval(length.minutes) * 60)
        )]
    }

    /// A short break and then a work block, starting where `plan` ends and indexed after it. The
    /// block is as long as the plan's first one; the break comes from `QuickBlockLength`, or is five
    /// minutes if the first block is not one of those lengths. Empty for an empty plan.
    static func nextBlocks(after plan: [PlannedSegment]) -> [PlannedSegment] {
        guard let first = plan.first, let last = plan.last else { return [] }
        let blockMinutes = Int((first.duration / 60).rounded())
        let breakMinutes = QuickBlockLength(rawValue: blockMinutes)?.breakMinutes ?? 5
        let breakEnd = last.end.addingTimeInterval(TimeInterval(breakMinutes) * 60)
        return [
            PlannedSegment(index: plan.count, kind: .shortBreak, start: last.end, end: breakEnd),
            PlannedSegment(index: plan.count + 1, kind: .work, start: breakEnd, end: breakEnd.addingTimeInterval(first.duration)),
        ]
    }
}
