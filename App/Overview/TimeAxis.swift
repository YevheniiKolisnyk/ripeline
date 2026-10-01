import Foundation

/// The shared time axis the two timelines are drawn on: a span of time cut into whole steps.
struct TimeAxis: Equatable, Sendable {
    struct Tick: Equatable, Sendable {
        let date: Date
        /// Position on the axis, from 0 (start) to 1 (end).
        let x: Double
    }

    /// The domain, a whole number of steps wide.
    let start: Date
    let end: Date
    /// 30 minutes, an hour or two hours, by how long the span is.
    let step: TimeInterval
    /// Marks at every step; the first is at `start` (x 0), the last at `end` (x 1).
    let ticks: [Tick]

    /// An axis that covers all of `dates`, or `nil` when there are none. The start is rounded down
    /// and the end up to a multiple of the step counted from local midnight in `calendar`.
    init?(covering dates: [Date], calendar: Calendar) {
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        let step = Self.step(forSpan: latest.timeIntervalSince(earliest))
        let minutes = Int(step / 60)
        let start = Self.floor(earliest, minutes: minutes, calendar: calendar)
        var end = Self.floor(latest, minutes: minutes, calendar: calendar)
        if end < latest { end = end.addingTimeInterval(step) }
        if end <= start { end = start.addingTimeInterval(step) }
        let width = end.timeIntervalSince(start)

        var ticks: [Tick] = []
        var date = start
        while date < end {
            ticks.append(Tick(date: date, x: date.timeIntervalSince(start) / width))
            date = date.addingTimeInterval(step)
        }
        ticks.append(Tick(date: end, x: 1))

        self.start = start
        self.end = end
        self.step = step
        self.ticks = ticks
    }

    /// Where `date` falls on the axis, from 0 to 1; dates outside it are clamped.
    func x(for date: Date) -> Double {
        min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }

    /// Up to 4 hours: 30 minutes; up to 10 hours: an hour; longer: two hours.
    static func step(forSpan span: TimeInterval) -> TimeInterval {
        if span <= 4 * 3600 { return 1800 }
        if span <= 10 * 3600 { return 3600 }
        return 7200
    }

    /// `date` rounded down to a multiple of `minutes` since local midnight.
    private static func floor(_ date: Date, minutes: Int, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let sinceMidnight = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let rounded = sinceMidnight / minutes * minutes
        return calendar.date(
            bySettingHour: rounded / 60, minute: rounded % 60, second: 0, of: date, matchingPolicy: .nextTime
        ) ?? date
    }
}
