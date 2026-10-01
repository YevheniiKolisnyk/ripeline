import Foundation
import Testing
@testable import Ripeline

struct TimeOfDayTests {
    @Test(arguments: [(25, 99, 23, 59), (-1, -5, 0, 0), (9, 30, 9, 30), (0, 0, 0, 0), (23, 59, 23, 59)])
    func initClampsToAValidTime(hour: Int, minute: Int, expectedHour: Int, expectedMinute: Int) {
        let time = TimeOfDay(hour: hour, minute: minute)
        #expect(time.hour == expectedHour)
        #expect(time.minute == expectedMinute)
    }

    @Test func decodingClampsToo() throws {
        let time = try JSONDecoder().decode(TimeOfDay.self, from: Data(#"{"hour": 99, "minute": -3}"#.utf8))
        #expect(time == TimeOfDay(hour: 23, minute: 0))
    }

    @Test func roundTripsThroughJSON() throws {
        let time = TimeOfDay(hour: 17, minute: 5)
        #expect(try JSONDecoder().decode(TimeOfDay.self, from: JSONEncoder().encode(time)) == time)
    }

    @Test func putsTheTimeOnTheDayInUTC() {
        #expect(TimeOfDay(hour: 17, minute: 0).date(on: d(15, 9, 12), calendar: utc) == d(15, 17, 0))
    }

    @Test func putsTheTimeOnTheLocalDay() {
        let plus3 = calendar(offsetHours: 3)
        // 22:30 UTC on the 14th is 01:30 on the 15th in +03:00; 17:00 local that day is 14:00 UTC.
        #expect(TimeOfDay(hour: 17, minute: 0).date(on: d(14, 22, 30), calendar: plus3) == d(15, 14, 0))
    }

    @Test func readsTheWallClockTimeOfADate() {
        let plus3 = calendar(offsetHours: 3)
        #expect(TimeOfDay(date: d(15, 14, 0), calendar: plus3) == TimeOfDay(hour: 17, minute: 0))
        #expect(TimeOfDay(date: d(15, 14, 0), calendar: utc) == TimeOfDay(hour: 14, minute: 0))
    }

    @Test(arguments: [(0, 0), (23, 59), (12, 30)])
    func roundTripsThroughADate(hour: Int, minute: Int) {
        let time = TimeOfDay(hour: hour, minute: minute)
        #expect(TimeOfDay(date: time.date(on: d(15), calendar: utc), calendar: utc) == time)
    }

    // MARK: daylight saving

    @Test func aTimeThatDoesNotExistBecomesTheNextValidOne() {
        let newYork = calendar(zone: "America/New_York")
        let day = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))!   // spring forward at 02:00
        let result = TimeOfDay(hour: 2, minute: 30).date(on: day, calendar: newYork)
        let parts = newYork.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        #expect(parts.day == 8)
        #expect(parts.hour == 3)
    }

    @Test func aRepeatedTimeIsAValidInstantOnTheSameDay() {
        let newYork = calendar(zone: "America/New_York")
        let day = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!  // fall back at 02:00
        let result = TimeOfDay(hour: 1, minute: 30).date(on: day, calendar: newYork)
        let parts = newYork.dateComponents([.day, .hour, .minute], from: result)
        #expect(parts.day == 1)
        #expect(parts.hour == 1)
        #expect(parts.minute == 30)
    }

    @Test func aRepeatedTimeCanBeAskedForTheSecondOccurrence() {
        let newYork = calendar(zone: "America/New_York")
        let day = newYork.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let time = TimeOfDay(hour: 1, minute: 30)
        let first = time.date(on: day, calendar: newYork)
        let last = time.date(on: day, calendar: newYork, repeatedTimePolicy: .last)
        #expect(first == utcDate(2026, 11, 1, 5, 30))      // 01:30 EDT
        #expect(last == utcDate(2026, 11, 1, 6, 30))       // 01:30 EST, an hour later
    }
}
