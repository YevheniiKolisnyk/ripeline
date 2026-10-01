import Foundation
import RipelineCore

/// A day as it was stored: the snapshot and the key (`YYYY-MM-DD`) it was stored under.
struct StoredDay: Equatable, Sendable {
    let key: String
    let snapshot: SessionSnapshot
}

enum DayStoreError: Error, Equatable {
    /// A snapshot without a plan has nothing to store and no date to store it under.
    case emptyPlan
}

/// Where days are kept between launches.
@MainActor protocol DayStore {
    /// The most recent day that can be read. Damaged or newer-version files are set aside
    /// and the next older day is tried.
    func loadLatest() throws -> StoredDay?

    /// Writes the snapshot under the local calendar date of its plan's first segment.
    func save(_ snapshot: SessionSnapshot) throws

    /// Sets the day's file aside as `<key>.json.corrupt`: kept, but no longer loaded.
    func quarantine(_ day: StoredDay) throws
}
