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

    /// Review finding: resizing the window must not throw the pile away and drop it again.
    @Test func resizingKeepsTheSameTomatoNodes() throws {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.update(tomatoes(20), highlight: nil)
        let before = scene.nodeIdentities
        scene.size = CGSize(width: 520, height: 300)
        #expect(scene.nodeIdentities == before)
        #expect(scene.tomatoNodeCount == 20)
    }

    @Test func aShrinkingCrateKeepsTheTomatoesInsideIt() {
        let scene = CrateScene(size: CGSize(width: 600, height: 300))
        scene.reduceMotion = true
        scene.update(tomatoes(30), highlight: nil)
        scene.size = CGSize(width: 300, height: 200)
        let interior = CrateGeometry.interior(in: scene.size)
        #expect(scene.nodePositions.allSatisfy { interior.insetBy(dx: -1, dy: -1).contains($0) })
    }

    /// Review finding: under Reduce Motion the still pile follows the list when tomatoes come and go.
    @Test func theStillPileClosesRanksWhenATomatoLeaves() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.reduceMotion = true
        let all = tomatoes(6)
        scene.update(all, highlight: nil)
        scene.update(Array(all.dropFirst()), highlight: nil)
        let interior = CrateGeometry.interior(in: scene.size)
        let d = CrateGeometry.baseDiameter(forCount: 5)
        let expected = (0..<5).map { CrateGeometry.settledPosition(index: $0, in: interior, diameter: d) }
        let actual = scene.nodePositions(inOrderOf: Array(all.dropFirst()))
        #expect(actual.count == expected.count)
        // SpriteKit keeps positions in single precision.
        #expect(zip(actual, expected).allSatisfy { abs($0.x - $1.x) < 0.01 && abs($0.y - $1.y) < 0.01 })
    }

    @Test func updatingWithTheSameTomatoesKeepsTheirBodies() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        let all = tomatoes(5)
        scene.update(all, highlight: nil)
        let before = scene.bodyIdentities
        scene.update(all, highlight: "2026-01-10")
        #expect(scene.bodyIdentities == before)
    }
}
