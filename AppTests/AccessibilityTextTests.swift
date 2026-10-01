import Foundation
import Testing
@testable import Ripeline

struct AccessibilityTextTests {
    private let en = Locale(identifier: "en")
    private let uk = Locale(identifier: "uk")

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// The spoken time changes once a minute, not every second.
    @Test(arguments: [(1930.0, "33 min"), (1921.0, "33 min"), (1861.0, "32 min"), (60.0, "1 min"), (0.4, "1 min"), (3725.0, "1 hr, 3 min")])
    func countdownIsRoundedUpToWholeMinutes(seconds: Double, expected: String) throws {
        let text = AccessibilityText.timerValue(phase: .working, remaining: seconds, overtimeElapsed: nil, locale: en, bundle: try bundle("en"))
        #expect(text == expected)
    }

    @Test func theSpokenValueIsStableWithinAMinute() throws {
        let english = try bundle("en")
        let values = (0..<59).map {
            AccessibilityText.timerValue(phase: .working, remaining: 1860 - Double($0), overtimeElapsed: nil, locale: en, bundle: english)
        }
        #expect(Set(values).count <= 2)
    }

    @Test func overtimeIsSaidAsOverThePlan() throws {
        let text = AccessibilityText.timerValue(phase: .overtime(onBreak: false), remaining: 0, overtimeElapsed: 135, locale: en, bundle: try bundle("en"))
        #expect(text == "2 min over the plan")
        let ukrainian = AccessibilityText.timerValue(phase: .overtime(onBreak: false), remaining: 0, overtimeElapsed: 135, locale: uk, bundle: try bundle("uk"))
        #expect(ukrainian == "2 хв понад план")
    }

    @Test(arguments: [Phase.idle, .finished])
    func nothingIsSaidWithoutATimer(phase: Phase) throws {
        #expect(AccessibilityText.timerValue(phase: phase, remaining: nil, overtimeElapsed: nil, locale: en, bundle: try bundle("en")) == nil)
    }

    @Test func theMenuBarLabelNamesTheAppThePhaseAndTheTime() throws {
        let label = AccessibilityText.menuBarLabel(phase: .working, remaining: 1930, overtimeElapsed: nil, locale: en, bundle: try bundle("en"))
        #expect(label == "Ripeline, Work, 33 min")
        let idle = AccessibilityText.menuBarLabel(phase: .idle, remaining: nil, overtimeElapsed: nil, locale: en, bundle: try bundle("en"))
        #expect(idle == "Ripeline, No day started")
        let ukrainian = AccessibilityText.menuBarLabel(phase: .onBreak, remaining: 300, overtimeElapsed: nil, locale: uk, bundle: try bundle("uk"))
        #expect(ukrainian == "Ripeline, Перерва, 5 хв")
    }
}
