import Foundation
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
