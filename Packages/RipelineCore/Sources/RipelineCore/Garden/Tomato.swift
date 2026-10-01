import Foundation

/// Whether a work block's tomato can be picked.
public enum TomatoAvailability: Sendable, Equatable {
    /// The block has not started, and its day is not over.
    case upcoming
    /// The block is running or paused: the tomato is still growing.
    case growing
    /// The block is over, or waits in overtime, and some work was recorded in it.
    case pickable
    /// The block is over, or its day ended before it started, and no work was recorded in it.
    case empty
}

/// The tomato of one work block. It is derived from the record, never stored.
public struct Tomato: Sendable, Equatable, Identifiable {
    /// The id of the work segment, stable across relaunches.
    public let id: UUID
    /// The segment's position in the plan.
    public let segmentIndex: Int
    /// Seconds of recorded work in the block, including extensions and overtime.
    public let workTime: TimeInterval
    /// The planned length of the block, in seconds.
    public let plannedTime: TimeInterval
    /// Whether it can be picked.
    public let availability: TomatoAvailability

    /// How grown it is: 1.0 is 100% (the planned length worked); more than 1 is work beyond the plan.
    public var growth: Double { workTime / plannedTime }

    /// A tomato of the given figures; `plannedTime` must be positive.
    public init(id: UUID, segmentIndex: Int, workTime: TimeInterval, plannedTime: TimeInterval, availability: TomatoAvailability) {
        self.id = id
        self.segmentIndex = segmentIndex
        self.workTime = workTime
        self.plannedTime = plannedTime
        self.availability = availability
    }
}

/// Derives the tomatoes of a day from its record.
public enum Tomatoes {
    /// One tomato per work segment, in plan order, as of `now`. The day is first caught up with `now`
    /// and the interval being recorded counts up to it. Paused and untracked time is not work; breaks
    /// give no tomato.
    ///
    /// - Parameter settled: The day is stored and no longer runs, for example because the app was closed in
    ///   the middle of a block. A block that was still active counts as over, and one that never started
    ///   gives nothing, so every tomato of the day can be picked.
    public static func of(_ snapshot: SessionSnapshot, at now: Date, settled: Bool = false) -> [Tomato] {
        var current = snapshot
        current.catchUp(to: now)
        let actuals = current.actuals(at: now)
        var overtimeIndex: Int?
        if case let .overtime(index, _) = current.state { overtimeIndex = index }
        let dayIsOver = settled || current.state == .finished

        var result: [Tomato] = []
        for segment in current.plan where segment.kind == .work {
            let actual = actuals[segment.index]
            var work: TimeInterval = 0
            for interval in actual.intervals where interval.kind == .work { work += interval.duration }
            let availability: TomatoAvailability
            switch actual.status {
            case .notStarted:
                availability = dayIsOver ? .empty : .upcoming
            case .active:
                if settled {
                    availability = work > 0 ? .pickable : .empty
                } else {
                    availability = segment.index == overtimeIndex && work > 0 ? .pickable : .growing
                }
            case .completed, .skipped:
                availability = work > 0 ? .pickable : .empty
            }
            result.append(Tomato(
                id: segment.id, segmentIndex: segment.index, workTime: work,
                plannedTime: segment.duration, availability: availability
            ))
        }
        return result
    }
}

extension SessionEngine {
    /// The tomatoes of the day as of the current time, like `timeline()`.
    public func tomatoes() -> [Tomato] {
        Tomatoes.of(snapshot, at: currentInstant())
    }
}
