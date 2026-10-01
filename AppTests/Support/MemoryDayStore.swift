import Foundation
import RipelineCore
@testable import Ripeline

/// An in-memory `DayStore` that records what happens to it.
@MainActor
final class MemoryDayStore: DayStore {
    struct Failure: Error {}

    var latest: StoredDay?
    private(set) var saved: [SessionSnapshot] = []
    private(set) var quarantined: [StoredDay] = []
    /// How many times a save was attempted, including ones that failed.
    private(set) var saveAttempts = 0
    var failLoad = false
    var failSave = false
    var failDelete = false
    /// The days `loadAll` returns, newest first; defaults to the latest day alone.
    var days: [StoredDay]?
    private(set) var deleted: [StoredDay] = []

    init(latest: StoredDay? = nil) { self.latest = latest }

    func loadLatest() throws -> StoredDay? {
        if failLoad { throw Failure() }
        return latest
    }

    func save(_ snapshot: SessionSnapshot) throws {
        saveAttempts += 1
        if failSave { throw Failure() }
        guard !snapshot.plan.isEmpty else { throw DayStoreError.emptyPlan }
        saved.append(snapshot)
        latest = StoredDay(key: "memory", snapshot: snapshot)
    }

    func loadAll() throws -> [StoredDay] {
        if failLoad { throw Failure() }
        return days ?? latest.map { [$0] } ?? []
    }

    func delete(_ day: StoredDay) throws {
        if failDelete { throw Failure() }
        deleted.append(day)
        days?.removeAll { $0.key == day.key }
        if latest == day { latest = nil }
    }

    func quarantine(_ day: StoredDay) throws {
        quarantined.append(day)
        if latest == day { latest = nil }
    }
}
