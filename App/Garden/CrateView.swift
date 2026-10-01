import SpriteKit
import SwiftUI

/// The crate: tomatoes fall into it with physics. Rings the tomatoes of `highlight`, the chosen day.
struct CrateView: View {
    let model: CrateModel
    let highlight: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = CrateScene(size: CGSize(width: 1, height: 1))

    var body: some View {
        ZStack {
            CrateArt.Back()
            SpriteView(scene: scene, options: [.allowsTransparency])
            CrateArt.Front(total: model.total)
            if model.total == 0 {
                VStack(spacing: 4) {
                    Text("crate.empty").font(.headline)
                    Text("crate.emptyHint").font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 40)
            }
        }
        .frame(height: 260)
        .onAppear { push() }
        .onChange(of: model.tomatoes) { push() }
        .onChange(of: highlight) { push() }
        .onChange(of: reduceMotion) { push() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GardenText.crateLabel(total: model.total))
    }

    private func push() {
        scene.reduceMotion = reduceMotion
        scene.update(model.tomatoes, highlight: highlight)
    }
}
