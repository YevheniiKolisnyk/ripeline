import Foundation

/// A wall-clock time without a date: what the user types for "the day ends at 17:00".
struct TimeOfDay: Codable, Equatable, Hashable, Sendable {
    let hour: Int
    let minute: Int

    /// Out-of-range values are clamped to 0–23 and 0–59.
    init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    /// The wall-clock time of `date` in `calendar`'s time zone.
    init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    private enum CodingKeys: String, CodingKey { case hour, minute }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hour: try container.decode(Int.self, forKey: .hour), minute: try container.decode(Int.self, forKey: .minute))
    }

    /// This time on the calendar day that contains `day`. A time that does not exist that day
    /// (skipped by a daylight saving change) becomes the next time that does.
    func date(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime) ?? day
    }
}
