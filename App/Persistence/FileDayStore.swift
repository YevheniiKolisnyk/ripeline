import Foundation
import RipelineCore

/// Keeps each day as its own JSON file in one directory: `YYYY-MM-DD.json`, and
/// `YYYY-MM-DD-2.json`, `-3`, … for further days that start on the same date.
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
        for name in try dayFileNames() {
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
        try data.write(to: file(named: try fileName(for: snapshot, startingAt: start)), options: .atomic)
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

    /// Day files, newest first: by date, then by number within a date.
    private func dayFileNames() throws -> [String] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let parsed = try fileManager.contentsOfDirectory(atPath: directory.path).compactMap {
            name -> (name: String, date: String, sequence: Int)? in
            guard let match = name.wholeMatch(of: /(\d{4}-\d{2}-\d{2})(?:-(\d+))?\.json/) else { return nil }
            return (name, String(match.1), match.2.flatMap { Int($0) } ?? 1)
        }
        return parsed
            .sorted { ($0.date, $0.sequence) > ($1.date, $1.sequence) }
            .map(\.name)
    }

    /// The file this snapshot belongs in: its own file if it was saved before, otherwise the
    /// first free number on its date. A second day on one date never overwrites the first.
    private func fileName(for snapshot: SessionSnapshot, startingAt start: Date) throws -> String {
        let date = key(for: start)
        let dayID = snapshot.plan.first?.id
        var sequence = 1
        while true {
            let name = sequence == 1 ? "\(date).json" : "\(date)-\(sequence).json"
            guard fileManager.fileExists(atPath: file(named: name).path) else { return name }
            if case let .snapshot(existing)? = try? read(name), existing.plan.first?.id == dayID { return name }
            sequence += 1
        }
    }

    private func file(named name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    private func key(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
