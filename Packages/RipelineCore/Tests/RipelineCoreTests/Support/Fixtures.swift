import Foundation
import Testing
@testable import RipelineCore

/// Fixed calendar so tests never depend on the machine's time zone or locale.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

/// The day every test runs on: 2026-01-15, UTC.
let testDay = DateComponents(calendar: testCalendar, year: 2026, month: 1, day: 15).date!

/// A time of day on the test day. Hours past 24 roll into the next day.
func t(_ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
    testDay.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60 + second))
}

/// Preset used throughout the tests: 50 min work, 10 min break, 45 min long break.
let presetP = Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45)

/// Length of `minutes` in seconds.
func minutes(_ value: Int) -> TimeInterval { TimeInterval(value * 60) }

/// A plain, comparable view of a planned segment (ignores `id` and `index`).
struct Block: Equatable, CustomStringConvertible {
    let kind: SegmentKind
    let start: Date
    let end: Date

    var description: String { "\(kind) \(start.formatted(.iso8601.time(includingFractionalSeconds: false)))–\(end.formatted(.iso8601.time(includingFractionalSeconds: false)))" }
}

func blocks(_ plan: [PlannedSegment]) -> [Block] {
    plan.map { Block(kind: $0.kind, start: $0.start, end: $0.end) }
}

func work(_ start: Date, _ end: Date) -> Block { Block(kind: .work, start: start, end: end) }
func shortBreak(_ start: Date, _ end: Date) -> Block { Block(kind: .shortBreak, start: start, end: end) }
func longBreak(_ start: Date, _ end: Date) -> Block { Block(kind: .longBreak, start: start, end: end) }

/// Total planned work time of `plan`, in minutes.
func focusMinutes(_ plan: [PlannedSegment]) -> Double {
    plan.filter { $0.kind == .work }.reduce(0) { $0 + $1.duration } / 60
}

/// Structural invariants every generated plan must satisfy.
func expectWellFormed(_ plan: [PlannedSegment], sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(plan.map(\.index) == Array(0..<plan.count), sourceLocation: sourceLocation)
    #expect(Set(plan.map(\.id)).count == plan.count, sourceLocation: sourceLocation)
    for (previous, next) in zip(plan, plan.dropFirst()) {
        #expect(next.start == previous.end, sourceLocation: sourceLocation)
        #expect(previous.kind.isBreak != next.kind.isBreak, sourceLocation: sourceLocation)
    }
    #expect(plan.allSatisfy { $0.duration > 0 }, sourceLocation: sourceLocation)
    #expect(plan.last.map { $0.kind == .work } ?? true, sourceLocation: sourceLocation)
}
