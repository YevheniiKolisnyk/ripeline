import CoreGraphics
import Foundation
import Testing
@testable import Ripeline

struct CrateGeometryTests {
    private let size = CGSize(width: 400, height: 260)

    @Test func theInteriorIsInsideTheCrate() {
        let interior = CrateGeometry.interior(in: size)
        #expect(interior.minX > 0 && interior.maxX < size.width)
        #expect(interior.minY > 0 && interior.maxY < size.height)
    }

    @Test func tomatoesShrinkAsTheCrateFillsAndStayInBounds() {
        let counts = [0, 1, 10, 60, 100, 200, 300, 500]
        let diameters = counts.map { CrateGeometry.baseDiameter(forCount: $0) }
        #expect(zip(diameters, diameters.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(diameters.allSatisfy { $0 >= 14 && $0 <= 30 })
        #expect(CrateGeometry.baseDiameter(forCount: 300) == 14)
        #expect(CrateGeometry.baseDiameter(forCount: 60) == 30)
    }

    /// Review focus 4: with 300 tomatoes the still pile (Reduce Motion) fits in the crate.
    @Test func threeHundredSettledTomatoesFitInTheInterior() {
        let interior = CrateGeometry.interior(in: size)
        let d = CrateGeometry.baseDiameter(forCount: 300)
        let points = (0..<300).map { CrateGeometry.settledPosition(index: $0, in: interior, diameter: d) }
        #expect(points.allSatisfy { $0.x - d / 2 >= interior.minX - 0.5 && $0.x + d / 2 <= interior.maxX + 0.5 })
        #expect(points.allSatisfy { $0.y - d / 2 >= interior.minY - 0.5 && $0.y + d / 2 <= interior.maxY + 0.5 })
        #expect(Set(points.map { "\($0.x),\($0.y)" }).count == 300)
    }

    @Test func aTomatoAlwaysDropsFromTheSameSpot() {
        let interior = CrateGeometry.interior(in: size)
        let id = UUID()
        let x = CrateGeometry.dropX(for: id, in: interior, diameter: 20)
        #expect(x == CrateGeometry.dropX(for: id, in: interior, diameter: 20))
        #expect(x >= interior.minX + 10 && x <= interior.maxX - 10)
    }
}
