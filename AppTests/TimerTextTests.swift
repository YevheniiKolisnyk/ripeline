import Testing
@testable import Ripeline

struct TimerTextTests {
    @Test(arguments: [
        (0.0, "0:00"), (0.4, "0:01"), (59.0, "0:59"), (59.2, "1:00"), (1930.0, "32:10"),
        (3599.5, "1:00:00"), (3600.0, "1:00:00"), (3725.0, "1:02:05"), (-5.0, "0:00"),
        (36000.0, "10:00:00"),
    ])
    func countdown(seconds: Double, expected: String) {
        #expect(TimerText.countdown(seconds) == expected)
    }

    @Test(arguments: [(0.0, "+0:00"), (135.9, "+2:15"), (3725.0, "+1:02:05"), (-3.0, "+0:00")])
    func overtime(seconds: Double, expected: String) {
        #expect(TimerText.overtime(seconds) == expected)
    }
}
