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

/// A Gregorian calendar fixed at a UTC offset.
func calendar(offsetHours: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: offsetHours * 3600)!
    return calendar
}

/// A Gregorian calendar in a named time zone, for daylight saving tests.
func calendar(zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

/// The plan 2a's quick start produced: net focus of four hours, 50/10/45, no long break.
func standardRequest(at now: Date) -> DayPlanRequest {
    DayPlanRequest(
        mode: .netFocus(start: now, focusMinutes: 240), longBreak: .none, remainderStrategy: .leaveFree,
        preset: Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45)
    )
}

/// An instant given in UTC, for dates outside the test day.
func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    DateComponents(calendar: utc, year: year, month: month, day: day, hour: hour, minute: minute).date!
}

/// A day played on a real engine and returned as a snapshot. `script` receives the engine and the
/// clock, which starts at the plan's first segment.
func playedDay(
    plan: [PlannedSegment] = fivePlan(), settings: SessionSettings = SessionSettings(), kind: SessionKind = .day,
    _ script: (inout SessionEngine, TestClock) throws -> Void
) throws -> SessionSnapshot {
    let clock = TestClock(plan[0].start)
    var engine = SessionEngine(clock: clock)
    try engine.startDay(plan: plan, settings: settings, kind: kind)
    try script(&engine, clock)
    return engine.snapshot
}

/// A day on `fivePlan(start:)` started at its start and ended thirty minutes later.
func finishedDay(start: Date = t(9)) throws -> SessionSnapshot {
    try playedDay(plan: fivePlan(start: start)) { engine, clock in
        try engine.start()
        clock.set(start.addingTimeInterval(1800))
        try engine.endDay()
    }
}

/// A day started at `start`, paused for five minutes after half an hour, and left running: never ended.
func abandonedDay(start: Date = t(9)) throws -> SessionSnapshot {
    try playedDay(plan: fivePlan(start: start)) { engine, clock in
        try engine.start()
        clock.set(start.addingTimeInterval(1800)); try engine.pause()
        clock.set(start.addingTimeInterval(2100)); try engine.resume()
    }
}

/// A day with two worked blocks of 25 minutes (09:00 and 09:30 from `start`), ended after the second.
/// Both tomatoes are pickable and fully grown. Plan indices 0 and 2 are the work blocks.
func twoTomatoDay(start: Date = t(9)) throws -> SessionSnapshot {
    try playedDay(plan: makePlan(start: start, [(.work, 25), (.shortBreak, 5), (.work, 25)])) { engine, clock in
        try engine.start()
        clock.set(start.addingTimeInterval(minutes(25))); try engine.skip()      // the first block, done
        clock.set(start.addingTimeInterval(minutes(30))); try engine.advance()   // the break ran out; on to the second
        clock.set(start.addingTimeInterval(minutes(55))); try engine.endDay()
    }
}
