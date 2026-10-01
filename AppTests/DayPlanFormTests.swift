import Foundation
import RipelineCore
import Testing
@testable import Ripeline

struct DayPlanFormTests {
    @Test func standardValues() {
        let form = DayPlanForm.standard
        #expect(form.presetChoice == .builtIn(.deepWork))
        #expect(form.customPreset == Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45))
        #expect(form.mode == .untilTime)
        #expect(form.endTime == TimeOfDay(hour: 17, minute: 0))
        #expect(form.focusMinutes == 240)
        #expect(form.longBreak == .none)
        #expect(form.remainder == .shortBlock)
        #expect(form.minBlockMinutes == 15)
    }

    @Test(arguments: [
        (BuiltInPreset.classic, Preset(workMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15)),
        (.deepWork, Preset(workMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 45)),
        (.longBlocks, Preset(workMinutes: 90, shortBreakMinutes: 15, longBreakMinutes: 30)),
    ])
    func builtInPresets(preset: BuiltInPreset, expected: Preset) {
        #expect(preset.preset == expected)
    }

    @Test func thePresetFollowsTheChoice() {
        var form = DayPlanForm.standard
        form.customPreset = Preset(workMinutes: 30, shortBreakMinutes: 7, longBreakMinutes: 20)
        form.presetChoice = .builtIn(.classic)
        #expect(form.preset == BuiltInPreset.classic.preset)
        form.presetChoice = .custom
        #expect(form.preset == Preset(workMinutes: 30, shortBreakMinutes: 7, longBreakMinutes: 20))
    }

    // MARK: normalization

    private func normalized(_ edit: (inout DayPlanForm) -> Void) -> DayPlanForm {
        var form = DayPlanForm.standard
        edit(&form)
        return form.normalized()
    }

    @Test func clampsTheCustomPreset() {
        let low = normalized { $0.customPreset = Preset(workMinutes: 0, shortBreakMinutes: -4, longBreakMinutes: 0) }
        #expect(low.customPreset == Preset(workMinutes: 1, shortBreakMinutes: 1, longBreakMinutes: 1))
        let high = normalized { $0.customPreset = Preset(workMinutes: 999, shortBreakMinutes: 500, longBreakMinutes: 500) }
        #expect(high.customPreset == Preset(workMinutes: 240, shortBreakMinutes: 120, longBreakMinutes: 120))
    }

    @Test(arguments: [(7, 15), (15, 15), (100, 100), (720, 720), (1000, 720), (-5, 15)])
    func clampsFocusMinutes(value: Int, expected: Int) {
        #expect(normalized { $0.focusMinutes = value }.focusMinutes == expected)
    }

    @Test(arguments: [(0, 1), (1, 1), (7, 7), (20, 20), (99, 20), (-3, 1)])
    func clampsTheLongBreakBlockNumber(value: Int, expected: Int) {
        #expect(normalized { $0.longBreak = .afterBlock(value) }.longBreak == .afterBlock(expected))
    }

    @Test(arguments: [(0, 1), (15, 15), (500, 120)])
    func clampsTheMinimumBlock(value: Int, expected: Int) {
        #expect(normalized { $0.minBlockMinutes = value }.minBlockMinutes == expected)
    }

    @Test func aValidFormIsUnchanged() {
        var form = DayPlanForm.standard
        form.presetChoice = .custom
        form.longBreak = .atTime(TimeOfDay(hour: 13, minute: 0))
        form.mode = .netFocus
        #expect(form.normalized() == form)
    }

    @Test func otherChoicesAreKept() {
        let form = normalized { $0.longBreak = .none; $0.remainder = .stretchBlocks; $0.mode = .netFocus }
        #expect(form.longBreak == LongBreakChoice.none)
        #expect(form.remainder == .stretchBlocks)
        #expect(form.mode == .netFocus)
    }

    // MARK: Codable

    static let allChoices: [DayPlanForm] = {
        var forms: [DayPlanForm] = []
        let presets: [PresetChoice] = BuiltInPreset.allCases.map { .builtIn($0) } + [.custom]
        let longBreaks: [LongBreakChoice] = [.none, .atTime(TimeOfDay(hour: 13, minute: 0)), .afterBlock(3)]
        for preset in presets {
            for mode in DayModeChoice.allCases {
                for longBreak in longBreaks {
                    for remainder in RemainderChoice.allCases {
                        var form = DayPlanForm.standard
                        form.presetChoice = preset; form.mode = mode
                        form.longBreak = longBreak; form.remainder = remainder
                        forms.append(form)
                    }
                }
            }
        }
        return forms
    }()

    @Test(arguments: DayPlanFormTests.allChoices)
    func roundTripsThroughJSON(form: DayPlanForm) throws {
        #expect(try JSONDecoder().decode(DayPlanForm.self, from: JSONEncoder().encode(form)) == form)
    }

    @Test func anUnknownCaseFailsToDecode() throws {
        let json = try String(decoding: JSONEncoder().encode(DayPlanForm.standard), as: UTF8.self)
            .replacingOccurrences(of: "deepWork", with: "mystery")
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(DayPlanForm.self, from: Data(json.utf8)) }
    }
}
