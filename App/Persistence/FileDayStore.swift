import Foundation
import os
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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "storage")
    /// Which file each day lives in, learned by loading and saving. A day keeps its file even if
    /// the calendar's time zone changes between launches.
    private var fileForDay: [UUID: String] = [:]

    init(directory: URL, calendar: Calendar = .autoupdatingCurrent, fileManager: FileManager = .default) {
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

    /// The day that started last. Files are judged two dates at a time (the newest two), because
    /// a change of time zone can shift a day's date key by one; among those, the later start wins.
    /// A file that cannot be read is logged and skipped, never fatal, so it cannot hide older days.
    func loadLatest() throws -> StoredDay? {
        var remaining = try dayFiles()
        while !remaining.isEmpty {
            var batchDates: [String] = []
            for file in remaining where !batchDates.contains(file.date) && batchDates.count < 2 {
                batchDates.append(file.date)
            }
            let batch = remaining.filter { batchDates.contains($0.date) }
            remaining.removeAll { batchDates.contains($0.date) }

            var best: StoredDay?
            for file in batch {
                do {
                    switch try read(file.name) {
                    case let .snapshot(snapshot):
                        if let id = snapshot.plan.first?.id { fileForDay[id] = file.name }
                        let day = StoredDay(key: String(file.name.dropLast(".json".count)), snapshot: snapshot)
                        if let current = best?.snapshot.plan.first?.start,
                           let start = snapshot.plan.first?.start, start <= current { continue }
                        best = day
                    case .corrupt:
                        try setAside(file.name, suffix: "corrupt")
                    case .unsupported:
                        try setAside(file.name, suffix: "unsupported")
                    }
                } catch {
                    logger.error("Skipping \(file.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            if let best { return best }
        }
        return nil
    }

    func save(_ snapshot: SessionSnapshot) throws {
        guard let start = snapshot.plan.first?.start else { throw DayStoreError.emptyPlan }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: Self.currentVersion, snapshot: snapshot))
        let name = try fileName(for: snapshot, startingAt: start)
        try data.write(to: file(named: name), options: .atomic)
        if let id = snapshot.plan.first?.id { fileForDay[id] = name }
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

    /// Renames a file so it is kept but no longer loaded. Never overwrites or deletes anything:
    /// if the new name is taken it counts up (`.corrupt`, `.corrupt-2`, …).
    private func setAside(_ name: String, suffix: String) throws {
        var target = "\(name).\(suffix)"
        var number = 2
        while fileManager.fileExists(atPath: file(named: target).path) {
            target = "\(name).\(suffix)-\(number)"
            number += 1
        }
        try fileManager.moveItem(at: file(named: name), to: file(named: target))
    }

    private struct DayFile {
        let name: String
        let date: String
        let sequence: Int
    }

    /// Day files, newest first by name: by date, then by number within a date.
    private func dayFiles() throws -> [DayFile] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(atPath: directory.path).compactMap { name -> DayFile? in
            guard let match = name.wholeMatch(of: /(\d{4}-\d{2}-\d{2})(?:-(\d+))?\.json/) else { return nil }
            return DayFile(name: name, date: String(match.1), sequence: match.2.flatMap { Int($0) } ?? 1)
        }
        .sorted { ($0.date, $0.sequence) > ($1.date, $1.sequence) }
    }

    /// The file this snapshot belongs in: its own file if it was saved before, otherwise the
    /// first free number on its date. A second day on one date never overwrites the first.
    private func fileName(for snapshot: SessionSnapshot, startingAt start: Date) throws -> String {
        let date = key(for: start)
        let dayID = snapshot.plan.first?.id
        if let dayID, let known = fileForDay[dayID], fileManager.fileExists(atPath: file(named: known).path) {
            return known
        }
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
