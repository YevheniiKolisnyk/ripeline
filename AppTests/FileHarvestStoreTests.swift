import Foundation
import Testing
@testable import Ripeline

@MainActor
struct FileHarvestStoreTests {
    private struct Workspace {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ripeline-harvest-\(UUID().uuidString)")
        var file: URL { directory.appendingPathComponent("harvest.json") }
        func names() -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted() }
        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func aMissingFileMeansNothingPicked() throws {
        let w = Workspace(); defer { w.cleanUp() }
        #expect(try FileHarvestStore(file: w.file).load().isEmpty)
        #expect(w.names().isEmpty)                                // loading creates nothing
    }

    @Test func theSetRoundTripsAndTheDirectoryIsCreated() throws {
        let w = Workspace(); defer { w.cleanUp() }
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]
        try FileHarvestStore(file: w.file).save(ids)
        #expect(try FileHarvestStore(file: w.file).load() == ids)   // a new instance, as after a relaunch
        #expect(w.names() == ["harvest.json"])
    }

    @Test func theSameSetIsWrittenAsTheSameBytes() throws {
        let w = Workspace(); defer { w.cleanUp() }
        let ids: Set<UUID> = [UUID(), UUID(), UUID(), UUID()]
        let store = FileHarvestStore(file: w.file)
        try store.save(ids)
        let first = try Data(contentsOf: w.file)
        try store.save(ids)
        #expect(try Data(contentsOf: w.file) == first)
    }

    /// Review focus 3: a damaged file is kept aside and never crashes the app.
    @Test func aDamagedFileIsSetAsideAndReadsAsNothingPicked() throws {
        let w = Workspace(); defer { w.cleanUp() }
        try FileManager.default.createDirectory(at: w.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: w.file)
        #expect(try FileHarvestStore(file: w.file).load().isEmpty)
        #expect(w.names() == ["harvest.json.corrupt"])
        #expect(try Data(contentsOf: w.directory.appendingPathComponent("harvest.json.corrupt")) == Data("not json".utf8))
    }

    @Test func aNewerVersionIsSetAsideAndNeverOverwritten() throws {
        let w = Workspace(); defer { w.cleanUp() }
        try FileManager.default.createDirectory(at: w.directory, withIntermediateDirectories: true)
        let future = Data(#"{"version":2,"picked":[]}"#.utf8)
        try future.write(to: w.file)
        let store = FileHarvestStore(file: w.file)
        #expect(try store.load().isEmpty)
        try store.save([UUID()])
        #expect(w.names() == ["harvest.json", "harvest.json.unsupported"])
        #expect(try Data(contentsOf: w.directory.appendingPathComponent("harvest.json.unsupported")) == future)
    }

    @Test func settingAsideNeverOverwritesAnEarlierAsideFile() throws {
        let w = Workspace(); defer { w.cleanUp() }
        try FileManager.default.createDirectory(at: w.directory, withIntermediateDirectories: true)
        try Data("first".utf8).write(to: w.directory.appendingPathComponent("harvest.json.corrupt"))
        try Data("second".utf8).write(to: w.file)
        _ = try FileHarvestStore(file: w.file).load()
        #expect(w.names() == ["harvest.json.corrupt", "harvest.json.corrupt-2"])
    }

    @Test func theInMemoryStoreKeepsTheSet() throws {
        let store = InMemoryHarvestStore()
        let ids: Set<UUID> = [UUID()]
        try store.save(ids)
        #expect(try store.load() == ids)
    }
}
