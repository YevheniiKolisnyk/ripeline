import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct CrateModelTests {
    private func world(days: [SessionSnapshot], picked: (SessionSnapshot) -> [UUID], limit: Int = 300)
        -> (crate: CrateModel, store: MemoryDayStore, garden: GardenModel)
    {
        let store = MemoryDayStore()
        store.days = days.map {
            StoredDay(key: String(format: "2026-01-%02d", utc.component(.day, from: $0.plan[0].start)), snapshot: $0)
        }
        let garden = GardenModel(store: MemoryHarvestStore(picked: Set(days.flatMap(picked))))
        return (CrateModel(store: store, garden: garden, limit: limit), store, garden)
    }

    @Test func onlyPickedTomatoesAreInTheCrateOldestFirst() throws {
        let first = try twoTomatoDay(start: d(15, 9)), second = try twoTomatoDay(start: d(16, 9))
        let w = world(days: [second, first]) { [$0.plan[0].id, $0.plan[2].id] }
        w.crate.refresh()
        #expect(w.crate.total == 4)
        #expect(w.crate.tomatoes.map(\.start) == [d(15, 9), d(15, 9, 30), d(16, 9), d(16, 9, 30)])
        #expect(w.crate.tomatoes.map(\.dayID) == ["2026-01-15", "2026-01-15", "2026-01-16", "2026-01-16"])
        #expect(w.crate.tomatoes.allSatisfy { abs($0.growth - 1) < 1e-9 })
    }

    @Test func anUnpickedTomatoIsNotInTheCrate() throws {
        let day = try twoTomatoDay()
        let w = world(days: [day]) { [$0.plan[0].id] }
        w.crate.refresh()
        #expect(w.crate.total == 1)
        #expect(w.crate.tomatoes.map(\.id) == [day.plan[0].id])
    }

    /// Review focus 4.
    @Test func anEmptyCrateHasNoTomatoesAndNoTotal() {
        let w = world(days: [], picked: { _ in [] })
        w.crate.refresh()
        #expect(w.crate.tomatoes.isEmpty && w.crate.total == 0 && !w.crate.loadFailed)
    }

    /// Review focus 4: only the newest tomatoes are kept, but the total stays honest.
    @Test func theCrateKeepsTheNewestTomatoesAndCountsThemAll() throws {
        let first = try twoTomatoDay(start: d(15, 9)), second = try twoTomatoDay(start: d(16, 9))
        let w = world(days: [second, first], picked: { [$0.plan[0].id, $0.plan[2].id] }, limit: 3)
        w.crate.refresh()
        #expect(w.crate.total == 4)
        #expect(w.crate.tomatoes.map(\.start) == [d(15, 9, 30), d(16, 9), d(16, 9, 30)])
    }

    /// Review focus 5: a picked id whose day no longer exists is not in the crate.
    @Test func idsOfADayThatIsGoneAreNotShown() throws {
        let day = try twoTomatoDay()
        let w = world(days: [day]) { [$0.plan[0].id] }
        w.garden.pick(Tomato(id: UUID(), segmentIndex: 0, workTime: 1, plannedTime: 1, availability: .pickable))
        w.crate.refresh()
        #expect(w.crate.total == 1)
    }

    @Test func aTomatoSizeIsReadAtTheEndOfItsDay() throws {
        // The block was worked for 40 minutes of a planned 25: 160%.
        let day = try playedDay(plan: makePlan([(.work, 25)])) { engine, clock in
            try engine.start()
            clock.set(t(9, 40)); try engine.endDay()
        }
        let w = world(days: [day]) { [$0.plan[0].id] }
        w.crate.refresh()
        let tomato = try #require(w.crate.tomatoes.first)
        #expect(abs(tomato.growth - 1.6) < 1e-9)
    }

    @Test func aFailedReadKeepsWhatWasThereAndSaysSo() throws {
        let day = try twoTomatoDay()
        let w = world(days: [day]) { [$0.plan[0].id] }
        w.crate.refresh()
        w.store.failLoad = true
        w.crate.refresh()
        #expect(w.crate.loadFailed && w.crate.total == 1)
    }
}
