import AppKit
import SwiftUI

/// The tomato as a picture for the menu bar. Drawn once per look and size, then reused; the menu bar
/// redraws every second and must not render a new image each time.
@MainActor
enum MenuBarTomato {
    private static var cache: [String: NSImage] = [:]

    static func image(growth: Double, frozen: Bool) -> NSImage {
        let diameter = TomatoLook.menuBarDiameter(growth: growth).rounded()
        let snapped = TomatoLook.textureGrowth(growth)
        let key = "\(snapped)-\(diameter)-\(frozen)"
        if let hit = cache[key] { return hit }
        let art = TomatoArt(growth: snapped)
            .frame(width: diameter, height: diameter)
            .opacity(frozen ? 0.55 : 1)
        let renderer = ImageRenderer(content: art)
        renderer.scale = 3
        let image = renderer.cgImage.map { NSImage(cgImage: $0, size: NSSize(width: diameter, height: diameter)) } ?? NSImage()
        image.isTemplate = false                       // keep the colours; the menu bar must not tint it
        cache[key] = image
        return image
    }
}
