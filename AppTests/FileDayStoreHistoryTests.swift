import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct FileDayStoreHistoryTests {
    private func makeStore(calendar: Calendar = utc, in url: URL? = nil) throws -> (FileDayStore, URL) {
        let directory = url ?? FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (FileDayStore(directory: directory, calendar: calendar), directory)
    }

    private func names(_ url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    // MARK: loadAll

    @Test func daysComeBackNewestFirstAndNoneIsLost() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        for start in [d(13), d(15), d(14), d(15, 13)] { try store.save(try finishedDay(start: start)) }
        let keys = try store.loadAll().map(\.key)
        #expect(keys == ["2026-01-15-2", "2026-01-15", "2026-01-14", "2026-01-13"])
    }

    @Test func severalDaysOnOneDate() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        for hour in [9, 13, 16] { try store.save(try finishedDay(start: d(15, hour))) }
        let starts = try store.loadAll().map { $0.snapshot.plan[0].start }
        #expect(starts == [d(15, 16), d(15, 13), d(15, 9)])
    }

    @Test func daysSavedInOtherTimeZonesSortByTheirRealStart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-history-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let (plus3, _) = try makeStore(calendar: calendar(offsetHours: 3), in: directory)
        let (zero, _) = try makeStore(calendar: utc, in: directory)
        try plus3.save(try finishedDay(start: d(14, 22, 30)))      // key 2026-01-15 in +03:00
        try zero.save(try finishedDay(start: d(15, 1, 0)))         // key 2026-01-15 in UTC, later in real time
        let starts = try zero.loadAll().map { $0.snapshot.plan[0].start }
        #expect(starts == [d(15, 1, 0), d(14, 22, 30)])
    }

    /// Review Focus 4: listing is free of side effects and one bad file hides nothing.
    @Test func damagedFilesAreSkippedAndNotRenamed() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(13)))
        try store.save(try finishedDay(start: d(14)))
        try Data("{not json".utf8).write(to: url.appendingPathComponent("2026-01-16.json"))
        try Data(#"{"version": 2, "snapshot": {}}"#.utf8).write(to: url.appendingPathComponent("2026-01-17.json"))
        let before = try names(url)
        #expect(try store.loadAll().map(\.key) == ["2026-01-14", "2026-01-13"])
        #expect(try names(url) == before)
    }

    @Test func anUnreadableEntryDoesNotHideTheRest() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(13)))
        try FileManager.default.createDirectory(at: url.appendingPathComponent("2026-01-16.json"), withIntermediateDirectories: false)
        #expect(try store.loadAll().map(\.key) == ["2026-01-13"])
    }

    @Test func emptyAndMissingDirectories() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        #expect(try store.loadAll().isEmpty)
        try FileManager.default.removeItem(at: url)
        #expect(try store.loadAll().isEmpty)
    }

    @Test func setAsideFilesAreNotListed() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(13)))
        try Data("x".utf8).write(to: url.appendingPathComponent("2026-01-14.json.corrupt"))
        try Data("x".utf8).write(to: url.appendingPathComponent("2026-01-15.json.unsupported"))
        #expect(try store.loadAll().map(\.key) == ["2026-01-13"])
    }

    // MARK: delete

    @Test func deletingRemovesOnlyThatDay() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        for start in [d(13), d(14), d(15)] { try store.save(try finishedDay(start: start)) }
        let middle = try #require(try store.loadAll().first { $0.key == "2026-01-14" })
        try store.delete(middle)
        #expect(try names(url) == ["2026-01-13.json", "2026-01-15.json"])
        #expect(try store.loadAll().map(\.key) == ["2026-01-15", "2026-01-13"])
    }

    /// Review Focus 1.
    @Test func deletingNeverTouchesSetAsideFilesOrOtherDays() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(13)))
        try store.save(try finishedDay(start: d(15)))
        try Data("keep".utf8).write(to: url.appendingPathComponent("2026-01-15.json.corrupt"))
        try Data("keep".utf8).write(to: url.appendingPathComponent("2026-01-13.json.unsupported"))
        let day = try #require(try store.loadAll().first { $0.key == "2026-01-15" })
        try store.delete(day)
        #expect(try names(url) == ["2026-01-13.json", "2026-01-13.json.unsupported", "2026-01-15.json.corrupt"])
    }

    @Test func deletingTwiceOrAVanishedDayIsSafe() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(13)))
        let day = try #require(try store.loadAll().first)
        try store.delete(day)
        try store.delete(day)
        try store.delete(StoredDay(key: "2026-02-01", snapshot: day.snapshot))
        #expect(try store.loadAll().isEmpty)
    }

    @Test func aKeyThatIsNotADayFileNameIsRefused() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(13)))
        let day = try #require(try store.loadAll().first)
        try Data("outside".utf8).write(to: url.deletingLastPathComponent().appendingPathComponent("ripeline-outside-\(url.lastPathComponent).json"))
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().appendingPathComponent("ripeline-outside-\(url.lastPathComponent).json")) }
        for key in ["../ripeline-outside-\(url.lastPathComponent)", "notes", "2026-01-13.json", "", "../../x"] {
            #expect(throws: DayStoreError.invalidKey) { try store.delete(StoredDay(key: key, snapshot: day.snapshot)) }
        }
        #expect(try names(url) == ["2026-01-13.json"])
    }

    @Test func aFailedDeletionKeepsTheFile() throws {
        let (store, url) = try makeStore(); defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            try? FileManager.default.removeItem(at: url)
        }
        try store.save(try finishedDay(start: d(13)))
        try store.save(try finishedDay(start: d(14)))
        let day = try #require(try store.loadAll().first { $0.key == "2026-01-13" })
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)   // read-only directory
        #expect(throws: (any Error).self) { try store.delete(day) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        #expect(try names(url) == ["2026-01-13.json", "2026-01-14.json"])
    }

    @Test func aDeletedDaysNameCanBeUsedAgain() throws {
        let (store, url) = try makeStore(); defer { try? FileManager.default.removeItem(at: url) }
        try store.save(try finishedDay(start: d(15)))
        try store.delete(try #require(try store.loadAll().first))
        try store.save(try finishedDay(start: d(15, 13)))
        #expect(try names(url) == ["2026-01-15.json"])
    }
}
