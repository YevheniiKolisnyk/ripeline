import Foundation
@testable import Ripeline

/// An in-memory `HarvestStore` that records what happens to it and can be made to fail.
@MainActor
final class MemoryHarvestStore: HarvestStore {
    struct Failure: Error {}

    var picked: Set<UUID>
    var failLoad = false
    var failSave = false
    private(set) var saves: [Set<UUID>] = []

    init(picked: Set<UUID> = []) { self.picked = picked }

    func load() throws -> Set<UUID> {
        if failLoad { throw Failure() }
        return picked
    }

    func save(_ picked: Set<UUID>) throws {
        if failSave { throw Failure() }
        self.picked = picked
        saves.append(picked)
    }
}
