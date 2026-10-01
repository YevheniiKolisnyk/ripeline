import Foundation
import Observation
import os
import RipelineCore

/// Which tomatoes have been picked. Picking is the only write; it is remembered across launches in
/// the harvest store. Whether a tomato can be picked at all is decided by the core (`.pickable`).
@MainActor @Observable
final class GardenModel {
    @ObservationIgnored private let store: any HarvestStore
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "garden")
    /// A store that could not be read is never written: its content would be replaced by a partial set.
    @ObservationIgnored private var canSave = true

    private(set) var picked: Set<UUID> = []
    /// The last attempt to save failed. The picks are kept in memory and written with the next save.
    private(set) var saveFailed = false

    init(store: any HarvestStore) {
        self.store = store
        do { picked = try store.load() } catch {
            canSave = false
            logger.error("Could not read the picked tomatoes; they will not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    func isPicked(_ id: UUID) -> Bool { picked.contains(id) }

    /// Picks a tomato that is pickable and not yet picked. Returns whether anything was picked.
    @discardableResult
    func pick(_ tomato: Tomato) -> Bool {
        guard tomato.availability == .pickable, !picked.contains(tomato.id) else { return false }
        picked.insert(tomato.id)
        persist()
        return true
    }

    /// Removes ids, for example those of a deleted day. Saves only when something changed.
    func forget(_ ids: some Sequence<UUID>) {
        let before = picked
        picked.subtract(ids)
        if picked != before { persist() }
    }

    private func persist() {
        guard canSave else { return }
        do {
            try store.save(picked)
            saveFailed = false
        } catch {
            saveFailed = true
            logger.error("Could not save the picked tomatoes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
