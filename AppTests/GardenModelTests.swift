import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct GardenModelTests {
    private func tomato(_ availability: TomatoAvailability = .pickable, id: UUID = UUID()) -> Tomato {
        Tomato(id: id, segmentIndex: 0, workTime: minutes(25), plannedTime: minutes(25), availability: availability)
    }

    @Test func aPickableTomatoIsPickedAndSaved() {
        let store = MemoryHarvestStore()
        let garden = GardenModel(store: store)
        let t = tomato()
        #expect(garden.pick(t))
        #expect(garden.isPicked(t.id))
        #expect(store.picked == [t.id])
    }

    /// Review focus 2.
    @Test(arguments: [TomatoAvailability.upcoming, .growing, .empty])
    func aTomatoThatIsNotPickableIsRefused(availability: TomatoAvailability) {
        let store = MemoryHarvestStore()
        let garden = GardenModel(store: store)
        #expect(garden.pick(tomato(availability)) == false)
        #expect(garden.picked.isEmpty && store.saves.isEmpty)
    }

    @Test func pickingTwiceChangesNothing() {
        let store = MemoryHarvestStore()
        let garden = GardenModel(store: store)
        let t = tomato()
        #expect(garden.pick(t))
        #expect(garden.pick(t) == false)
        #expect(store.saves.count == 1)
    }

    @Test func thePickedSetSurvivesARelaunch() {
        let store = MemoryHarvestStore()
        let t = tomato()
        GardenModel(store: store).pick(t)
        #expect(GardenModel(store: store).isPicked(t.id))
    }

    @Test func forgettingRemovesIdsAndSavesOnlyWhenSomethingChanged() {
        let store = MemoryHarvestStore()
        let garden = GardenModel(store: store)
        let a = tomato(), b = tomato()
        garden.pick(a); garden.pick(b)
        garden.forget([a.id, UUID()])
        #expect(garden.picked == [b.id] && store.picked == [b.id])
        let saves = store.saves.count
        garden.forget([UUID()])
        #expect(store.saves.count == saves)
    }

    @Test func aFailedSaveKeepsThePickInMemoryAndSaysSo() {
        let store = MemoryHarvestStore()
        store.failSave = true
        let garden = GardenModel(store: store)
        let t = tomato()
        #expect(garden.pick(t))
        #expect(garden.isPicked(t.id) && garden.saveFailed)
        store.failSave = false
        garden.pick(tomato())
        #expect(!garden.saveFailed)
        #expect(store.picked.contains(t.id))                      // the earlier pick is written with the next save
    }

    /// Review focus 3: a store that cannot be read must not be overwritten with a nearly empty set.
    @Test func aStoreThatCouldNotBeReadIsNeverWritten() {
        let old = UUID()
        let store = MemoryHarvestStore(picked: [old])
        store.failLoad = true
        let garden = GardenModel(store: store)
        #expect(garden.pick(tomato()))
        #expect(store.saves.isEmpty && store.picked == [old])
    }

    @Test func forgettingADayForgetsEveryWorkBlockOfIt() throws {
        let store = MemoryHarvestStore()
        let garden = GardenModel(store: store)
        let day = try twoTomatoDay()
        let other = UUID()
        garden.pick(tomato(id: day.plan[0].id)); garden.pick(tomato(id: day.plan[2].id)); garden.pick(tomato(id: other))
        garden.forget(day: day)
        #expect(garden.picked == [other] && store.picked == [other])
    }
}
