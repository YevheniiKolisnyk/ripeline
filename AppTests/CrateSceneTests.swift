import CoreGraphics
import Foundation
import Testing
@testable import Ripeline

@MainActor
struct CrateSceneTests {
    private func tomatoes(_ count: Int) -> [CrateTomato] {
        (0..<count).map {
            CrateTomato(
                id: UUID(), dayID: "2026-01-1\($0 % 3)", growth: 1 + Double($0 % 5) * 0.2,
                start: d(15, 9).addingTimeInterval(Double($0) * 60)
            )
        }
    }

    /// Review focus 4: no tomatoes, one, and more than the crate keeps.
    @Test(arguments: [0, 1, 300, 400])
    func theSceneHoldsOneNodePerTomatoItIsGiven(count: Int) {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.update(tomatoes(count), highlight: nil)
        #expect(scene.tomatoNodeCount == count)
    }

    @Test func updatingAddsNewTomatoesAndRemovesGoneOnes() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        let all = tomatoes(5)
        scene.update(all, highlight: nil)
        scene.update(Array(all.dropFirst(2)) + tomatoes(1), highlight: nil)
        #expect(scene.tomatoNodeCount == 4)
    }

    @Test func oneDaysTomatoesCanBeHighlighted() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        let all = tomatoes(6)
        scene.update(all, highlight: "2026-01-10")
        #expect(scene.highlightedCount == all.filter { $0.dayID == "2026-01-10" }.count)
        scene.update(all, highlight: nil)
        #expect(scene.highlightedCount == 0)
    }

    @Test func withReduceMotionTheTomatoesHaveNoPhysics() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.reduceMotion = true
        scene.update(tomatoes(5), highlight: nil)
        #expect(scene.dynamicBodyCount == 0)
    }

    @Test func withoutReduceMotionEveryTomatoIsABody() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.update(tomatoes(5), highlight: nil)
        #expect(scene.dynamicBodyCount == 5)
    }
}
