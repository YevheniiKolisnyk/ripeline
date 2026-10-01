import Foundation
import Testing
@testable import Ripeline

struct TomatoLookTests {
    @Test(arguments: [
        (0.0, TomatoStage.sprout), (0.19, .sprout), (0.2, .green), (0.59, .green),
        (0.6, .blushing), (0.99, .blushing), (1.0, .ripe), (1.5, .ripe),
    ])
    func stagesFollowTheGrowth(growth: Double, stage: TomatoStage) {
        #expect(TomatoLook(growth: growth).stage == stage)
    }

    @Test(arguments: [(0.0, 0.35), (1.0, 1.0), (1.5, 1.25), (2.0, 1.5), (5.0, 1.5)])
    func theScaleGrowsAndIsCappedAtTwiceTheGrowth(growth: Double, scale: Double) {
        #expect(abs(TomatoLook(growth: growth).scale - scale) < 1e-9)
    }

    @Test func theScaleNeverShrinksAsTheTomatoGrows() {
        let scales = stride(from: 0.0, through: 3.0, by: 0.01).map { TomatoLook(growth: $0).scale }
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test(arguments: [(0.5, TomatoFace.sleepy), (0.99, .sleepy), (1.0, .smile), (1.19, .smile), (1.2, .grin), (2.0, .grin)])
    func theFaceFollowsTheGrowth(growth: Double, face: TomatoFace) {
        #expect(TomatoLook(growth: growth).face == face)
        #expect(TomatoLook(growth: growth).isBig == (face == .grin))
    }

    @Test func ripenessIsClampedToWhatCanBeSeen() {
        #expect(TomatoLook(growth: -1).ripeness == 0)
        #expect(TomatoLook(growth: 0.4).ripeness == 0.4)
        #expect(TomatoLook(growth: 3).ripeness == 1)
    }

    /// A texture is drawn once per look, so the snapped growth must look like the real one.
    @Test func theTextureGrowthLooksLikeTheRealGrowth() {
        for step in 0...220 {
            let growth = Double(step) * 0.01
            let snapped = TomatoLook.textureGrowth(growth)
            let real = TomatoLook(growth: growth), texture = TomatoLook(growth: snapped)
            #expect(real.stage == texture.stage && real.face == texture.face, "growth \(growth) snapped to \(snapped)")
            #expect(snapped <= growth + 1e-9)
        }
    }

    @Test func thePaletteRunsFromGreenThroughYellowToRed() {
        #expect(TomatoPalette.body(ripeness: 0) == TomatoPalette.green)
        #expect(TomatoPalette.body(ripeness: 0.7) == TomatoPalette.yellow)
        #expect(TomatoPalette.body(ripeness: 1) == TomatoPalette.red)
        #expect(TomatoPalette.body(ripeness: 7) == TomatoPalette.red)
        #expect(TomatoPalette.body(ripeness: -1) == TomatoPalette.green)
    }
}
