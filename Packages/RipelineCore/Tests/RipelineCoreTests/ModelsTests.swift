import Foundation
import Testing
@testable import RipelineCore

struct ModelsTests {
    @Test func settingsDefaults() {
        let settings = SessionSettings()
        #expect(settings.pausesCountAsRest == true)
        #expect(settings.autoAdvanceWorkToBreak == false)
        #expect(settings.autoAdvanceBreakToWork == false)
    }

    @Test(arguments: [
        (SegmentKind.work, false),
        (SegmentKind.shortBreak, true),
        (SegmentKind.longBreak, true),
    ])
    func isBreak(kind: SegmentKind, expected: Bool) {
        #expect(kind.isBreak == expected)
    }

    @Test func plannedSegmentDuration() {
        let segment = PlannedSegment(index: 0, kind: .work, start: t(9), end: t(9, 50))
        #expect(segment.duration == 3000)
    }

    @Test(arguments: allRequests())
    func requestRoundTripsThroughJSON(request: DayPlanRequest) throws {
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(DayPlanRequest.self, from: data)
        #expect(decoded == request)
    }

    @Test func plannedSegmentRoundTripsThroughJSON() throws {
        let segment = PlannedSegment(index: 3, kind: .longBreak, start: t(12, 50), end: t(13, 35))
        let data = try JSONEncoder().encode(segment)
        #expect(try JSONDecoder().decode(PlannedSegment.self, from: data) == segment)
    }
}

private func allRequests() -> [DayPlanRequest] {
    let modes: [DayPlanRequest.Mode] = [
        .untilTime(start: t(9), end: t(17)),
        .netFocus(start: t(9), focusMinutes: 300),
    ]
    let longBreaks: [DayPlanRequest.LongBreak] = [.none, .atTime(t(13)), .afterWorkBlock(3)]
    let remainders: [DayPlanRequest.RemainderStrategy] = [
        .shortBlock(minMinutes: 15), .leaveFree, .stretchBlocks,
    ]
    var result: [DayPlanRequest] = []
    for mode in modes {
        for longBreak in longBreaks {
            for remainder in remainders {
                result.append(DayPlanRequest(
                    mode: mode, longBreak: longBreak, remainderStrategy: remainder, preset: presetP
                ))
            }
        }
    }
    return result
}
