import Foundation
import RipelineCore

/// Localized text for the garden: labels, counts and what VoiceOver reads. The bundle is explicit so tests can ask for either language.
enum GardenText {
    /// The growth as a whole percentage: 1.0 is 100.
    static func percent(_ growth: Double) -> Int { Int((growth * 100).rounded()) }

    /// `Picked: 3`.
    static func basket(_ count: Int, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "garden.basket", value: nil, table: nil), count)
    }

    /// `12 in the crate`.
    static func crateTotal(_ total: Int, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "crate.total", value: nil, table: nil), total)
    }

    /// What VoiceOver reads for the crate.
    static func crateLabel(total: Int, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "a11y.crate", value: nil, table: nil), total)
    }

    /// What VoiceOver reads for one tomato.
    static func tomatoLabel(growth: Double, availability: TomatoAvailability, isPicked: Bool, bundle: Bundle = .main) -> String {
        let key: String
        if isPicked {
            key = "a11y.tomatoPicked"
        } else {
            key = availability == .pickable ? "a11y.tomatoReady" : "a11y.tomatoGrowing"
        }
        return String(format: bundle.localizedString(forKey: key, value: nil, table: nil), percent(growth))
    }
}
