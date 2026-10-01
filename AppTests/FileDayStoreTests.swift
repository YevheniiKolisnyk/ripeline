import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct FileDayStoreTests {
    /// A fresh temporary directory and a store over it.
    private func makeStore(calendar: Calendar = utc, createDirectory: Bool = true) throws -> (FileDayStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-tests-\(UUID().uuidString)")
        if createDirectory { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return (FileDayStore(directory: url, calendar: calendar), url)
    }

    private func names(in url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    private func dayPlan(_ day: Int) -> [PlannedSegment] { fivePlan(start: d(day)) }

    @Test func roundTripsExactly() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = try startedSnapshot(plan: fivePlan(start: d(15, 9, 3, 27, fraction: 0.123)))
        try store.save(snapshot)
        let loaded = try #require(try store.loadLatest())
        #expect(loaded == StoredDay(key: "2026-01-15", snapshot: snapshot))
    }

    @Test func writesAVersionedEnvelopeToADatedFile() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try idleSnapshot())
        #expect(try names(in: url) == ["2026-01-15.json"])
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url.appendingPathComponent("2026-01-15.json"))) as? [String: Any])
        #expect(object["version"] as? Int == 1)
        #expect(object["snapshot"] is [String: Any])
    }

    @Test func savingTwiceKeepsOneFileWithTheLatestSnapshot() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try idleSnapshot())
        let started = try startedSnapshot()
        try store.save(started)
        #expect(try names(in: url) == ["2026-01-15.json"])
        #expect(try store.loadLatest()?.snapshot == started)
    }

    @Test func createsTheDirectoryWhenSaving() throws {
        let (store, url) = try makeStore(createDirectory: false)
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try idleSnapshot())
        #expect(try names(in: url) == ["2026-01-15.json"])
    }

    @Test func loadsTheMostRecentDay() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        for day in [13, 15, 14] { try store.save(try idleSnapshot(plan: dayPlan(day))) }
        #expect(try store.loadLatest()?.key == "2026-01-15")
    }

    @Test func emptyOrMissingDirectoryHasNoDay() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try store.loadLatest() == nil)
        let (missing, _) = try makeStore(createDirectory: false)
        #expect(try missing.loadLatest() == nil)
    }

    @Test func refusesToSaveAnEmptyPlan() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: DayStoreError.emptyPlan) { try store.save(SessionSnapshot.empty) }
        #expect(try names(in: url).isEmpty)
    }

    @Test func theKeyFollowsTheCalendarTimeZone() throws {
        var plus3 = Calendar(identifier: .gregorian)
        plus3.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        let lateEvening = try idleSnapshot(plan: fivePlan(start: d(15, 23, 30)))

        let (utcStore, utcURL) = try makeStore(calendar: utc)
        let (plusStore, plusURL) = try makeStore(calendar: plus3)
        defer { try? FileManager.default.removeItem(at: utcURL); try? FileManager.default.removeItem(at: plusURL) }
        try utcStore.save(lateEvening)
        try plusStore.save(lateEvening)
        #expect(try utcStore.loadLatest()?.key == "2026-01-15")
        #expect(try plusStore.loadLatest()?.key == "2026-01-16")
    }

    // MARK: damaged and unsupported files

    @Test func corruptLatestFileIsSetAsideAndTheOlderDayIsUsed() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let older = try idleSnapshot(plan: dayPlan(14))
        try store.save(older)
        try Data("{not json".utf8).write(to: url.appendingPathComponent("2026-01-15.json"))
        #expect(try store.loadLatest() == StoredDay(key: "2026-01-14", snapshot: older))
        #expect(try names(in: url) == ["2026-01-14.json", "2026-01-15.json.corrupt"])
    }

    @Test func truncatedFileIsTreatedAsCorrupt() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try startedSnapshot())
        let file = url.appendingPathComponent("2026-01-15.json")
        let whole = try Data(contentsOf: file)
        try whole.prefix(whole.count / 2).write(to: file)
        #expect(try store.loadLatest() == nil)
        #expect(try names(in: url) == ["2026-01-15.json.corrupt"])
    }

    @Test func newerVersionIsSetAsideUntouched() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        let older = try idleSnapshot(plan: dayPlan(14))
        try store.save(older)
        let future = Data(#"{"version": 2, "snapshot": {"somethingNew": true}}"#.utf8)
        try future.write(to: url.appendingPathComponent("2026-01-15.json"))
        #expect(try store.loadLatest()?.key == "2026-01-14")
        #expect(try names(in: url) == ["2026-01-14.json", "2026-01-15.json.unsupported"])
        #expect(try Data(contentsOf: url.appendingPathComponent("2026-01-15.json.unsupported")) == future)
    }

    @Test func quarantineKeepsTheFileButStopsLoadingIt() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try idleSnapshot(plan: dayPlan(14)))
        try store.save(try idleSnapshot(plan: dayPlan(15)))
        let latest = try #require(try store.loadLatest())
        try store.quarantine(latest)
        #expect(try names(in: url) == ["2026-01-14.json", "2026-01-15.json.corrupt"])
        #expect(try store.loadLatest()?.key == "2026-01-14")
    }

    @Test func ignoresFilesThatAreNotDayFiles() throws {
        let (store, url) = try makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        for name in ["notes.txt", ".DS_Store", "2026-1-5.json", "2026-01-15.json.corrupt"] {
            try Data("x".utf8).write(to: url.appendingPathComponent(name))
        }
        #expect(try store.loadLatest() == nil)
        #expect(try names(in: url).count == 4)
    }
}
