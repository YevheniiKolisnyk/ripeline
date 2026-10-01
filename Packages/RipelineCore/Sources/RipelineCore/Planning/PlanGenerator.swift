import Foundation

/// Turns a `DayPlanRequest` into a fixed list of planned segments.
public enum PlanGenerator {
    /// Generates the plan for `request`.
    ///
    /// A valid request whose day is too short for any block yields an empty plan.
    public static func generate(_ request: DayPlanRequest) throws(PlanError) -> [PlannedSegment] {
        try validate(request)
        let withoutLongBreak = build(request, longBreakAfter: nil)
        for junction in longBreakCandidates(request, workBlockCount: workCount(withoutLongBreak)) {
            let plan = build(request, longBreakAfter: junction)
            // The junction only exists if a work block follows it.
            if workCount(plan) > junction { return plan }
        }
        return withoutLongBreak
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
        if case let .afterWorkBlock(block) = request.longBreak, block < 1 {
            throw .invalidLongBreakBlock
        }
        if case let .shortBlock(minMinutes) = request.remainderStrategy, minMinutes < 1 {
            throw .invalidMinimumBlock
        }
    }

    // MARK: Long break placement

    /// Junctions to try for the long break, best first. Junction `k` is the break after the
    /// k-th work block.
    ///
    /// For `.atTime` they are ordered by distance between the requested time and the end of
    /// block `k` on the nominal layout (full blocks, short breaks); the earlier junction wins a tie.
    private static func longBreakCandidates(_ request: DayPlanRequest, workBlockCount: Int) -> [Int] {
        switch request.longBreak {
        case .none:
            return []
        case let .afterWorkBlock(block):
            return [block]
        case let .atTime(target):
            return atTimeCandidates(request, target: target, workBlockCount: workBlockCount)
        }
    }

    private static func atTimeCandidates(
        _ request: DayPlanRequest, target: Date, workBlockCount: Int
    ) -> [Int] {
        let start: Date
        switch request.mode {
        case let .untilTime(modeStart, _): start = modeStart
        case let .netFocus(modeStart, _): start = modeStart
        }
        let work = TimeInterval(request.preset.workMinutes) * 60
        let shortBreak = TimeInterval(request.preset.shortBreakMinutes) * 60
        func nominalJunction(_ k: Int) -> Date {
            start.addingTimeInterval(TimeInterval(k) * work + TimeInterval(k - 1) * shortBreak)
        }
        return (1..<max(workBlockCount, 1))
            .sorted { lhs, rhs in
                let left = abs(nominalJunction(lhs).timeIntervalSince(target))
                let right = abs(nominalJunction(rhs).timeIntervalSince(target))
                return left == right ? lhs < rhs : left < right
            }
    }

    // MARK: Building

    private static func build(_ request: DayPlanRequest, longBreakAfter: Int?) -> [PlannedSegment] {
        let preset = request.preset
        let breaks = Breaks(
            short: TimeInterval(preset.shortBreakMinutes) * 60,
            long: TimeInterval(preset.longBreakMinutes) * 60,
            longAfter: longBreakAfter
        )
        let work = TimeInterval(preset.workMinutes) * 60

        switch request.mode {
        case let .untilTime(start, end):
            let durations = untilTimeDurations(
                start: start, end: end, work: work, breaks: breaks, remainder: request.remainderStrategy
            )
            return layout(start: start, work: durations, breaks: breaks)
        case let .netFocus(start, focusMinutes):
            let durations = netFocusDurations(focus: TimeInterval(focusMinutes) * 60, work: work)
            return layout(start: start, work: durations, breaks: breaks)
        }
    }

    private static func workCount(_ plan: [PlannedSegment]) -> Int {
        plan.filter { $0.kind == .work }.count
    }

    /// Break lengths, and which junction gets the long one.
    private struct Breaks {
        let short: TimeInterval
        let long: TimeInterval
        let longAfter: Int?

        func kind(afterBlock count: Int) -> SegmentKind {
            count == longAfter ? .longBreak : .shortBreak
        }

        func length(afterBlock count: Int) -> TimeInterval {
            count == longAfter ? long : short
        }
    }

    // MARK: Work block lengths

    /// Lengths of the work blocks that fit in `start..<end`, after applying the remainder strategy.
    private static func untilTimeDurations(
        start: Date, end: Date, work: TimeInterval, breaks: Breaks,
        remainder: DayPlanRequest.RemainderStrategy
    ) -> [TimeInterval] {
        var durations: [TimeInterval] = []
        var cursor = start
        func gapBeforeNextBlock() -> TimeInterval {
            durations.isEmpty ? 0 : breaks.length(afterBlock: durations.count)
        }
        while true {
            let gap = gapBeforeNextBlock()
            guard cursor.addingTimeInterval(gap + work) <= end else { break }
            durations.append(work)
            cursor = cursor.addingTimeInterval(gap + work)
        }

        switch remainder {
        case .leaveFree:
            return durations
        case let .shortBlock(minMinutes):
            let left = end.timeIntervalSince(cursor) - gapBeforeNextBlock()
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

    /// Lays the work blocks out one after another, with a break between each pair.
    private static func layout(
        start: Date, work durations: [TimeInterval], breaks: Breaks
    ) -> [PlannedSegment] {
        var segments: [PlannedSegment] = []
        var cursor = start
        func append(_ kind: SegmentKind, _ length: TimeInterval) {
            let end = cursor.addingTimeInterval(length)
            segments.append(PlannedSegment(index: segments.count, kind: kind, start: cursor, end: end))
            cursor = end
        }
        for (position, duration) in durations.enumerated() {
            if position > 0 { append(breaks.kind(afterBlock: position), breaks.length(afterBlock: position)) }
            append(.work, duration)
        }
        return segments
    }
}
