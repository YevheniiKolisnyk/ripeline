import Foundation
import Observation
import RipelineCore

/// A picked tomato as the crate sees it.
struct CrateTomato: Equatable, Identifiable, Sendable {
    let id: UUID
    /// The store key of the day it grew in, the same as `HistoryEntry.id`.
    let dayID: String
    let growth: Double
    /// When its block was planned to start; the crate is filled in this order.
    let start: Date
}

/// What the crate holds: the picked tomatoes of the stored days, the newest `limit` of them, and how many there are in all.
/// A tomato counts only while its day exists. Its size is read at the last record of its day.
@MainActor @Observable
final class CrateModel {
    static let defaultLimit = 300

    @ObservationIgnored private let store: any DayStore
    @ObservationIgnored private let garden: GardenModel
    @ObservationIgnored private let limit: Int

    /// Oldest first.
    private(set) var tomatoes: [CrateTomato] = []
    private(set) var total = 0
    private(set) var loadFailed = false

    init(store: any DayStore, garden: GardenModel, limit: Int = CrateModel.defaultLimit) {
        self.store = store
        self.garden = garden
        self.limit = limit
    }

    /// Reads the stored days again. A failed read keeps what was there.
    func refresh() {
        let days: [StoredDay]
        do { days = try store.loadAll() } catch {
            loadFailed = true
            return
        }
        loadFailed = false
        var all: [CrateTomato] = []
        for day in days {
            let snapshot = day.snapshot
            let instant = SnapshotSource.lastRecordedInstant(of: snapshot) ?? snapshot.plan.first?.start ?? .distantPast
            for tomato in Tomatoes.of(snapshot, at: instant) where garden.isPicked(tomato.id) && tomato.workTime > 0 {
                all.append(CrateTomato(
                    id: tomato.id, dayID: day.key, growth: tomato.growth, start: snapshot.plan[tomato.segmentIndex].start
                ))
            }
        }
        all.sort { $0.start < $1.start }
        total = all.count
        tomatoes = Array(all.suffix(limit))
    }
}
