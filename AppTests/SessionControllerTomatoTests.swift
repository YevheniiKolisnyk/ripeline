import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerTomatoTests {
    @Test func theTomatoOfTheRunningBlockGrowsWithTheClock() async throws {
        let h = Harness(); defer { h.cleanUp() }
        await h.controller.startQuickSession(length: .short)
        await settleBackgroundWork()
        h.clock.set(t(9, 10)); h.controller.refresh()
        let growing = try #require(h.controller.tomatoes.first)
        #expect(abs(growing.growth - 0.4) < 1e-9 && growing.availability == .growing)
        h.clock.set(t(9, 25)); h.controller.refresh()
        #expect(h.controller.tomatoes.first?.availability == .pickable)
    }

    @Test func noDayHasNoTomatoes() {
        let h = Harness(); defer { h.cleanUp() }
        #expect(h.controller.tomatoes.isEmpty)
    }

    @Test func theMenuBarTomatoIsTheOneOfTheRunningWorkBlock() async throws {
        let h = Harness(); defer { h.cleanUp() }
        #expect(h.controller.currentTomatoGrowth == nil)                      // no day
        await h.controller.startQuickSession(length: .short)
        await settleBackgroundWork()
        h.clock.set(t(9, 10)); h.controller.refresh()
        #expect(abs(try #require(h.controller.currentTomatoGrowth) - 0.4) < 1e-9)
        h.clock.set(t(9, 40)); h.controller.refresh()                          // overtime: still the same tomato, bigger
        #expect(abs(try #require(h.controller.currentTomatoGrowth) - 1.6) < 1e-9)
        h.controller.addBlock(); h.controller.advance()                        // into the break
        #expect(h.controller.currentTomatoGrowth == nil)
    }
}
