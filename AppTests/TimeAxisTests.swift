import Foundation
import Testing
@testable import Ripeline

struct TimeAxisTests {
    private func axis(_ dates: [Date], calendar: Calendar = utc) throws -> TimeAxis {
        try #require(TimeAxis(covering: dates, calendar: calendar))
    }

    @Test func theStageOneDay() throws {
        let a = try axis([t(9), t(17)])
        #expect(a.step == 3600)
        #expect(a.start == t(9))
        #expect(a.end == t(17))
        #expect(a.ticks.count == 9)
        #expect(a.ticks.first?.x == 0)
        #expect(a.ticks.last?.x == 1)
        #expect(abs(a.x(for: t(12, 50)) - 230.0 / 480.0) < 1e-9)
    }

    @Test func theDomainIsRoundedOutToTheStep() throws {
        let a = try axis([t(9, 7), t(11, 42)])     // 2 h 35 min wide → half-hour steps
        #expect(a.step == 1800)
        #expect(a.start == t(9))
        #expect(a.end == t(12))
    }

    @Test func aBoundaryIsKeptAsIs() throws {
        let a = try axis([t(9), t(11)])
        #expect(a.start == t(9))
        #expect(a.end == t(11))
    }

    @Test(arguments: [(4, 1800.0), (5, 3600.0), (10, 3600.0), (11, 7200.0)])
    func stepsFollowTheSpan(hours: Int, expected: Double) throws {
        #expect(try axis([t(8), t(8 + hours)]).step == expected)
    }

    @Test func aLongDayUsesTwoHourSteps() throws {
        let a = try axis([t(8), t(20)])
        #expect(a.step == 7200)
        #expect(a.ticks.map(\.date) == [t(8), t(10), t(12), t(14), t(16), t(18), t(20)])
    }

    @Test func aSingleInstantGetsOneStep() throws {
        let onTick = try axis([t(9)])
        #expect(onTick.start == t(9)); #expect(onTick.end == t(9, 30))
        let between = try axis([t(9, 20)])
        #expect(between.start == t(9)); #expect(between.end == t(9, 30))
    }

    @Test func noDatesNoAxis() {
        #expect(TimeAxis(covering: [], calendar: utc) == nil)
    }

    @Test func positionsAreClamped() throws {
        let a = try axis([t(9), t(17)])
        #expect(a.x(for: t(8)) == 0)
        #expect(a.x(for: t(18)) == 1)
    }

    @Test func ticksFallOnLocalWholeHours() throws {
        let plus3 = calendar(offsetHours: 3)
        let a = try axis([t(6), t(14)], calendar: plus3)         // 09:00–17:00 local
        #expect(a.step == 3600)
        #expect(a.start == t(6))
        #expect(a.end == t(14))
        #expect(a.ticks.count == 9)
    }

    @Test func aDayCrossingMidnightKeepsCounting() throws {
        let a = try axis([d(15, 22), d(16, 2)])
        #expect(a.step == 1800)
        #expect(a.ticks.count == 9)
        #expect(a.ticks[4].date == d(16, 0))
        #expect(zip(a.ticks, a.ticks.dropFirst()).allSatisfy { $0.date < $1.date && $0.x < $1.x })
    }

    @Test func aDaylightSavingDayStillMakesSense() throws {
        let newYork = calendar(zone: "America/New_York")
        let start = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 30))!
        let end = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 5))!
        let a = try axis([start, end], calendar: newYork)
        expectWellFormed(a, covering: [start, end])
    }

    private func expectWellFormed(_ a: TimeAxis, covering dates: [Date]) {
        #expect(a.start <= dates.min()!)
        #expect(a.end >= dates.max()!)
        #expect(a.ticks.first?.x == 0)
        #expect(a.ticks.last?.x == 1)
        #expect(zip(a.ticks, a.ticks.dropFirst()).allSatisfy { $0.date < $1.date && $0.x < $1.x })
        #expect(a.ticks.allSatisfy { $0.x >= 0 && $0.x <= 1 })
    }

    @Test func holdsForManyGeneratedSpans() {
        var seed: UInt64 = 20_260_115
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<200 {
            let from = d(15, 0).addingTimeInterval(TimeInterval(next(20 * 3600)))
            let to = from.addingTimeInterval(TimeInterval(next(14 * 3600)))
            let zone = [utc, calendar(offsetHours: 3), calendar(offsetHours: -5)][next(3)]
            guard let a = TimeAxis(covering: [from, to], calendar: zone) else { Issue.record("no axis"); return }
            expectWellFormed(a, covering: [from, to])
        }
    }
}
