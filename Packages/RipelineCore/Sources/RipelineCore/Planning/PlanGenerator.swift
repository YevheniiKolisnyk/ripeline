import Foundation

/// Turns a `DayPlanRequest` into a fixed list of planned segments.
public enum PlanGenerator {
    /// Generates the plan for `request`.
    ///
    /// A valid request whose day is too short for any block yields an empty plan.
    public static func generate(_ request: DayPlanRequest) throws(PlanError) -> [PlannedSegment] {
        try validate(request)
        let preset = request.preset
        let work = TimeInterval(preset.workMinutes) * 60
        let shortBreak = TimeInterval(preset.shortBreakMinutes) * 60

        switch request.mode {
        case let .untilTime(start, end):
            let durations = untilTimeDurations(
                start: start, end: end, work: work, shortBreak: shortBreak,
                remainder: request.remainderStrategy
            )
            return layout(start: start, work: durations, shortBreak: shortBreak)
        case let .netFocus(start, focusMinutes):
            let durations = netFocusDurations(focus: TimeInterval(focusMinutes) * 60, work: work)
            return layout(start: start, work: durations, shortBreak: shortBreak)
        }
    }

    // MARK: Validation

    private static func validate(_ request: DayPlanRequest) throws(PlanError) {
        let preset = request.preset
        guard preset.workMinutes > 0, preset.shortBreakMinutes > 0, preset.longBreakMinutes > 0 else {
            throw .invalidPreset
        }
        switch request.mode {
        case let .untilTime(start, end):
            guard end > start else { throw .invalidTimeRange }
        case let .netFocus(_, focusMinutes):
            guard focusMinutes > 0 else { throw .invalidFocusMinutes }
        }
        if case let .shortBlock(minMinutes) = request.remainderStrategy, minMinutes < 1 {
            throw .invalidMinimumBlock
        }
    }

    // MARK: Work block lengths

    /// Lengths of the work blocks that fit in `start..<end`, after applying the remainder strategy.
    private static func untilTimeDurations(
        start: Date, end: Date, work: TimeInterval, shortBreak: TimeInterval,
        remainder: DayPlanRequest.RemainderStrategy
    ) -> [TimeInterval] {
        var durations: [TimeInterval] = []
        var cursor = start
        while true {
            let gap = durations.isEmpty ? 0 : shortBreak
            guard cursor.addingTimeInterval(gap + work) <= end else { break }
            durations.append(work)
            cursor = cursor.addingTimeInterval(gap + work)
        }

        switch remainder {
        case .leaveFree:
            return durations
        case let .shortBlock(minMinutes):
            let gap = durations.isEmpty ? 0 : shortBreak
            let left = end.timeIntervalSince(cursor) - gap
            if left >= TimeInterval(minMinutes) * 60 {
                durations.append(left)
            }
            return durations
        case .stretchBlocks:
            guard !durations.isEmpty else { return [] }
            return stretch(durations, extra: end.timeIntervalSince(cursor))
        }
    }

    /// Spreads `extra` seconds over `durations` in whole minutes, earliest blocks first.
    /// Any sub-minute residue goes to the last block.
    private static func stretch(_ durations: [TimeInterval], extra: TimeInterval) -> [TimeInterval] {
        let wholeMinutes = Int(extra / 60)
        let residue = extra - TimeInterval(wholeMinutes) * 60
        let share = wholeMinutes / durations.count
        let leftover = wholeMinutes % durations.count
        var result = durations.enumerated().map { index, duration in
            duration + TimeInterval(share + (index < leftover ? 1 : 0)) * 60
        }
        result[result.count - 1] += residue
        return result
    }

    /// `ceil(focus / work)` blocks; the last one carries whatever focus is left.
    private static func netFocusDurations(focus: TimeInterval, work: TimeInterval) -> [TimeInterval] {
        let fullBlocks = Int(focus / work)
        var durations = [TimeInterval](repeating: work, count: fullBlocks)
        let rest = focus - TimeInterval(fullBlocks) * work
        if rest > 0 { durations.append(rest) }
        return durations
    }

    // MARK: Layout

    /// Lays the work blocks out one after another, with a short break between each pair.
    private static func layout(
        start: Date, work durations: [TimeInterval], shortBreak: TimeInterval
    ) -> [PlannedSegment] {
        var segments: [PlannedSegment] = []
        var cursor = start
        func append(_ kind: SegmentKind, _ length: TimeInterval) {
            let end = cursor.addingTimeInterval(length)
            segments.append(PlannedSegment(index: segments.count, kind: kind, start: cursor, end: end))
            cursor = end
        }
        for (position, duration) in durations.enumerated() {
            if position > 0 { append(.shortBreak, shortBreak) }
            append(.work, duration)
        }
        return segments
    }
}
