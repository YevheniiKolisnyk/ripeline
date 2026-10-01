import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// A laptop changes time zone while the app keeps running; the setup window must follow it.
/// Serialized because it changes the process-wide default time zone.
@MainActor @Suite(.serialized)
struct AutoupdatingCalendarTests {
    @Test func theEndTimeFollowsATimeZoneChangeWithoutARelaunch() throws {
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }
        let suite = "ripeline-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let london = try #require(TimeZone(identifier: "Europe/London"))
        NSTimeZone.default = tokyo
        // 09:00 UTC is 18:00 in Tokyo (past an end of 17:00) and 09:00 in London.
        let clock = TestClock(d(15, 9, 0))
        let model = DaySetupModel(
            settings: AppSettings(defaults: UserDefaults(suiteName: suite)!), clock: clock,
            canStart: { true }, start: { _ in true }
        )
        #expect(model.result == .invalid(.endNotAfterNow))

        NSTimeZone.default = london
        model.refresh()
        guard case let .ready(request, _, _) = model.result else {
            Issue.record("expected a ready result after the time zone changed, got \(model.result)")
            return
        }
        guard case let .untilTime(_, end) = request.mode else { Issue.record("not untilTime"); return }
        #expect(end == d(15, 17, 0))
    }
}
