import Foundation
import RipelineCore

/// Keeps each day as its own JSON file, `YYYY-MM-DD.json`, in one directory.
///
/// A file holds `{"version": 1, "snapshot": …}`. Files are written atomically. A file that
/// cannot be read is renamed rather than deleted, so nothing the user recorded is ever lost.
@MainActor
final class FileDayStore: DayStore {
    private static let currentVersion = 1
    private let directory: URL
    private let calendar: Calendar
    private let fileManager: FileManager

    init(directory: URL, calendar: Calendar = .current, fileManager: FileManager = .default) {
        self.directory = directory
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// `Application Support/Ripeline/days` inside the app's sandbox container.
    static func defaultDirectory() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Ripeline", isDirectory: true)
            .appendingPathComponent("days", isDirectory: true)
    }

    // MARK: DayStore

    func loadLatest() throws -> StoredDay? {
        for name in try dayFileNames().sorted(by: >) {
            let key = String(name.dropLast(".json".count))
            switch try read(name) {
            case let .snapshot(snapshot):
                return StoredDay(key: key, snapshot: snapshot)
            case .corrupt:
                try setAside(name, suffix: "corrupt")
            case .unsupported:
                try setAside(name, suffix: "unsupported")
            }
        }
        return nil
    }

    func save(_ snapshot: SessionSnapshot) throws {
        guard let start = snapshot.plan.first?.start else { throw DayStoreError.emptyPlan }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: Self.currentVersion, snapshot: snapshot))
        try data.write(to: file(named: "\(key(for: start)).json"), options: .atomic)
    }

    func quarantine(_ day: StoredDay) throws {
        try setAside("\(day.key).json", suffix: "corrupt")
    }

    // MARK: Files

    private struct Envelope: Codable {
        let version: Int
        let snapshot: SessionSnapshot
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    private enum ReadResult {
        case snapshot(SessionSnapshot)
        case corrupt
        case unsupported
    }

    private func read(_ name: String) throws -> ReadResult {
        let data = try Data(contentsOf: file(named: name))
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { return .corrupt }
        if probe.version > Self.currentVersion { return .unsupported }
        guard probe.version == Self.currentVersion,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else { return .corrupt }
        return .snapshot(envelope.snapshot)
    }

    private func setAside(_ name: String, suffix: String) throws {
        let source = file(named: name)
        let target = file(named: "\(name).\(suffix)")
        if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
        try fileManager.moveItem(at: source, to: target)
    }

    private func dayFileNames() throws -> [String] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.wholeMatch(of: /\d{4}-\d{2}-\d{2}\.json/) != nil }
    }

    private func file(named name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
