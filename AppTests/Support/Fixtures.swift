import Foundation
import RipelineCore
import Testing

/// A fixed calendar so tests never depend on the machine's time zone or locale.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

/// A time on 2026-01-`day`, UTC. `fraction` adds sub-second precision.
func d(_ day: Int, _ hour: Int = 9, _ minute: Int = 0, _ second: Int = 0, fraction: Double = 0) -> Date {
    let start = DateComponents(calendar: utc, year: 2026, month: 1, day: day).date!
    return start.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second) + fraction)
}

/// A time on the default test day, 2026-01-15.
func t(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date { d(15, hour, minute, second) }

func minutes(_ value: Int) -> TimeInterval { TimeInterval(value * 60) }

/// Builds a contiguous plan by hand.
func makePlan(start: Date = t(9), _ items: [(SegmentKind, Int)]) -> [PlannedSegment] {
    var cursor = start
    return items.enumerated().map { index, item in
        let end = cursor.addingTimeInterval(minutes(item.1))
        defer { cursor = end }
        return PlannedSegment(index: index, kind: item.0, start: cursor, end: end)
    }
}

/// Work 50, break 10, work 50, break 10, work 50: 09:00–11:50 on the start day.
func fivePlan(start: Date = t(9)) -> [PlannedSegment] {
    makePlan(start: start, [(.work, 50), (.shortBreak, 10), (.work, 50), (.shortBreak, 10), (.work, 50)])
}

/// A snapshot of a day that is loaded but not started.
func idleSnapshot(plan: [PlannedSegment] = fivePlan(), settings: SessionSettings = SessionSettings()) throws -> SessionSnapshot {
    var engine = SessionEngine(clock: TestClock(plan[0].start))
    try engine.startDay(plan: plan, settings: settings)
    return engine.snapshot
}

/// A snapshot of a day whose first segment started at the plan's start.
func startedSnapshot(plan: [PlannedSegment] = fivePlan(), settings: SessionSettings = SessionSettings()) throws -> SessionSnapshot {
    var engine = SessionEngine(clock: TestClock(plan[0].start))
    try engine.startDay(plan: plan, settings: settings)
    try engine.start()
    return engine.snapshot
}

/// Re-encodes `snapshot` through JSON after letting `edit` change the raw object, to build
/// snapshots the engine itself would never produce.
func tamperedSnapshot(_ snapshot: SessionSnapshot, edit: (inout [String: Any]) -> Void) throws -> SessionSnapshot {
    let data = try JSONEncoder().encode(snapshot)
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    edit(&object)
    return try JSONDecoder().decode(SessionSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
}
