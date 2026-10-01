import SwiftUI

/// The garden bed above the timelines: a strip of soil with a wooden edge, and a tomato standing on every worked block.
struct GardenBedView: View {
    let plots: [BedPlot]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4).fill(TomatoPalette.soil.color).frame(height: 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(TomatoPalette.woodDark.color).frame(height: 4)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(TomatoPalette.outline.color.opacity(0.7), lineWidth: 1))
            }
            ForEach(plots) { plot in
                let diameter = min(34, max(16, plot.width * width * 1.3))
                let size = diameter * TomatoLook(growth: plot.tomato.growth).scale
                TomatoButton(tomato: plot.tomato, diameter: diameter)
                    .position(x: plot.x * width, y: height - 8 - size / 2)
            }
        }
        .frame(width: width, height: height)
    }
}
