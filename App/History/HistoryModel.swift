import Foundation
import Observation
import RipelineCore

/// What the History tab shows: the recorded days, the chosen one in detail, and deleting one.
///
/// The running day is left out (it belongs to "Today"); a day that was never ended is listed as
/// such. Nothing here changes a day: the only write is deleting one, after a confirmation.
@MainActor @Observable
final class HistoryModel {
    @ObservationIgnored private let store: any DayStore
    @ObservationIgnored private let activeDayID: @MainActor () -> UUID?
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let onDayDeleted: @MainActor (SessionSnapshot) -> Void

    /// Newest first.
    private(set) var entries: [HistoryEntry] = []
    /// The id of the chosen entry.
    private(set) var selection: String?
    /// The chosen day's overview, read only.
    private(set) var detail: DayOverviewModel?
    /// The day the user asked to delete and has not confirmed yet.
    private(set) var pendingDelete: HistoryEntry?
    private(set) var deleteFailed = false
    private(set) var loadFailed = false

    /// - Parameter activeDayID: The id of the first segment of the day that is running now, if any.
    /// - Parameter onDayDeleted: Called with the snapshot of a day that was deleted, for whoever keeps something about it.
    init(
        store: any DayStore, activeDayID: @escaping @MainActor () -> UUID?, calendar: Calendar = .autoupdatingCurrent,
        onDayDeleted: @escaping @MainActor (SessionSnapshot) -> Void = { _ in }
    ) {
        self.store = store
        self.activeDayID = activeDayID
        self.calendar = calendar
        self.onDayDeleted = onDayDeleted
    }

    /// Reads the store again. The selection is kept if its day still exists, otherwise the newest is chosen.
    func refresh() {
        let oldIndex = entries.firstIndex(where: { $0.id == selection })
        let days: [StoredDay]
        do { days = try store.loadAll() } catch {
            loadFailed = true
            return
        }
        loadFailed = false
        deleteFailed = false
        let active = activeDayID()
        entries = days.filter { active == nil || $0.snapshot.plan.first?.id != active }.map(HistoryEntry.init(day:))
        if selection == nil || !entries.contains(where: { $0.id == selection }) {
            // The day that was selected is gone: the one that took its place, else the newer neighbour.
            if let oldIndex, !entries.isEmpty {
                selection = entries[min(oldIndex, entries.count - 1)].id
            } else {
                selection = entries.first?.id
            }
        }
        rebuildDetail()
    }

    /// Chooses a day; an id that is not in the list is ignored. `nil` clears the choice.
    func select(_ id: String?) {
        if let id, !entries.contains(where: { $0.id == id }) { return }
        deleteFailed = false
        selection = id
        rebuildDetail()
    }

    // MARK: Deleting

    /// Asks to delete a day. The running day and unknown ids are refused.
    func requestDelete(_ id: String) {
        deleteFailed = false
        guard let entry = entries.first(where: { $0.id == id }), !isRunning(entry) else {
            pendingDelete = nil
            return
        }
        pendingDelete = entry
    }

    func cancelDelete() { pendingDelete = nil }

    /// Deletes the day that was asked for. If it started running meanwhile, nothing is deleted.
    func confirmDelete() {
        guard let entry = pendingDelete else { return }
        confirmDelete(entry)
    }

    /// Deletes `entry`, the day the confirmation dialog showed. A day that is no longer listed, or
    /// that started running meanwhile, is left alone.
    func confirmDelete(_ entry: HistoryEntry) {
        pendingDelete = nil
        guard entries.contains(where: { $0.id == entry.id }), !isRunning(entry) else { return }
        do {
            try store.delete(StoredDay(key: entry.id, snapshot: entry.snapshot))
        } catch {
            // Perhaps the file is not the day shown any more: re-read, then say it failed.
            refresh()
            deleteFailed = true
            return
        }
        deleteFailed = false
        onDayDeleted(entry.snapshot)
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries.remove(at: index)
            if selection == entry.id {
                // The next older day if there is one, otherwise the newer neighbour.
                selection = entries.indices.contains(index) ? entries[index].id : entries.last?.id
            }
        }
        refresh()
    }

    // MARK: Private

    private func isRunning(_ entry: HistoryEntry) -> Bool {
        guard let active = activeDayID() else { return false }
        return entry.snapshot.plan.first?.id == active
    }

    private func rebuildDetail() {
        guard let entry = entries.first(where: { $0.id == selection }) else {
            detail = nil
            return
        }
        detail = DayOverviewModel(source: SnapshotSource(snapshot: entry.snapshot), calendar: calendar)
    }
}
