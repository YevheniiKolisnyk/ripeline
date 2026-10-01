import Foundation
import os

/// Keeps the picked ids in one JSON file, `{"version": 1, "picked": ["<segment id>", …]}`, written
/// atomically with sorted ids so the same set is always the same bytes. A file that cannot be read is
/// renamed aside, never deleted or overwritten.
@MainActor
final class FileHarvestStore: HarvestStore {
    private static let currentVersion = 1
    private let file: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "storage")

    init(file: URL, fileManager: FileManager = .default) {
        self.file = file
        self.fileManager = fileManager
    }

    /// `Application Support/Ripeline/harvest.json` inside the app's sandbox container.
    static func defaultFile() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Ripeline", isDirectory: true)
            .appendingPathComponent("harvest.json", isDirectory: false)
    }

    func load() throws -> Set<UUID> {
        guard fileManager.fileExists(atPath: file.path) else { return [] }
        let data = try Data(contentsOf: file)
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            try setAside("corrupt")
            return []
        }
        if probe.version > Self.currentVersion {
            try setAside("unsupported")
            return []
        }
        guard probe.version == Self.currentVersion, let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            try setAside("corrupt")
            return []
        }
        return Set(envelope.picked)
    }

    func save(_ picked: Set<UUID>) throws {
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let ids = picked.sorted { $0.uuidString < $1.uuidString }
        try encoder.encode(Envelope(version: Self.currentVersion, picked: ids)).write(to: file, options: .atomic)
    }

    private struct Envelope: Codable {
        let version: Int
        let picked: [UUID]
    }

    private struct VersionProbe: Decodable {
        let version: Int
    }

    /// Renames the file so it is kept but no longer loaded; counts up (`.corrupt`, `.corrupt-2`) if the name is taken.
    private func setAside(_ suffix: String) throws {
        var target = file.appendingPathExtension(suffix)
        var number = 2
        while fileManager.fileExists(atPath: target.path) {
            target = file.deletingLastPathComponent().appendingPathComponent("\(file.lastPathComponent).\(suffix)-\(number)")
            number += 1
        }
        try fileManager.moveItem(at: file, to: target)
        logger.error("Set aside the harvest file as \(target.lastPathComponent, privacy: .public)")
    }
}
