import RipelineCore
import SwiftUI

/// One tomato. When it can be picked it wiggles and a click picks it; a picked one is shown faded.
struct TomatoButton: View {
    let tomato: Tomato
    /// The size of a tomato at 100%.
    let diameter: CGFloat
    @Environment(GardenModel.self) private var garden: GardenModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false

    var body: some View {
        let isPicked = garden?.isPicked(tomato.id) ?? false
        let ready = tomato.availability == .pickable && !isPicked && garden != nil
        let size = diameter * TomatoLook(growth: tomato.growth).scale
        Button {
            if reduceMotion { garden?.pick(tomato) } else { withAnimation(.spring(duration: 0.35)) { _ = garden?.pick(tomato) } }
        } label: {
            TomatoArt(growth: tomato.growth)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(ready && wiggle ? 6 : (ready ? -6 : 0)))
                .opacity(isPicked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(ready)
        .animation(ready && !reduceMotion ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: wiggle)
        .task(id: ready) { wiggle = ready }
        .help(ready ? Text("garden.pick") : Text(verbatim: ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GardenText.tomatoLabel(growth: tomato.growth, availability: tomato.availability, isPicked: isPicked))
        .accessibilityAddTraits(ready ? .isButton : [])
        .accessibilityAction(named: Text("a11y.pickTomato")) { if ready { garden?.pick(tomato) } }
    }
}

/// The popover's row of tomatoes: those still on the bed, the one that is growing among them, and a count of the picked ones.
struct TomatoPatchView: View {
    let tomatoes: [Tomato]
    @Environment(GardenModel.self) private var garden: GardenModel?

    var body: some View {
        let shown = tomatoes.filter { $0.availability == .growing || $0.availability == .pickable }
        let waiting = shown.filter { !(garden?.isPicked($0.id) ?? false) }
        let pickedCount = shown.count - waiting.count
        if !shown.isEmpty {
            HStack(alignment: .bottom, spacing: 8) {
                // The newest few fit the popover; older ones are still on the day screen's bed.
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(waiting.suffix(6)) { tomato in
                        TomatoButton(tomato: tomato, diameter: 34)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(minHeight: 40, alignment: .bottom)
                Spacer(minLength: 0)
                if pickedCount > 0 {
                    Text(verbatim: GardenText.basket(pickedCount)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
