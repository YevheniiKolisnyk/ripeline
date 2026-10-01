import CoreGraphics
import Foundation

/// Where things are in the crate. Fractions of the view; the scene's origin is the bottom left, as in SpriteKit.
enum CrateGeometry {
    static let insetX = 0.07
    static let floorY = 0.10
    static let rimY = 0.80
    /// The front boards hide the lowest tomatoes, so the pile looks like it is inside.
    static let frontHeight = 0.22

    /// The inside of the crate, in scene coordinates.
    static func interior(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * insetX, y: size.height * floorY,
            width: size.width * (1 - 2 * insetX), height: size.height * (rimY - floorY)
        )
    }

    /// How wide a tomato at 100% is drawn: 30 pt up to 60 tomatoes, shrinking to 14 pt at 300 so the crate can hold them all.
    static func baseDiameter(forCount count: Int) -> CGFloat {
        let fill = min(1, max(0, Double(count - 60) / 240))
        return CGFloat(30 - 16 * fill)
    }

    /// Where the `index`th tomato lies in a still pile (Reduce Motion): rows from the floor up.
    static func settledPosition(index: Int, in interior: CGRect, diameter: CGFloat) -> CGPoint {
        let columns = max(1, Int(interior.width / diameter))
        let column = index % columns, row = index / columns
        let step = interior.width / CGFloat(columns)
        return CGPoint(
            x: interior.minX + (CGFloat(column) + 0.5) * step,
            y: interior.minY + diameter / 2 + CGFloat(row) * diameter * 0.86
        )
    }

    /// Where a tomato is let go, the same every time for the same tomato.
    static func dropX(for id: UUID, in interior: CGRect, diameter: CGFloat) -> CGFloat {
        let fraction = CGFloat(id.uuid.0) / 255
        return interior.minX + diameter / 2 + fraction * max(0, interior.width - diameter)
    }
}
