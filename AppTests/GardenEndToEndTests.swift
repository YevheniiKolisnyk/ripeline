import Foundation
import RipelineCore
import Testing
@testable import Ripeline

/// Days and picks over real files: pick, relaunch, the same crate; delete a day, its tomatoes are gone from the file.
@MainActor
struct GardenEndToEndTests {
    private struct World {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-garden-e2e-\(UUID().uuidString)")
        var days: URL { root.appendingPathComponent("days") }
        var harvest: URL { root.appendingPathComponent("harvest.json") }
        func cleanUp() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func picksSurviveARelaunchAndADeletedDaysTomatoesLeave() throws {
        let w = World(); defer { w.cleanUp() }
        let dayStore = FileDayStore(directory: w.days, calendar: utc)
        let first = try twoTomatoDay(start: d(15, 9)), second = try twoTomatoDay(start: d(16, 9))
        try dayStore.save(first); try dayStore.save(second)

        let garden = GardenModel(store: FileHarvestStore(file: w.harvest))
        for snapshot in [first, second] {
            for tomato in Tomatoes.of(snapshot, at: d(17)) { #expect(garden.pick(tomato)) }
        }
        let crate = CrateModel(store: dayStore, garden: garden)
        crate.refresh()
        #expect(crate.total == 4)

        // A relaunch: new store instances over the same files.
        let relaunchedStore = FileDayStore(directory: w.days, calendar: utc)
        let relaunchedGarden = GardenModel(store: FileHarvestStore(file: w.harvest))
        let relaunchedCrate = CrateModel(store: relaunchedStore, garden: relaunchedGarden)
        relaunchedCrate.refresh()
        #expect(relaunchedCrate.tomatoes == crate.tomatoes)

        // Deleting a day in the history takes its tomatoes out of the crate and out of harvest.json.
        let history = HistoryModel(
            store: relaunchedStore, activeDayID: { nil }, calendar: utc,
            onDayDeleted: { relaunchedGarden.forget(day: $0) }
        )
        history.refresh()
        history.requestDelete("2026-01-15")
        history.confirmDelete()
        relaunchedCrate.refresh()
        #expect(relaunchedCrate.total == 2)
        #expect(relaunchedCrate.tomatoes.allSatisfy { $0.dayID == "2026-01-16" })
        let onDisk = try FileHarvestStore(file: w.harvest).load()
        #expect(onDisk == Set([second.plan[0].id, second.plan[2].id]))
    }
}
