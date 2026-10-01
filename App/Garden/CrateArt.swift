import SwiftUI

/// The back and the front of the wooden crate. The scene with the tomatoes sits between them.
enum CrateArt {
    /// The back wall and the inside.
    struct Back: View {
        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let x = w * (CrateGeometry.insetX - 0.03)
                let top = h * (1 - CrateGeometry.rimY - 0.02)
                let box = CGRect(x: x, y: top, width: w - 2 * x, height: h * 0.97 - top)
                RoundedRectangle(cornerRadius: 10).fill(TomatoPalette.woodDark.color)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TomatoPalette.outline.color, lineWidth: 3))
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
            }
        }
    }

    /// The front boards and the plank that carries the total.
    struct Front: View {
        let total: Int

        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let boardHeight = h * CrateGeometry.frontHeight
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { _ in
                            Rectangle().fill(TomatoPalette.wood.color).overlay(Rectangle().stroke(TomatoPalette.outline.color, lineWidth: 3))
                        }
                    }
                    .frame(width: w * (1 - 2 * (CrateGeometry.insetX - 0.04)), height: boardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(verbatim: GardenText.crateTotal(total))
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(TomatoPalette.outline.color)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.97, green: 0.89, blue: 0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(TomatoPalette.outline.color, lineWidth: 2))
                        .padding(.bottom, boardHeight * 0.25)
                }
                .frame(width: w, height: h, alignment: .bottom)
            }
            .allowsHitTesting(false)
        }
    }
}
