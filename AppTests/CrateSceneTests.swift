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

    // MARK: grabbing and tossing

    private func oneTomatoScene(reduceMotion: Bool = false) -> (scene: CrateScene, tomato: CrateTomato) {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.reduceMotion = reduceMotion
        let tomato = tomatoes(1)[0]
        scene.update([tomato], highlight: nil)                      // the only tomato drops in at once
        return (scene, tomato)
    }

    @Test func aTomatoCanBeGrabbedWhereItLies() throws {
        let (scene, tomato) = oneTomatoScene()
        let at = try #require(scene.nodePositions(inOrderOf: [tomato]).first)
        #expect(scene.beginGrab(at: at, time: 0))
        #expect(scene.isGrabbing)
    }

    @Test func nothingIsGrabbedWhereThereIsNoTomato() {
        let (scene, _) = oneTomatoScene()
        #expect(scene.beginGrab(at: CGPoint(x: 5, y: 5), time: 0) == false)
        #expect(!scene.isGrabbing)
    }

    @Test func withReduceMotionNothingCanBeGrabbed() throws {
        let (scene, tomato) = oneTomatoScene(reduceMotion: true)
        let at = try #require(scene.nodePositions(inOrderOf: [tomato]).first)
        #expect(scene.beginGrab(at: at, time: 0) == false)
    }

    @Test func aHeldTomatoIsPulledTowardThePointerAndIgnoresGravity() throws {
        let (scene, tomato) = oneTomatoScene()
        let start = try #require(scene.nodePositions(inOrderOf: [tomato]).first)
        let goal = CGPoint(x: 200, y: 100)
        scene.beginGrab(at: start, time: 0)
        scene.moveGrab(to: goal, time: 0.05)
        scene.update(0.05)
        let velocity = try #require(scene.grabbedVelocity)
        #expect((velocity.dx > 0) == (goal.x > start.x))            // towards the pointer, whichever side it is on
        #expect(velocity.dy < 0)                                    // a new tomato starts above the crate
        #expect(scene.grabbedFeelsGravity == false)
    }

    @Test func releasingTossesWithTheSpeedOfTheHand() throws {
        let (scene, tomato) = oneTomatoScene()
        let start = try #require(scene.nodePositions(inOrderOf: [tomato]).first)
        scene.beginGrab(at: start, time: 0)
        scene.moveGrab(to: CGPoint(x: 200, y: 100), time: 0.01)
        scene.moveGrab(to: CGPoint(x: 240, y: 140), time: 0.06)
        scene.moveGrab(to: CGPoint(x: 280, y: 180), time: 0.11)
        scene.endGrab(time: 0.11)
        #expect(!scene.isGrabbing)
        let velocity = try #require(scene.firstBodyVelocity)
        #expect(abs(velocity.dx - 800) < 1 && abs(velocity.dy - 800) < 1)   // 80 pt in 0.1 s each way
        #expect(scene.firstBodyFeelsGravity)
    }

    @Test func holdingStillBeforeLettingGoDropsTheTomato() throws {
        let (scene, tomato) = oneTomatoScene()
        let start = try #require(scene.nodePositions(inOrderOf: [tomato]).first)
        scene.beginGrab(at: start, time: 0)
        scene.moveGrab(to: CGPoint(x: start.x + 80, y: start.y), time: 0.05)
        scene.moveGrab(to: CGPoint(x: start.x + 80, y: start.y), time: 0.60)   // stayed put for half a second
        scene.endGrab(time: 0.60)
        let velocity = try #require(scene.firstBodyVelocity)
        #expect(abs(velocity.dx) < 50 && abs(velocity.dy) < 50)
    }

    @Test func aTossIsNotFasterThanTheLimit() {
        let fast = [(time: 0.0, point: CGPoint(x: 0, y: 0)), (time: 0.01, point: CGPoint(x: 500, y: 0))]
        let velocity = CrateScene.tossVelocity(from: fast, releasedAt: 0.01)
        #expect((velocity.dx * velocity.dx + velocity.dy * velocity.dy).squareRoot() <= CrateScene.maxTossSpeed + 1e-6)
        #expect(velocity.dx > 0)
    }

    @Test func aTomatoRemovedWhileHeldEndsTheGrab() throws {
        let (scene, tomato) = oneTomatoScene()
        let start = try #require(scene.nodePositions(inOrderOf: [tomato]).first)
        scene.beginGrab(at: start, time: 0)
        scene.update([], highlight: nil)
        #expect(!scene.isGrabbing)
        scene.moveGrab(to: CGPoint(x: 10, y: 10), time: 0.1)         // must not crash
        scene.endGrab(time: 0.1)
    }
}
