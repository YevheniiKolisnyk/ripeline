import SpriteKit
import SwiftUI

/// Drawings of tomatoes as textures for the crate, rendered once per look.
@MainActor
final class TomatoTextures {
    private var cache: [Double: SKTexture] = [:]

    func texture(growth: Double) -> SKTexture {
        let snapped = TomatoLook.textureGrowth(growth)
        if let hit = cache[snapped] { return hit }
        let renderer = ImageRenderer(content: TomatoArt(growth: snapped).frame(width: 96, height: 96))
        renderer.scale = 2
        let texture = renderer.cgImage.map { SKTexture(cgImage: $0) } ?? SKTexture()
        cache[snapped] = texture
        return texture
    }
}
