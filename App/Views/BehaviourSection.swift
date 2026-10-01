import RipelineCore
import SwiftUI

/// The three switches that change how sessions behave. They take effect from the next transition.
struct BehaviourSection: View {
    let controller: SessionController
    let settings: AppSettings

    var body: some View {
        DisclosureGroup("behaviour.title") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("behaviour.pausesAsRest", isOn: binding(\.pausesCountAsRest))
                Toggle("behaviour.autoBreak", isOn: binding(\.autoAdvanceWorkToBreak))
                Toggle("behaviour.autoWork", isOn: binding(\.autoAdvanceBreakToWork))
                Text("behaviour.note").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<SessionSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { controller.effectiveSessionSettings[keyPath: keyPath] },
            set: { newValue in
                var changed = controller.effectiveSessionSettings
                changed[keyPath: keyPath] = newValue
                controller.updateSessionSettings(changed)
            }
        )
    }
}
