import Foundation
import RipelineCore

/// A `DayStore` that keeps the latest day in memory only. Used when the real directory cannot
/// be created, and by the inert environment under test.
@MainActor
final class InMemoryDayStore: DayStore {
    private var latest: StoredDay?

    func loadLatest() throws -> StoredDay? { latest }

    func save(_ snapshot: SessionSnapshot) throws {
        guard !snapshot.plan.isEmpty else { throw DayStoreError.emptyPlan }
        latest = StoredDay(key: "memory", snapshot: snapshot)
    }

    func quarantine(_ day: StoredDay) throws {
        if latest == day { latest = nil }
    }
}
