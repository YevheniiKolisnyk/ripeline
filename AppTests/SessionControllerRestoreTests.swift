import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerRestoreTests {
    @Test func emptyStoreStartsIdle() {
        let h = Harness(); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .idle)
        #expect(h.controller.currentSegment == nil)
        #expect(h.store.saved.isEmpty)
    }

    @Test func runningDayContinues() throws {
        let h = Harness(now: t(9, 20), stored: try startedSnapshot()); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .working)
        #expect(h.controller.remaining == minutes(30))
        #expect(h.controller.currentSegment?.index == 0)
    }

    @Test func segmentsThatEndedWhileTheAppWasClosedAreAccountedFor() throws {
        let h = Harness(now: t(9, 55), stored: try startedSnapshot()); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .overtime(onBreak: false))
        #expect(h.controller.overtimeElapsed == minutes(5))
    }

    @Test func autoAdvanceIsAppliedOnRestore() throws {
        let settings = SessionSettings(autoAdvanceWorkToBreak: true, autoAdvanceBreakToWork: true)
        let h = Harness(now: t(11, 15), stored: try startedSnapshot(settings: settings)); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .working)
        #expect(h.controller.currentSegment?.index == 4)
    }

    @Test func aFinishedDayStartsFreshAndLeavesTheFileAlone() throws {
        let h = Harness(now: t(12), stored: try finishedSnapshot()); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .idle)
        #expect(h.controller.plan.isEmpty)
        #expect(h.store.saved.isEmpty)
        #expect(h.store.quarantined.isEmpty)
    }

    @Test func aPlanThatEndedYesterdayStartsFresh() throws {
        let yesterday = try startedSnapshot(plan: fivePlan(start: d(14, 20, 0)))   // ends 22:50 on the 14th
        let h = Harness(now: d(15, 7), stored: yesterday); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .idle)
        #expect(h.controller.plan.isEmpty)
    }

    @Test func aDayCrossingMidnightStaysActive() throws {
        let overnight = try startedSnapshot(plan: fivePlan(start: d(14, 22, 0)))   // ends 00:50 on the 15th
        let h = Harness(now: d(15, 0, 30), stored: overnight); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase != .idle)
        #expect(h.controller.plan.count == 5)
    }

    @Test func anUnstartedPlanForTodayIsRestored() throws {
        let h = Harness(now: t(9), stored: try idleSnapshot()); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .idle)
        #expect(h.controller.plan.count == 5)
    }

    @Test func aSnapshotThatFailsValidationIsSetAsideAndTheAppStartsFresh() throws {
        let broken = try tamperedSnapshot(try startedSnapshot()) { object in
            object["actuals"] = Array((object["actuals"] as? [Any] ?? []).dropLast())
        }
        let h = Harness(now: t(9, 20), stored: broken); defer { h.cleanUp() }
        h.controller.restore()
        #expect(h.controller.phase == .idle)
        #expect(h.store.quarantined.count == 1)
        #expect(h.store.quarantined.first?.snapshot == broken)
    }

    @Test func aFailingStoreStartsFresh() throws {
        let h = Harness(); defer { h.cleanUp() }
        h.store.failLoad = true
        h.controller.restore()
        #expect(h.controller.phase == .idle)
    }

    @Test func todayFollowsTheCalendarTimeZone() throws {
        var plus3 = Calendar(identifier: .gregorian)
        plus3.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        // The plan ends at 23:00 UTC on the 14th = 02:00 on the 15th in +03:00.
        let snapshot = try startedSnapshot(plan: fivePlan(start: d(14, 20, 10)))
        let morning = d(15, 4, 0)    // 04:00 UTC = 07:00 local on the 15th

        let inPlus3 = Harness(now: morning, stored: snapshot, calendar: plus3); defer { inPlus3.cleanUp() }
        inPlus3.controller.restore()
        #expect(inPlus3.controller.phase != .idle)

        let inUTC = Harness(now: morning, stored: snapshot, calendar: utc); defer { inUTC.cleanUp() }
        inUTC.controller.restore()
        #expect(inUTC.controller.phase == .idle)
    }
}
