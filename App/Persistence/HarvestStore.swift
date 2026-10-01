import Foundation

/// Where the ids of the picked tomatoes are kept between launches. Separate from the days, so a day
/// file is never rewritten when a tomato is picked.
@MainActor protocol HarvestStore {
    /// The ids of the picked tomatoes; empty when nothing was ever picked.
    func load() throws -> Set<UUID>
    /// Replaces the stored set.
    func save(_ picked: Set<UUID>) throws
}

/// A `HarvestStore` that keeps the set in memory only. Used when the real directory cannot be
/// created, and by the inert environment under test.
@MainActor
final class InMemoryHarvestStore: HarvestStore {
    private var picked: Set<UUID> = []
    func load() throws -> Set<UUID> { picked }
    func save(_ picked: Set<UUID>) throws { self.picked = picked }
}
