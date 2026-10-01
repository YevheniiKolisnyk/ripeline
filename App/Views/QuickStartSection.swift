import SwiftUI

/// "Quick start": a block length and a Start button. One press starts a block at once, with no planning.
struct QuickStartSection: View {
    let controller: SessionController
    @Bindable var settings: AppSettings
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ui.quickStartTitle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Picker("ui.quickLength", selection: $settings.quickBlockLength) {
                    ForEach(QuickBlockLength.allCases, id: \.self) { length in
                        Text(verbatim: SetupText.duration(TimeInterval(length.minutes) * 60, locale: locale)).tag(length)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Button("ui.quickStartButton") {
                    Task { await controller.startQuickSession(length: settings.quickBlockLength) }
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}
