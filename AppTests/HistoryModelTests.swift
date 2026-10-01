import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct HistoryModelTests {
    private final class Active { var id: UUID? }

    private struct Fixture {
        let model: HistoryModel
        let store: MemoryDayStore
        let active: Active
    }

    private func day(_ key: String, _ snapshot: SessionSnapshot) -> StoredDay { StoredDay(key: key, snapshot: snapshot) }

    /// Three finished days, newest first: 15th, 14th, 13th.
    private func threeDays() throws -> [StoredDay] {
        [day("2026-01-15", try finishedDay(start: d(15))),
         day("2026-01-14", try finishedDay(start: d(14))),
         day("2026-01-13", try finishedDay(start: d(13)))]
    }

    private func fixture(_ days: [StoredDay]) -> Fixture {
        let store = MemoryDayStore()
        store.days = days
        let active = Active()
        let model = HistoryModel(store: store, activeDayID: { active.id }, calendar: utc)
        return Fixture(model: model, store: store, active: active)
    }

    // MARK: listing and selection

    @Test func listsNewestFirstAndSelectsTheNewest() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        #expect(f.model.entries.map(\.id) == ["2026-01-15", "2026-01-14", "2026-01-13"])
        #expect(f.model.selection == "2026-01-15")
        #expect(f.model.detail?.mode == .finished)
        #expect(f.model.detail?.planned.first?.start == d(15))
    }

    @Test func theRunningDayIsLeftOut() throws {
        let days = try threeDays()
        let f = fixture(days)
        f.active.id = days[0].snapshot.plan[0].id           // the 15th is the running day
        f.model.refresh()
        #expect(f.model.entries.map(\.id) == ["2026-01-14", "2026-01-13"])
    }

    @Test func aFinishedCurrentDayIsHistory() throws {
        let f = fixture(try threeDays())                    // nothing is running: active id is nil
        f.model.refresh()
        #expect(f.model.entries.count == 3)
    }

    @Test func noDaysIsAnEmptyState() {
        let f = fixture([])
        f.model.refresh()
        #expect(f.model.entries.isEmpty && f.model.selection == nil && f.model.detail == nil)
    }

    @Test func selectingSwapsTheDetailAndIgnoresUnknownIds() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.select("2026-01-13")
        #expect(f.model.selection == "2026-01-13")
        #expect(f.model.detail?.planned.first?.start == d(13))
        f.model.select("nope")
        #expect(f.model.selection == "2026-01-13")
        f.model.select(nil)
        #expect(f.model.selection == nil && f.model.detail == nil)
    }

    @Test func anAbandonedDayHasAFixedDetail() throws {
        let f = fixture([day("2026-01-15", try abandonedDay())])
        f.model.refresh()
        #expect(f.model.entries.first?.isFinished == false)
        #expect(f.model.detail?.summary?.endKind == .lastRecord)
        #expect(f.model.detail?.nowX == nil)
    }

    // MARK: deleting (Review Focus 1 and 2)

    @Test func deletingTheMiddleDayMovesToTheNextOlderOne() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.select("2026-01-14")
        f.model.requestDelete("2026-01-14")
        #expect(f.model.pendingDelete?.id == "2026-01-14")
        f.model.confirmDelete()
        #expect(f.store.deleted.map(\.key) == ["2026-01-14"])
        #expect(f.model.entries.map(\.id) == ["2026-01-15", "2026-01-13"])
        #expect(f.model.selection == "2026-01-13")
        #expect(f.model.detail?.planned.first?.start == d(13))
        #expect(f.model.pendingDelete == nil && !f.model.deleteFailed)
    }

    /// The dialog's button acts on the day the dialog showed, even if the pending request was cleared as it closed.
    @Test func confirmingAnExplicitDayWorksEvenIfThePendingRequestWasCleared() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.requestDelete("2026-01-14")
        let shown = try #require(f.model.pendingDelete)
        f.model.cancelDelete()                              // the dialog's dismissal got there first
        f.model.confirmDelete(shown)
        #expect(f.store.deleted.map(\.key) == ["2026-01-14"])
        #expect(f.model.entries.map(\.id) == ["2026-01-15", "2026-01-13"])
    }

    @Test func confirmingADayThatIsNoLongerListedDoesNothing() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        let stray = HistoryEntry(day: StoredDay(key: "2026-02-01", snapshot: try finishedDay(start: d(20))))
        f.model.confirmDelete(stray)
        #expect(f.store.deleted.isEmpty)
    }

    @Test func deletingTheOldestMovesToTheNewerNeighbour() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.select("2026-01-13")
        f.model.requestDelete("2026-01-13")
        f.model.confirmDelete()
        #expect(f.model.selection == "2026-01-14")
    }

    @Test func deletingAnUnselectedDayKeepsTheSelection() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.requestDelete("2026-01-13")
        f.model.confirmDelete()
        #expect(f.model.selection == "2026-01-15")
        #expect(f.model.entries.count == 2)
    }

    @Test func deletingTheOnlyDayLeavesTheEmptyState() throws {
        let f = fixture([day("2026-01-15", try finishedDay())])
        f.model.refresh()
        f.model.requestDelete("2026-01-15")
        f.model.confirmDelete()
        #expect(f.model.entries.isEmpty && f.model.selection == nil && f.model.detail == nil)
    }

    @Test func cancelChangesNothing() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.requestDelete("2026-01-14")
        f.model.cancelDelete()
        #expect(f.model.pendingDelete == nil)
        #expect(f.store.deleted.isEmpty)
        #expect(f.model.entries.count == 3)
    }

    @Test func theRunningDayAndUnknownIdsCannotBeRequested() throws {
        let days = try threeDays()
        let f = fixture(days)
        f.model.refresh()
        f.active.id = days[1].snapshot.plan[0].id
        f.model.requestDelete("2026-01-14")
        #expect(f.model.pendingDelete == nil)
        f.model.requestDelete("nope")
        #expect(f.model.pendingDelete == nil)
    }

    @Test func aDayThatBecomesTheRunningDayBeforeConfirmingIsNotDeleted() throws {
        let days = try threeDays()
        let f = fixture(days)
        f.model.refresh()
        f.model.requestDelete("2026-01-14")
        f.active.id = days[1].snapshot.plan[0].id           // it started running meanwhile
        f.model.confirmDelete()
        #expect(f.store.deleted.isEmpty)
        #expect(f.model.pendingDelete == nil)
        #expect(f.model.entries.count == 3)
    }

    @Test func aFailedDeletionKeepsTheDayAndSaysSo() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.store.failDelete = true
        f.model.requestDelete("2026-01-14")
        f.model.confirmDelete()
        #expect(f.model.deleteFailed)
        #expect(f.model.entries.count == 3)
        #expect(f.model.pendingDelete == nil)

        f.store.failDelete = false
        f.model.requestDelete("2026-01-14")
        f.model.confirmDelete()
        #expect(!f.model.deleteFailed)
        #expect(f.model.entries.count == 2)
    }

    // MARK: refreshing

    @Test func refreshingKeepsTheSelectionAndPicksUpNewDays() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.select("2026-01-14")
        f.store.days = [day("2026-01-16", try finishedDay(start: d(16)))] + (f.store.days ?? [])
        f.model.refresh()
        #expect(f.model.entries.count == 4)
        #expect(f.model.selection == "2026-01-14")
    }

    @Test func aSelectionThatVanishedAtTheEndFallsToTheNearestDay() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.select("2026-01-13")
        f.store.days?.removeAll { $0.key == "2026-01-13" }
        f.model.refresh()
        #expect(f.model.selection == "2026-01-14")
    }

    @Test func aLoadFailureKeepsWhatWasShown() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.store.failLoad = true
        f.model.refresh()
        #expect(f.model.loadFailed)
        #expect(f.model.entries.count == 3)
        f.store.failLoad = false
        f.model.refresh()
        #expect(!f.model.loadFailed)
    }

    // MARK: review findings

    @Test func theDeleteFailedNoteGoesAwayWhenTheUserMovesOn() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.store.failDelete = true
        f.model.requestDelete("2026-01-14"); f.model.confirmDelete()
        #expect(f.model.deleteFailed)
        f.model.select("2026-01-13")
        #expect(!f.model.deleteFailed)

        f.model.requestDelete("2026-01-14"); f.model.confirmDelete()
        #expect(f.model.deleteFailed)
        f.model.requestDelete("2026-01-15")
        #expect(!f.model.deleteFailed)

        f.model.confirmDelete()
        #expect(f.model.deleteFailed)
        f.store.failDelete = false
        f.model.refresh()
        #expect(!f.model.deleteFailed)
    }

    @Test func aVanishedSelectionFallsToItsNeighbour() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.model.select("2026-01-14")
        f.store.days?.removeAll { $0.key == "2026-01-14" }
        f.model.refresh()
        #expect(f.model.selection == "2026-01-13")                 // the next older day, where it was

        f.model.select("2026-01-13")
        f.store.days?.removeAll { $0.key == "2026-01-13" }
        f.model.refresh()
        #expect(f.model.selection == "2026-01-15")                 // no older day left: the newer neighbour
    }

    @Test func aChangedDayInTheFileIsReportedNotDeleted() throws {
        let f = fixture(try threeDays())
        f.model.refresh()
        f.store.failDeleteWith = DayStoreError.dayChanged
        f.model.requestDelete("2026-01-14")
        f.model.confirmDelete()
        #expect(f.model.deleteFailed)
        #expect(f.model.entries.count == 3)
    }

    @Test func deletingADayTellsWhoWantsToForgetItsTomatoes() throws {
        let store = MemoryDayStore()
        let day = try twoTomatoDay()
        store.days = [StoredDay(key: "2026-01-15", snapshot: day)]
        var forgotten: [SessionSnapshot] = []
        let model = HistoryModel(store: store, activeDayID: { nil }, calendar: utc, onDayDeleted: { forgotten.append($0) })
        model.refresh()
        model.requestDelete("2026-01-15")
        model.confirmDelete()
        #expect(forgotten == [day])
    }

    @Test func aDayThatWasNotDeletedIsNotForgotten() throws {
        let store = MemoryDayStore()
        store.days = [StoredDay(key: "2026-01-15", snapshot: try twoTomatoDay())]
        store.failDelete = true
        var forgotten: [SessionSnapshot] = []
        let model = HistoryModel(store: store, activeDayID: { nil }, calendar: utc, onDayDeleted: { forgotten.append($0) })
        model.refresh()
        model.requestDelete("2026-01-15")
        model.confirmDelete()
        #expect(forgotten.isEmpty)
    }
}
