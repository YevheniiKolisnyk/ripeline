import SwiftUI

/// How far a tomato has come, as far as the eye can tell.
enum TomatoStage: Equatable, Sendable { case sprout, green, blushing, ripe }

/// What a tomato's face says.
enum TomatoFace: Equatable, Sendable { case sleepy, smile, grin }

/// A colour as plain numbers, so the palette can be tested and mixed.
struct RGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// The fixed cartoon palette. It is the same in light and dark appearance.
enum TomatoPalette {
    static let outline = RGB(r: 0.33, g: 0.16, b: 0.10)
    static let green = RGB(r: 0.52, g: 0.76, b: 0.28)
    static let yellow = RGB(r: 0.98, g: 0.80, b: 0.28)
    static let red = RGB(r: 0.92, g: 0.25, b: 0.20)
    static let leaf = RGB(r: 0.30, g: 0.62, b: 0.25)
    static let soil = RGB(r: 0.52, g: 0.34, b: 0.20)
    static let wood = RGB(r: 0.80, g: 0.58, b: 0.34)
    static let woodDark = RGB(r: 0.62, g: 0.42, b: 0.24)
    static let blush = RGB(r: 1.0, g: 0.55, b: 0.55)

    /// Green at 0, yellow at 0.7, red at 1. It stays green for a good while, then turns quickly.
    static func body(ripeness: Double) -> RGB {
        let t = min(1, max(0, ripeness))
        if t < yellowAt {
            let leg = t / yellowAt
            return green.mixed(with: yellow, leg * leg)
        }
        return yellow.mixed(with: red, (t - yellowAt) / (1 - yellowAt))
    }

    private static let yellowAt = 0.7
}

/// Everything that decides how a tomato looks, from its growth alone (1.0 is 100%).
struct TomatoLook: Equatable, Sendable {
    static let sproutBelow = 0.2
    static let greenBelow = 0.6
    static let ripeFrom = 1.0
    static let grinFrom = 1.2
    /// The display scale stops growing here; the figures stay honest.
    static let maxGrowth = 2.0

    let stage: TomatoStage
    /// 0 is green and 1 is red.
    let ripeness: Double
    /// How big it is drawn, as a fraction of the full size: 1 at 100%, at most 1.5.
    let scale: Double
    let face: TomatoFace

    init(growth: Double) {
        let g = max(0, growth)
        ripeness = min(g, 1)
        switch g {
        case ..<Self.sproutBelow: stage = .sprout
        case ..<Self.greenBelow: stage = .green
        case ..<Self.ripeFrom: stage = .blushing
        default: stage = .ripe
        }
        let overshoot = min(g, Self.maxGrowth) - 1
        scale = g <= 1 ? 0.35 + 0.65 * g : 1 + 0.5 * overshoot
        face = g < Self.ripeFrom ? .sleepy : (g < Self.grinFrom ? .smile : .grin)
    }

    /// Bigger than 100% by enough to grin and sparkle.
    var isBig: Bool { face == .grin }

    /// The growth snapped down to what a drawing can tell apart, so one drawing serves many tomatoes.
    static func textureGrowth(_ growth: Double) -> Double {
        let g = max(0, growth)
        if g < ripeFrom { return ((g * 10) + 1e-9).rounded(.down) / 10 }
        return g < grinFrom ? ripeFrom : grinFrom
    }
}
