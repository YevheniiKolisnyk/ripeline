import Testing
@testable import Ripeline

@MainActor
struct AppRouterTests {
    @Test func startsOnTodayWithoutPlanning() {
        let router = AppRouter()
        #expect(router.tab == .today)
        #expect(!router.planningNewDay)
    }

    /// Review finding: "Day summary…" must show the summary, not a planning form left open by "New day".
    @Test func showingTodayLeavesThePlanningFormBehind() {
        let router = AppRouter()
        router.tab = .history
        router.planningNewDay = true
        router.showToday()
        #expect(router.tab == .today)
        #expect(!router.planningNewDay)
    }

    @Test func showingHistoryKeepsThePlanningChoice() {
        let router = AppRouter()
        router.planningNewDay = true
        router.showHistory()
        #expect(router.tab == .history)
        #expect(router.planningNewDay)
    }
}
