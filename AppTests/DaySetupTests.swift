import Foundation
import RipelineCore
import Testing
@testable import Ripeline

struct DaySetupTests {
    private func form(_ edit: (inout DayPlanForm) -> Void = { _ in }) -> DayPlanForm {
        var form = DayPlanForm.standard
        edit(&form)
        return form
    }

    private func ready(_ result: DaySetupResult) throws -> (request: DayPlanRequest, preview: DayPreview, notices: [DaySetupNotice]) {
        guard case let .ready(request, preview, notices) = result else {
            Issue.record("expected a ready result, got \(result)")
            throw CancellationError()
        }
        return (request, preview, notices)
    }

    private func kinds(_ preview: DayPreview) -> [SegmentKind] { preview.segments.map(\.kind) }

    // MARK: the stage 1 day

    @Test func theDayFromTheCoreSpecification() throws {
        let f = form {
            $0.longBreak = .atTime(TimeOfDay(hour: 13, minute: 0))
            $0.remainder = .shortBlock
            $0.minBlockMinutes = 15
        }
        let (request, preview, notices) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(request == DayPlanRequest(
            mode: .untilTime(start: t(9), end: t(17)), longBreak: .atTime(t(13)),
            remainderStrategy: .shortBlock(minMinutes: 15),
            preset: Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45)
        ))
        let longBreak = try #require(preview.segments.first { $0.kind == .longBreak })
        #expect(longBreak.start == t(12, 50))
        #expect(longBreak.end == t(13, 35))
        #expect(preview.focus == minutes(375))
        #expect(preview.rest == minutes(105))
        #expect(preview.endsAt == t(17))
        #expect(preview.freeRemainder == 0)
        #expect(notices.isEmpty)
    }

    // MARK: remainder and notices

    @Test func leavingTheRemainderFreeIsReported() throws {
        let f = form { $0.remainder = .leaveFree }
        let (_, preview, notices) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(preview.segments.filter { $0.kind == .work }.count == 8)
        #expect(preview.endsAt == t(16, 50))
        #expect(preview.freeRemainder == minutes(10))
        #expect(notices == [.remainderLeftFree(minutes: 10)])
    }

    @Test func stretchingFillsTheDay() throws {
        let f = form { $0.endTime = TimeOfDay(hour: 17, minute: 30); $0.remainder = .stretchBlocks }
        let (_, preview, notices) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(preview.endsAt == t(17, 30))
        #expect(preview.freeRemainder == 0)
        #expect(notices.isEmpty)
    }

    @Test func aLongBreakThatDoesNotFitIsReported() throws {
        let f = form {
            $0.endTime = TimeOfDay(hour: 11, minute: 0)
            $0.longBreak = .atTime(TimeOfDay(hour: 10, minute: 0))
            $0.remainder = .leaveFree
        }
        let (_, preview, notices) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(!kinds(preview).contains(.longBreak))
        #expect(notices == [.longBreakNotPlaced, .remainderLeftFree(minutes: 10)])
    }

    @Test func aLongBreakAfterABlock() throws {
        let f = form { $0.longBreak = .afterBlock(2) }
        let (request, preview, _) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(request.longBreak == .afterWorkBlock(2))
        #expect(Array(kinds(preview).prefix(4)) == [.work, .shortBreak, .work, .longBreak])
    }

    // MARK: net focus

    @Test func netFocusShortensTheLastBlock() throws {
        let f = form { $0.mode = .netFocus; $0.focusMinutes = 120 }
        let (_, preview, notices) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(preview.segments.map(\.duration) == [3000, 600, 3000, 600, 1200])
        #expect(preview.focus == minutes(120))
        #expect(preview.rest == minutes(20))
        #expect(preview.endsAt == t(11, 20))
        #expect(preview.freeRemainder == 0)
        #expect(notices.isEmpty)
    }

    @Test(arguments: RemainderChoice.allCases)
    func theRemainderChoiceHasNoEffectInNetFocus(remainder: RemainderChoice) throws {
        let base = form { $0.mode = .netFocus; $0.focusMinutes = 120; $0.remainder = .leaveFree }
        let other = form { $0.mode = .netFocus; $0.focusMinutes = 120; $0.remainder = remainder }
        let a = try ready(DaySetup.evaluate(form: base, now: t(9), calendar: utc)).preview
        let b = try ready(DaySetup.evaluate(form: other, now: t(9), calendar: utc)).preview
        #expect(a.segments.map(\.duration) == b.segments.map(\.duration))
        #expect(a.endsAt == b.endsAt)
    }

    @Test func netFocusIgnoresTheStoredEndTime() throws {
        let f = form { $0.mode = .netFocus; $0.focusMinutes = 60; $0.endTime = TimeOfDay(hour: 8, minute: 0) }
        _ = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
    }

    // MARK: issues

    @Test(arguments: [t(17), t(17, 30), t(23)])
    func anEndNotAfterNowIsAnIssue(now: Date) {
        #expect(DaySetup.evaluate(form: form(), now: now, calendar: utc) == .invalid(.endNotAfterNow))
    }

    @Test func aDayTooShortForABlockIsAnIssue() {
        let f = form { $0.remainder = .leaveFree }
        #expect(DaySetup.evaluate(form: f, now: t(16, 30), calendar: utc) == .invalid(.dayTooShort))
    }

    @Test func aShortBlockRescuesAShortDay() throws {
        let f = form { $0.remainder = .shortBlock; $0.minBlockMinutes = 15 }
        let (_, preview, _) = try ready(DaySetup.evaluate(form: f, now: t(16, 30), calendar: utc))
        #expect(preview.segments.map(\.duration) == [1800])
    }

    // MARK: presets and clamping

    @Test func aCustomPresetIsUsed() throws {
        let f = form {
            $0.presetChoice = .custom
            $0.customPreset = Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15)
        }
        let (request, preview, _) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(request.preset == Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15))
        #expect(preview.segments[0].duration == 1500)
    }

    @Test func outOfRangeInputIsClampedNotRejected() throws {
        let f = form {
            $0.presetChoice = .custom
            $0.customPreset = Preset(workMinutes: 0, shortBreakMinutes: 10, longBreakMinutes: 45)
            $0.longBreak = .afterBlock(99)
        }
        let (request, _, _) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(request.preset.workMinutes == 1)
        #expect(request.longBreak == .afterWorkBlock(20))
    }

    // MARK: time zones, midnight and daylight saving (Review Focus 1)

    @Test func theEndTimeIsInTheCalendarsTimeZone() throws {
        // 22:30 UTC on the 14th is 01:30 on the 15th at +03:00; 17:00 there is 14:00 UTC.
        let (request, _, _) = try ready(DaySetup.evaluate(form: form(), now: d(14, 22, 30), calendar: calendar(offsetHours: 3)))
        guard case let .untilTime(start, end) = request.mode else { Issue.record("not untilTime"); return }
        #expect(start == d(14, 22, 30))
        #expect(end == d(15, 14, 0))
    }

    @Test func aMinuteBeforeMidnightIsTooShort() {
        let f = form { $0.endTime = TimeOfDay(hour: 23, minute: 59); $0.remainder = .leaveFree }
        #expect(DaySetup.evaluate(form: f, now: t(23, 58), calendar: utc) == .invalid(.dayTooShort))
    }

    @Test func midnightIsNeverTomorrow() {
        let f = form { $0.endTime = TimeOfDay(hour: 0, minute: 0) }
        #expect(DaySetup.evaluate(form: f, now: t(23, 58), calendar: utc) == .invalid(.endNotAfterNow))
    }

    @Test func anEndTimeSkippedByDaylightSavingBecomesTheNextValidTime() throws {
        let newYork = calendar(zone: "America/New_York")
        let now = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 1))!
        let f = form { $0.endTime = TimeOfDay(hour: 2, minute: 30); $0.remainder = .shortBlock; $0.minBlockMinutes = 15 }
        let (request, preview, _) = try ready(DaySetup.evaluate(form: f, now: now, calendar: newYork))
        guard case let .untilTime(_, end) = request.mode else { Issue.record("not untilTime"); return }
        let parts = newYork.dateComponents([.day, .hour], from: end)
        #expect(parts.day == 8)
        #expect(parts.hour == 3)
        #expect(!preview.segments.isEmpty)
    }

    // MARK: minor findings

    /// The second pass through the repeated hour: 01:45 EST with an end of 01:50 is five minutes away.
    @Test func theSecondPassThroughARepeatedHourStillHasItsEndAhead() throws {
        let newYork = calendar(zone: "America/New_York")
        let now = utcDate(2026, 11, 1, 6, 45)               // 01:45 EST, the second 01:45
        let f = form { $0.endTime = TimeOfDay(hour: 1, minute: 50); $0.remainder = .shortBlock; $0.minBlockMinutes = 1 }
        let (request, _, _) = try ready(DaySetup.evaluate(form: f, now: now, calendar: newYork))
        guard case let .untilTime(_, end) = request.mode else { Issue.record("not untilTime"); return }
        #expect(end == utcDate(2026, 11, 1, 6, 50))
    }

    @Test func aLongBreakTimeThatHasPassedIsReported() throws {
        let f = form { $0.longBreak = .atTime(TimeOfDay(hour: 13, minute: 0)); $0.remainder = .leaveFree }
        let (_, preview, notices) = try ready(DaySetup.evaluate(form: f, now: t(14), calendar: utc))
        #expect(notices.contains(.longBreakTimePassed))
        #expect(kinds(preview).contains(.longBreak))        // the core still places it at the nearest break
    }

    @Test func aLongBreakTimeStillAheadIsNotReported() throws {
        let f = form { $0.longBreak = .atTime(TimeOfDay(hour: 13, minute: 0)) }
        let (_, _, notices) = try ready(DaySetup.evaluate(form: f, now: t(9), calendar: utc))
        #expect(!notices.contains(.longBreakTimePassed))
    }
}
