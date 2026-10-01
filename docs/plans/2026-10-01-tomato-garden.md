# Tomato garden Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every work block is a cartoon tomato that grows with the work really done in it, can be picked once the block is over, and ends up in a big physics crate in the history.

**Architecture:** `RipelineCore` gets a pure `Tomatoes.of(snapshot, at:)` that derives each work block's growth from the recorded intervals; nothing in the day files changes. The app stores the picked ids in its own `harvest.json`, models the garden (`GardenModel`) and the crate (`CrateModel`), draws the tomatoes in SwiftUI (`TomatoArt`), and drops them into a SpriteKit crate in the History tab.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, SpriteKit (`SpriteView`), Swift Testing, String Catalog (`en`, `uk`).

**Spec:** [`docs/specs/2026-10-01-tomato-garden-design.md`](../specs/2026-10-01-tomato-garden-design.md). This plan's PR also amends the spec in five places (see "Spec amendments"); executors read the amended spec.

## Global Constraints

- Public APIs only. App Sandbox with only `com.apple.security.app-sandbox`. No network, no analytics.
- No personal data in the repo; no new entitlement. All code, comments, docs and commit messages in English.
- Every user-facing string goes through the String Catalog (`en` + `uk`). Strings that are looked up with `bundle.localizedString(forKey:)` need `"extractionState": "manual"` in the catalog (Xcode rewrites the catalog on build and marks keys it cannot see in source as `stale`).
- `RipelineCore` imports `Foundation` only, exposes no user-facing text, public types are `Sendable`, public API has `///` doc comments. Time is derived from `Date`s, never a counter; no `Date()` in domain logic.
- Swift Testing only; tests never wait in real time; dates come from the fixed UTC fixtures (`t(...)`, `d(...)`).
- Day files are never rewritten or touched by this feature. Tests must never touch the developer's real files or the notification center.
- Commit messages: imperative, English, **no `Co-Authored-By` or other attribution lines** (the user is the sole author).
- Tests pass with zero warnings before a task is complete: `swift test --package-path Packages/RipelineCore` and `scripts/test-app.sh`.

## Spec amendments (made in the same PR as this plan)

1. `Tomato.availability` has a fourth case `.upcoming` (a block that has not started in a day that is not over); a block that never started in a finished day is `.empty`.
2. Deleting a day *forgets* its ids; nothing is pruned on load (a day unreadable for a moment must not lose its picks).
3. The palette is fixed in code, not asset-catalog tokens with dark variants.
4. Counts are "label: number" strings, so no plural variations.
5. A tomato's size in the crate is read at the last record of its day.

## Review Focus

Input classes and failure modes the spec implies; each has a test in the task that owns the code.

1. A block extended with "+5 min" keeps growing past 100% but cannot be picked while it still runs or is paused (Task 1).
2. Picking the same tomato twice, or one that is not pickable, changes nothing (Task 3).
3. A corrupt, newer-version or unreadable `harvest.json` never crashes the app and never overwrites what is on disk by accident (Task 2, Task 3).
4. A crate with no tomatoes, one, and more than 300 builds without crashing; the total stays honest (Task 3, Task 6).
5. Deleting a day in the history removes its tomatoes from the crate and from the picked set (Task 3).

## File Structure

| File | Responsibility |
|---|---|
| `Packages/RipelineCore/Sources/RipelineCore/Garden/Tomato.swift` (new) | `Tomato`, `TomatoAvailability`, `Tomatoes.of`, `SessionEngine.tomatoes()` |
| `App/Persistence/HarvestStore.swift` (new) | `HarvestStore` protocol, `InMemoryHarvestStore` |
| `App/Persistence/FileHarvestStore.swift` (new) | `harvest.json` on disk |
| `App/Garden/GardenModel.swift` (new) | the picked set; picking and forgetting |
| `App/Garden/CrateModel.swift` (new) | what the crate holds; `CrateTomato` |
| `App/Garden/TomatoLook.swift` (new) | pure mapping growth → stage, colour, scale, face; the palette |
| `App/Garden/GardenText.swift` (new) | localized labels and VoiceOver text |
| `App/Garden/TomatoArt.swift` (new) | the cartoon drawing (SwiftUI shapes) |
| `App/Garden/TomatoButton.swift` (new) | a tomato that can be picked; `TomatoPatchView` for the popover |
| `App/Garden/GardenBedView.swift` (new) | the bed row above the timelines |
| `App/Garden/TomatoTextures.swift` (new) | `SKTexture`s rendered from `TomatoArt` |
| `App/Garden/CrateGeometry.swift`, `CrateScene.swift`, `CrateArt.swift`, `CrateView.swift` (new) | the crate |
| modify `SessionController`, `DayOverviewModel`, `SnapshotSource`, `HistoryModel`, `AppEnvironment`, `RipelineApp`, `PopoverView`, `TimelineRowsView`, `HistoryView`, `Localizable.xcstrings` | wiring |

---

### Task 1: Tomatoes in the core

**Files:**
- Create: `Packages/RipelineCore/Sources/RipelineCore/Garden/Tomato.swift`
- Test: `Packages/RipelineCore/Tests/RipelineCoreTests/TomatoTests.swift`

**Interfaces:**
- Consumes: `SessionSnapshot` (`plan`, `actuals(at:)`, `state`, internal `catchUp(to:)`), `SessionEngine.currentInstant()`.
- Produces:
  - `public enum TomatoAvailability: Sendable, Equatable { case upcoming, growing, pickable, empty }`
  - `public struct Tomato: Sendable, Equatable, Identifiable` with `id: UUID` (the segment's id), `segmentIndex: Int`, `workTime: TimeInterval`, `plannedTime: TimeInterval`, `availability`, `var growth: Double` (`workTime / plannedTime`), and a public memberwise `init(id:segmentIndex:workTime:plannedTime:availability:)`.
  - `public enum Tomatoes { public static func of(_ snapshot: SessionSnapshot, at now: Date) -> [Tomato] }`
  - `extension SessionEngine { public func tomatoes() -> [Tomato] }`

- [ ] **Step 1: Write the failing tests** — `TomatoTests.swift`

```swift
import Foundation
import Testing
@testable import RipelineCore

struct TomatoTests {
    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    /// Work 25, break 5, work 25 from 09:00, started at 09:00.
    private func started(kind: SessionKind = .day) throws -> (engine: SessionEngine, clock: ManualClock) {
        let clock = ManualClock(t(9))
        var engine = SessionEngine(clock: clock)
        try engine.startDay(plan: makePlan([(.work, 25), (.shortBreak, 5), (.work, 25)]), settings: SessionSettings(), kind: kind)
        try engine.start()
        return (engine, clock)
    }

    @Test func aBlockGrowsWithTheWorkDoneAndIsFullAtThePlannedLength() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 10))
        var first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 0.4))
        #expect(first.availability == .growing)
        clock.set(t(9, 25))
        first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 1))
        #expect(first.availability == .pickable)          // it waits in overtime
    }

    @Test func aPauseDoesNotGrowTheTomato() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        clock.set(t(9, 10)); try engine.pause()
        clock.set(t(9, 20)); try engine.resume()
        clock.set(t(9, 25))
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.workTime, minutes(15)))
        #expect(close(first.growth, 0.6))
        #expect(first.availability == .growing)
    }

    /// Review focus 1: extra time grows the tomato past 100% but it stays unpickable while the block runs.
    @Test func anExtendedBlockGrowsPastFullButIsNotPickableWhileItRuns() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        clock.set(t(9, 20)); try engine.extend(minutes: 10)       // now ends at 09:35
        clock.set(t(9, 30))
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 1.2))
        #expect(first.availability == .growing)
        clock.set(t(9, 35))                                        // the extension ran out: overtime
        #expect(try #require(engine.tomatoes().first).availability == .pickable)
    }

    @Test func overtimeKeepsGrowingTheTomato() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 40))                                        // 15 minutes past the plan
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 1.6))
        #expect(first.availability == .pickable)
    }

    @Test func aSkippedBlockIsPickableWhenSomeWorkWasDone() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        clock.set(t(9, 10)); try engine.skip()
        let first = try #require(engine.tomatoes().first)
        #expect(close(first.growth, 0.4))
        #expect(first.availability == .pickable)
    }

    @Test func aBlockSkippedBeforeAnyWorkGivesNothing() throws {
        var engine = try started().engine
        try engine.skip()
        let first = try #require(engine.tomatoes().first)
        #expect(first.workTime == 0)
        #expect(first.availability == .empty)
    }

    @Test func breaksGiveNoTomatoAndIdsAreTheSegmentIds() throws {
        let (engine, _) = try started()
        let tomatoes = engine.tomatoes()
        let plan = engine.snapshot.plan
        #expect(tomatoes.map(\.segmentIndex) == [0, 2])
        #expect(tomatoes.map(\.id) == [plan[0].id, plan[2].id])
        #expect(tomatoes.map(\.plannedTime) == [minutes(25), minutes(25)])
    }

    @Test func aBlockThatHasNotStartedIsUpcomingUntilItsDayEnds() throws {
        let made = try started()
        var engine = made.engine
        let clock = made.clock
        #expect(engine.tomatoes()[1].availability == .upcoming)
        #expect(engine.tomatoes()[1].growth == 0)
        clock.set(t(9, 10)); try engine.endDay()
        #expect(engine.tomatoes()[0].availability == .pickable)
        #expect(engine.tomatoes()[1].availability == .empty)
    }

    @Test func aDayThatIsLoadedButNotStartedHasOnlyUpcomingTomatoes() throws {
        let (engine, _) = try makeEngine(plan: makePlan([(.work, 25), (.shortBreak, 5), (.work, 25)]))
        #expect(engine.tomatoes().map(\.availability) == [.upcoming, .upcoming])
    }

    @Test func aQuickSessionGivesATomatoToEveryBlockItGrows() throws {
        let clock = ManualClock(t(9))
        var engine = SessionEngine(clock: clock)
        try engine.startDay(plan: makePlan([(.work, 25)]), settings: SessionSettings(), kind: .quick)
        try engine.start()
        try engine.appendSegments([
            PlannedSegment(index: 1, kind: .shortBreak, start: t(9, 25), end: t(9, 30)),
            PlannedSegment(index: 2, kind: .work, start: t(9, 30), end: t(9, 55)),
        ])
        #expect(engine.tomatoes().map(\.segmentIndex) == [0, 2])
        #expect(engine.tomatoes()[1].availability == .upcoming)
    }

    @Test func readingTomatoesNeverChangesTheEngine() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 40))
        let before = engine.snapshot
        _ = engine.tomatoes()
        #expect(engine.snapshot == before)
    }

    @Test func aClockSetBackNeverGivesNegativeWork() throws {
        let (engine, clock) = try started()
        clock.set(t(9, 10))
        _ = engine.tomatoes()
        clock.set(t(8, 0))
        let first = try #require(engine.tomatoes().first)
        #expect(first.workTime >= 0)
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/RipelineCore --filter TomatoTests`
Expected: FAIL to compile (`engine.tomatoes()` and `Tomato` do not exist).

- [ ] **Step 3: Implement** — `Garden/Tomato.swift`

```swift
import Foundation

/// Whether a work block's tomato can be picked.
public enum TomatoAvailability: Sendable, Equatable {
    /// The block has not started, and its day is not over.
    case upcoming
    /// The block is running or paused: the tomato is still growing.
    case growing
    /// The block is over, or waits in overtime, and some work was recorded in it.
    case pickable
    /// The block is over, or its day ended before it started, and no work was recorded in it.
    case empty
}

/// The tomato of one work block. It is derived from the record, never stored.
public struct Tomato: Sendable, Equatable, Identifiable {
    /// The id of the work segment, stable across relaunches.
    public let id: UUID
    /// The segment's position in the plan.
    public let segmentIndex: Int
    /// Seconds of recorded work in the block, including extensions and overtime.
    public let workTime: TimeInterval
    /// The planned length of the block, in seconds.
    public let plannedTime: TimeInterval
    /// Whether it can be picked.
    public let availability: TomatoAvailability

    /// How grown it is: 1.0 is 100% (the planned length worked); more than 1 is work beyond the plan.
    public var growth: Double { workTime / plannedTime }

    /// A tomato of the given figures; `plannedTime` must be positive.
    public init(id: UUID, segmentIndex: Int, workTime: TimeInterval, plannedTime: TimeInterval, availability: TomatoAvailability) {
        self.id = id
        self.segmentIndex = segmentIndex
        self.workTime = workTime
        self.plannedTime = plannedTime
        self.availability = availability
    }
}

/// Derives the tomatoes of a day from its record.
public enum Tomatoes {
    /// One tomato per work segment, in plan order, as of `now`. The day is first caught up with `now`
    /// and the interval being recorded counts up to it. Paused and untracked time is not work; breaks
    /// give no tomato.
    public static func of(_ snapshot: SessionSnapshot, at now: Date) -> [Tomato] {
        var current = snapshot
        current.catchUp(to: now)
        let actuals = current.actuals(at: now)
        var overtimeIndex: Int?
        if case let .overtime(index, _) = current.state { overtimeIndex = index }
        let dayIsOver = current.state == .finished

        var result: [Tomato] = []
        for segment in current.plan where segment.kind == .work {
            let actual = actuals[segment.index]
            var work: TimeInterval = 0
            for interval in actual.intervals where interval.kind == .work { work += interval.duration }
            let availability: TomatoAvailability
            switch actual.status {
            case .notStarted:
                availability = dayIsOver ? .empty : .upcoming
            case .active:
                availability = segment.index == overtimeIndex && work > 0 ? .pickable : .growing
            case .completed, .skipped:
                availability = work > 0 ? .pickable : .empty
            }
            result.append(Tomato(
                id: segment.id, segmentIndex: segment.index, workTime: work,
                plannedTime: segment.duration, availability: availability
            ))
        }
        return result
    }
}

extension SessionEngine {
    /// The tomatoes of the day as of the current time, like `timeline()`.
    public func tomatoes() -> [Tomato] {
        Tomatoes.of(snapshot, at: currentInstant())
    }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `swift test --package-path Packages/RipelineCore --filter TomatoTests`
Expected: all `TomatoTests` pass. If `aBlockSkippedBeforeAnyWorkGivesNothing` fails because a zero-length interval was recorded, `workTime` is still 0, so the assertion on `.empty` must hold; investigate before touching the test.

- [ ] **Step 5: Full core suite, then commit**

Run: `swift test --package-path Packages/RipelineCore 2>&1 | tail -5`
Expected: all tests pass, no warnings.

```bash
git add Packages/RipelineCore
git commit -m "Derive the tomatoes of a day from its record"
```

---

### Task 2: The harvest store

**Files:**
- Create: `App/Persistence/HarvestStore.swift`, `App/Persistence/FileHarvestStore.swift`
- Create: `AppTests/Support/MemoryHarvestStore.swift`
- Test: `AppTests/FileHarvestStoreTests.swift`

**Interfaces:**
- Produces:
  - `@MainActor protocol HarvestStore { func load() throws -> Set<UUID>; func save(_ picked: Set<UUID>) throws }`
  - `InMemoryHarvestStore` (production, for the inert environment and as the fallback).
  - `FileHarvestStore(file: URL, fileManager:)` and `static func defaultFile() throws -> URL` (`Application Support/Ripeline/harvest.json`).
  - Test double `MemoryHarvestStore` with `picked`, `failLoad`, `failSave`, `saves`.

- [ ] **Step 1: Write the failing tests** — `FileHarvestStoreTests.swift`

```swift
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
```

- [ ] **Step 2: Run to see them fail**

Run: `scripts/test-app.sh FileHarvestStoreTests`
Expected: compile error (`FileHarvestStore` is not defined).

- [ ] **Step 3: Implement**

`App/Persistence/HarvestStore.swift`:

```swift
import Foundation

/// Where the ids of the picked tomatoes are kept between launches. Separate from the days, so a day
/// file is never rewritten when a tomato is picked.
@MainActor protocol HarvestStore {
    /// The ids of the picked tomatoes; empty when nothing was ever picked.
    func load() throws -> Set<UUID>
    /// Replaces the stored set.
    func save(_ picked: Set<UUID>) throws
}

/// A `HarvestStore` that keeps the set in memory only. Used when the real directory cannot be
/// created, and by the inert environment under test.
@MainActor
final class InMemoryHarvestStore: HarvestStore {
    private var picked: Set<UUID> = []
    func load() throws -> Set<UUID> { picked }
    func save(_ picked: Set<UUID>) throws { self.picked = picked }
}
```

`App/Persistence/FileHarvestStore.swift`:

```swift
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
```

`AppTests/Support/MemoryHarvestStore.swift`:

```swift
import Foundation
@testable import Ripeline

/// An in-memory `HarvestStore` that records what happens to it and can be made to fail.
@MainActor
final class MemoryHarvestStore: HarvestStore {
    struct Failure: Error {}

    var picked: Set<UUID>
    var failLoad = false
    var failSave = false
    private(set) var saves: [Set<UUID>] = []

    init(picked: Set<UUID> = []) { self.picked = picked }

    func load() throws -> Set<UUID> {
        if failLoad { throw Failure() }
        return picked
    }

    func save(_ picked: Set<UUID>) throws {
        if failSave { throw Failure() }
        self.picked = picked
        saves.append(picked)
    }
}
```

- [ ] **Step 4: Run to see them pass**

Run: `scripts/test-app.sh FileHarvestStoreTests`
Expected: `** TEST SUCCEEDED **`, no warnings.

- [ ] **Step 5: Commit**

```bash
git add App/Persistence AppTests
git commit -m "Keep the picked tomatoes in their own file"
```

---

### Task 3: The garden and the crate models, wired in

**Files:**
- Create: `App/Garden/GardenModel.swift`, `App/Garden/CrateModel.swift`
- Modify: `App/Runtime/SessionController.swift`, `App/Overview/DayOverviewModel.swift`, `App/History/SnapshotSource.swift`, `App/History/HistoryModel.swift`, `App/AppEnvironment.swift`, `AppTests/Support/EngineSource.swift`, `AppTests/Support/Fixtures.swift`
- Test: `AppTests/GardenModelTests.swift`, `AppTests/CrateModelTests.swift`, `AppTests/SessionControllerTomatoTests.swift`, additions to `AppTests/HistoryModelTests.swift` and `AppTests/DayOverviewModelTests.swift`

**Interfaces:**
- Consumes: `Tomato`, `Tomatoes.of`, `SessionEngine.tomatoes()` (Task 1); `HarvestStore`, `MemoryHarvestStore` (Task 2); `DayStore.loadAll()`, `StoredDay`, `SnapshotSource.lastRecordedInstant(of:)`.
- Produces:
  - `GardenModel(store:)`: `picked: Set<UUID>`, `isPicked(_:)`, `@discardableResult pick(_ tomato: Tomato) -> Bool`, `forget(_ ids: some Sequence<UUID>)`, `saveFailed: Bool`.
  - `CrateTomato { id: UUID; dayID: String; growth: Double; start: Date }` (`Equatable`, `Identifiable`, `Sendable`).
  - `CrateModel(store: any DayStore, garden: GardenModel, limit: Int = 300)`: `tomatoes: [CrateTomato]` (oldest first), `total: Int`, `loadFailed`, `refresh()`.
  - `SessionController.tomatoes: [Tomato]`.
  - `DayOverviewSource.overviewTomatoes: [Tomato]` (default `[]`) and `DayOverviewModel.bed: [BedPlot]`, `BedPlot { tomato: Tomato; x: Double; width: Double }` (`x` is the block's centre, 0…1).
  - `HistoryModel.init(…, onDayDeleted: @escaping @MainActor (SessionSnapshot) -> Void = { _ in })`.
  - `AppEnvironment.garden: GardenModel`, `AppEnvironment.crateModel: CrateModel`.

- [ ] **Step 1: Add fixtures** — in `AppTests/Support/Fixtures.swift` append:

```swift
/// A day with two worked blocks of 25 minutes (09:00 and 09:30 from `start`), ended after the second.
/// Both tomatoes are pickable and fully grown. Plan indices 0 and 2 are the work blocks.
func twoTomatoDay(start: Date = t(9)) throws -> SessionSnapshot {
    try playedDay(plan: makePlan(start: start, [(.work, 25), (.shortBreak, 5), (.work, 25)])) { engine, clock in
        try engine.start()
        clock.set(start.addingTimeInterval(minutes(25))); try engine.skip()      // the first block, done
        clock.set(start.addingTimeInterval(minutes(30))); try engine.advance()   // the break ran out; on to the second
        clock.set(start.addingTimeInterval(minutes(55))); try engine.endDay()
    }
}
```

If `skip()` or `advance()` are refused at those instants in the real engine, read the error and adjust the instants, not the assertions below: the aim is two blocks with 25 minutes of recorded work each.

- [ ] **Step 2: Write the failing tests**

`AppTests/GardenModelTests.swift`:

```swift
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
}
```

`AppTests/CrateModelTests.swift`:

```swift
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
        store.days = days.map { StoredDay(key: String(format: "2026-01-%02d", utc.component(.day, from: $0.plan[0].start)), snapshot: $0) }
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
        // The second block was worked for 40 minutes of a planned 25: 160%.
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
```

Append to `AppTests/HistoryModelTests.swift` (follow the file's existing helpers for building a model over a `MemoryDayStore`):

```swift
    @Test func deletingADayTellsWhoWantsToForgetItsTomatoes() throws {
        let store = MemoryDayStore()
        let day = try twoTomatoDay()
        store.days = [StoredDay(key: "2026-01-15", snapshot: day)]
        var forgotten: [SessionSnapshot] = []
        let model = HistoryModel(store: store, activeDayID: { nil }, calendar: utc, onDayDeleted: { forgotten.append($0) })
        model.refresh()
        model.requestDelete("2026-01-15")
        model.confirmDelete()
        #expect(forgotten == [day])
    }

    @Test func aDayThatWasNotDeletedIsNotForgotten() throws {
        let store = MemoryDayStore()
        store.days = [StoredDay(key: "2026-01-15", snapshot: try twoTomatoDay())]
        store.failDelete = true
        var forgotten: [SessionSnapshot] = []
        let model = HistoryModel(store: store, activeDayID: { nil }, calendar: utc, onDayDeleted: { forgotten.append($0) })
        model.refresh()
        model.requestDelete("2026-01-15")
        model.confirmDelete()
        #expect(forgotten.isEmpty)
    }
```

`AppTests/SessionControllerTomatoTests.swift`:

```swift
import Foundation
import RipelineCore
import Testing
@testable import Ripeline

@MainActor
struct SessionControllerTomatoTests {
    @Test func theTomatoOfTheRunningBlockGrowsWithTheClock() async throws {
        let h = Harness(); defer { h.cleanUp() }
        await h.controller.startQuickSession(length: .short)
        await settleBackgroundWork()
        h.clock.set(t(9, 10)); h.controller.refresh()
        let growing = try #require(h.controller.tomatoes.first)
        #expect(abs(growing.growth - 0.4) < 1e-9 && growing.availability == .growing)
        h.clock.set(t(9, 25)); h.controller.refresh()
        #expect(h.controller.tomatoes.first?.availability == .pickable)
    }

    @Test func noDayHasNoTomatoes() {
        let h = Harness(); defer { h.cleanUp() }
        #expect(h.controller.tomatoes.isEmpty)
    }
}
```

Append to `AppTests/DayOverviewModelTests.swift` (use the file's existing way of building a model from a played engine through `EngineSource`):

```swift
    @Test func theBedPutsAWorkedBlocksTomatoAtTheCentreOfItsBlock() throws {
        let source = try EngineSource(plan: makePlan([(.work, 30), (.shortBreak, 30), (.work, 30)]))
        try source.at(t(9)) { try $0.start() }
        try source.at(t(9, 30))
        let model = DayOverviewModel(source: source, calendar: utc)
        let plot = try #require(model.bed.first)
        let block = model.planned[0]
        #expect(model.bed.count == 1)                              // the second block has not started
        #expect(abs(plot.x - (block.x + block.width / 2)) < 1e-9)
        #expect(plot.tomato.segmentIndex == 0 && plot.tomato.availability == .pickable)
    }
```

In `AppTests/Support/EngineSource.swift` add `var overviewTomatoes: [Tomato] { engine.tomatoes() }` next to the other `overview…` properties.

- [ ] **Step 3: Run to see them fail**

Run: `scripts/test-app.sh`
Expected: compile errors for `GardenModel`, `CrateModel`, `controller.tomatoes`, `model.bed`, `onDayDeleted`.

- [ ] **Step 4: Implement**

`App/Garden/GardenModel.swift`:

```swift
import Foundation
import Observation
import os
import RipelineCore

/// Which tomatoes have been picked. Picking is the only write; it is remembered across launches in
/// the harvest store. Whether a tomato can be picked at all is decided by the core (`.pickable`).
@MainActor @Observable
final class GardenModel {
    @ObservationIgnored private let store: any HarvestStore
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ripeline", category: "garden")
    /// A store that could not be read is never written: its content would be replaced by a partial set.
    @ObservationIgnored private var canSave = true

    private(set) var picked: Set<UUID> = []
    /// The last attempt to save failed. The picks are kept in memory and written with the next save.
    private(set) var saveFailed = false

    init(store: any HarvestStore) {
        self.store = store
        do { picked = try store.load() } catch {
            canSave = false
            logger.error("Could not read the picked tomatoes; they will not be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    func isPicked(_ id: UUID) -> Bool { picked.contains(id) }

    /// Picks a tomato that is pickable and not yet picked. Returns whether anything was picked.
    @discardableResult
    func pick(_ tomato: Tomato) -> Bool {
        guard tomato.availability == .pickable, !picked.contains(tomato.id) else { return false }
        picked.insert(tomato.id)
        persist()
        return true
    }

    /// Removes ids, for example those of a deleted day. Saves only when something changed.
    func forget(_ ids: some Sequence<UUID>) {
        let before = picked
        picked.subtract(ids)
        if picked != before { persist() }
    }

    private func persist() {
        guard canSave else { return }
        do {
            try store.save(picked)
            saveFailed = false
        } catch {
            saveFailed = true
            logger.error("Could not save the picked tomatoes: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

`App/Garden/CrateModel.swift`:

```swift
import Foundation
import Observation
import RipelineCore

/// A picked tomato as the crate sees it.
struct CrateTomato: Equatable, Identifiable, Sendable {
    let id: UUID
    /// The store key of the day it grew in, the same as `HistoryEntry.id`.
    let dayID: String
    let growth: Double
    /// When its block was planned to start; the crate is filled in this order.
    let start: Date
}

/// What the crate holds: the picked tomatoes of the stored days, the newest `limit` of them, and how many there are in all.
/// A tomato counts only while its day exists. Its size is read at the last record of its day.
@MainActor @Observable
final class CrateModel {
    static let defaultLimit = 300

    @ObservationIgnored private let store: any DayStore
    @ObservationIgnored private let garden: GardenModel
    @ObservationIgnored private let limit: Int

    /// Oldest first.
    private(set) var tomatoes: [CrateTomato] = []
    private(set) var total = 0
    private(set) var loadFailed = false

    init(store: any DayStore, garden: GardenModel, limit: Int = CrateModel.defaultLimit) {
        self.store = store
        self.garden = garden
        self.limit = limit
    }

    /// Reads the stored days again. A failed read keeps what was there.
    func refresh() {
        let days: [StoredDay]
        do { days = try store.loadAll() } catch {
            loadFailed = true
            return
        }
        loadFailed = false
        var all: [CrateTomato] = []
        for day in days {
            let snapshot = day.snapshot
            let instant = SnapshotSource.lastRecordedInstant(of: snapshot) ?? snapshot.plan.first?.start ?? .distantPast
            for tomato in Tomatoes.of(snapshot, at: instant) where garden.isPicked(tomato.id) && tomato.workTime > 0 {
                all.append(CrateTomato(
                    id: tomato.id, dayID: day.key, growth: tomato.growth, start: snapshot.plan[tomato.segmentIndex].start
                ))
            }
        }
        all.sort { $0.start < $1.start }
        total = all.count
        tomatoes = Array(all.suffix(limit))
    }
}
```

`SessionController`: add after `comparison`:

```swift
    /// The tomatoes of the current day as of the current time.
    var tomatoes: [Tomato] {
        _ = now
        return engine.tomatoes()
    }
```
and in `extension SessionController: DayOverviewSource` add `var overviewTomatoes: [Tomato] { tomatoes }`.

`DayOverviewModel.swift`: in the protocol add `var overviewTomatoes: [Tomato] { get }`; in the extension `var overviewTomatoes: [Tomato] { [] }`; add

```swift
/// A tomato placed on the bed: the middle of its work block as a fraction of the axis, and the block's width.
struct BedPlot: Equatable, Sendable, Identifiable {
    let tomato: Tomato
    let x: Double
    let width: Double
    var id: UUID { tomato.id }
}
```
a property `private(set) var bed: [BedPlot] = []`, in `refresh()` after `planned = …`:

```swift
        bed = source.overviewTomatoes.compactMap { tomato in
            guard tomato.availability == .growing || tomato.availability == .pickable,
                  planned.indices.contains(tomato.segmentIndex) else { return nil }
            let block = planned[tomato.segmentIndex]
            return BedPlot(tomato: tomato, x: block.x + block.width / 2, width: block.width)
        }
```
and `bed = []` in `clear()`.

`SnapshotSource.swift`: add `var overviewTomatoes: [Tomato] { Tomatoes.of(snapshot, at: instant) }`.

`HistoryModel.swift`: add a stored `@ObservationIgnored private let onDayDeleted: @MainActor (SessionSnapshot) -> Void`, the init parameter `onDayDeleted: @escaping @MainActor (SessionSnapshot) -> Void = { _ in }`, and in `confirmDelete(_ entry:)` right after the `do/catch` that deletes (after the early `return` on failure): `onDayDeleted(entry.snapshot)`.

`AppEnvironment.swift`: add `let garden: GardenModel`, `let crateModel: CrateModel`; the private init takes `harvest: any HarvestStore`, builds `garden = GardenModel(store: harvest)`, `crateModel = CrateModel(store: store, garden: garden)` and passes `onDayDeleted: { [garden] snapshot in garden.forget(snapshot.plan.filter { $0.kind == .work }.map(\.id)) }` to `HistoryModel` (every work segment's id, including those whose tomato was empty). `makeInert` uses `InMemoryHarvestStore()`. `makeLive` uses `FileHarvestStore(file: try FileHarvestStore.defaultFile())` with the same fallback-and-log pattern as the day store (fall back to `InMemoryHarvestStore`).

- [ ] **Step 5: Run to see them pass**

Run: `scripts/test-app.sh`
Expected: `** TEST SUCCEEDED **`, no warnings. Also run `swift test --package-path Packages/RipelineCore | tail -3`.

- [ ] **Step 6: Commit**

```bash
git add App AppTests
git commit -m "Add the garden and the crate models"
```

---

### Task 4: How a tomato looks

**Files:**
- Create: `App/Garden/TomatoLook.swift`, `App/Garden/GardenText.swift`, `App/Garden/TomatoArt.swift`, `App/Garden/TomatoTextures.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Test: `AppTests/TomatoLookTests.swift`, `AppTests/GardenTextTests.swift`

**Interfaces:**
- Produces:
  - `TomatoStage { sprout, green, blushing, ripe }`, `TomatoFace { sleepy, smile, grin }`.
  - `TomatoLook(growth:)` with `stage`, `ripeness` (0…1), `scale`, `face`, `isBig`; `static func textureGrowth(_:) -> Double`.
  - `RGB`, `TomatoPalette` (colours; `body(ripeness:) -> RGB`).
  - `GardenText` (localized strings, explicit `bundle`).
  - `TomatoArt(growth:)` fills its frame. `TomatoTextures().texture(growth:) -> SKTexture`.

- [ ] **Step 1: Write the failing tests**

`AppTests/TomatoLookTests.swift`:

```swift
import Foundation
import Testing
@testable import Ripeline

struct TomatoLookTests {
    @Test(arguments: [
        (0.0, TomatoStage.sprout), (0.19, .sprout), (0.2, .green), (0.59, .green),
        (0.6, .blushing), (0.99, .blushing), (1.0, .ripe), (1.5, .ripe),
    ])
    func stagesFollowTheGrowth(growth: Double, stage: TomatoStage) {
        #expect(TomatoLook(growth: growth).stage == stage)
    }

    @Test(arguments: [(0.0, 0.35), (1.0, 1.0), (1.5, 1.25), (2.0, 1.5), (5.0, 1.5)])
    func theScaleGrowsAndIsCappedAtTwiceTheGrowth(growth: Double, scale: Double) {
        #expect(abs(TomatoLook(growth: growth).scale - scale) < 1e-9)
    }

    @Test func theScaleNeverShrinksAsTheTomatoGrows() {
        let scales = stride(from: 0.0, through: 3.0, by: 0.01).map { TomatoLook(growth: $0).scale }
        #expect(zip(scales, scales.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test(arguments: [(0.5, TomatoFace.sleepy), (0.99, .sleepy), (1.0, .smile), (1.19, .smile), (1.2, .grin), (2.0, .grin)])
    func theFaceFollowsTheGrowth(growth: Double, face: TomatoFace) {
        #expect(TomatoLook(growth: growth).face == face)
        #expect(TomatoLook(growth: growth).isBig == (face == .grin))
    }

    @Test func ripenessIsClampedToWhatCanBeSeen() {
        #expect(TomatoLook(growth: -1).ripeness == 0)
        #expect(TomatoLook(growth: 0.4).ripeness == 0.4)
        #expect(TomatoLook(growth: 3).ripeness == 1)
    }

    /// A texture is drawn once per look, so the snapped growth must look like the real one.
    @Test func theTextureGrowthLooksLikeTheRealGrowth() {
        for step in 0...220 {
            let growth = Double(step) * 0.01
            let snapped = TomatoLook.textureGrowth(growth)
            let real = TomatoLook(growth: growth), texture = TomatoLook(growth: snapped)
            #expect(real.stage == texture.stage && real.face == texture.face, "growth \(growth) snapped to \(snapped)")
            #expect(snapped <= growth + 1e-9)
        }
    }

    @Test func thePaletteRunsFromGreenThroughYellowToRed() {
        #expect(TomatoPalette.body(ripeness: 0) == TomatoPalette.green)
        #expect(TomatoPalette.body(ripeness: 0.5) == TomatoPalette.yellow)
        #expect(TomatoPalette.body(ripeness: 1) == TomatoPalette.red)
        #expect(TomatoPalette.body(ripeness: 7) == TomatoPalette.red)
        #expect(TomatoPalette.body(ripeness: -1) == TomatoPalette.green)
    }
}
```

`AppTests/GardenTextTests.swift`:

```swift
import Foundation
import RipelineCore
import Testing
@testable import Ripeline

struct GardenTextTests {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    @Test func percentRoundsToWholeNumbers() {
        #expect(GardenText.percent(0.404) == 40)
        #expect(GardenText.percent(1.256) == 126)
    }

    @Test func labelsAreInBothLanguages() throws {
        let en = try bundle("en"), uk = try bundle("uk")
        #expect(GardenText.basket(3, bundle: en) == "Picked: 3")
        #expect(GardenText.basket(3, bundle: uk) == "Зібрано: 3")
        #expect(GardenText.crateTotal(12, bundle: en) == "12 in the crate")
        #expect(GardenText.crateTotal(12, bundle: uk) == "У ящику: 12")
        #expect(GardenText.crateLabel(total: 12, bundle: en) == "Crate, tomatoes: 12")
    }

    @Test func aTomatoIsDescribedByItsGrowthAndWhetherItCanBePicked() throws {
        let en = try bundle("en")
        #expect(GardenText.tomatoLabel(growth: 0.4, availability: .growing, isPicked: false, bundle: en) == "Tomato, 40% grown")
        #expect(GardenText.tomatoLabel(growth: 1.1, availability: .pickable, isPicked: false, bundle: en) == "Tomato, 110% grown, ready to pick")
        #expect(GardenText.tomatoLabel(growth: 1.1, availability: .pickable, isPicked: true, bundle: en) == "Picked tomato, 110%")
        let uk = try bundle("uk")
        #expect(GardenText.tomatoLabel(growth: 0.4, availability: .growing, isPicked: false, bundle: uk) == "Помідор, виріс на 40%")
    }
}
```

- [ ] **Step 2: Run to see them fail** — `scripts/test-app.sh TomatoLookTests` → compile error.

- [ ] **Step 3: Implement the pure parts**

`App/Garden/TomatoLook.swift`:

```swift
import SwiftUI

/// How far a tomato has come, as far as the eye can tell.
enum TomatoStage: Equatable, Sendable { case sprout, green, blushing, ripe }

/// What a tomato's face says.
enum TomatoFace: Equatable, Sendable { case sleepy, smile, grin }

/// A colour as plain numbers, so the palette can be tested and mixed.
struct RGB: Equatable, Sendable {
    var r: Double, g: Double, b: Double

    func mixed(with other: RGB, _ amount: Double) -> RGB {
        let t = min(1, max(0, amount))
        return RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// The fixed cartoon palette. It is the same in light and dark appearance.
enum TomatoPalette {
    static let outline = RGB(r: 0.33, g: 0.16, b: 0.10)
    static let green = RGB(r: 0.52, g: 0.76, b: 0.28)
    static let yellow = RGB(r: 0.98, g: 0.80, b: 0.28)
    static let red = RGB(r: 0.92, g: 0.25, b: 0.20)
    static let leaf = RGB(r: 0.30, g: 0.62, b: 0.25)
    static let soil = RGB(r: 0.52, g: 0.34, b: 0.20)
    static let wood = RGB(r: 0.80, g: 0.58, b: 0.34)
    static let woodDark = RGB(r: 0.62, g: 0.42, b: 0.24)
    static let blush = RGB(r: 1.0, g: 0.55, b: 0.55)

    /// Green at 0, yellow at 0.5, red at 1.
    static func body(ripeness: Double) -> RGB {
        let t = min(1, max(0, ripeness))
        return t < 0.5 ? green.mixed(with: yellow, t * 2) : yellow.mixed(with: red, (t - 0.5) * 2)
    }
}

/// Everything that decides how a tomato looks, from its growth alone (1.0 is 100%).
struct TomatoLook: Equatable, Sendable {
    static let sproutBelow = 0.2
    static let greenBelow = 0.6
    static let ripeFrom = 1.0
    static let grinFrom = 1.2
    /// The display scale stops growing here; the figures stay honest.
    static let maxGrowth = 2.0

    let stage: TomatoStage
    /// 0 is green and 1 is red.
    let ripeness: Double
    /// How big it is drawn, as a fraction of the full size: 1 at 100%, at most 1.5.
    let scale: Double
    let face: TomatoFace

    init(growth: Double) {
        let g = max(0, growth)
        ripeness = min(g, 1)
        switch g {
        case ..<Self.sproutBelow: stage = .sprout
        case ..<Self.greenBelow: stage = .green
        case ..<Self.ripeFrom: stage = .blushing
        default: stage = .ripe
        }
        let overshoot = min(g, Self.maxGrowth) - 1
        scale = g <= 1 ? 0.35 + 0.65 * g : 1 + 0.5 * overshoot
        face = g < Self.ripeFrom ? .sleepy : (g < Self.grinFrom ? .smile : .grin)
    }

    /// Bigger than 100% by enough to grin and sparkle.
    var isBig: Bool { face == .grin }

    /// The growth snapped down to what a drawing can tell apart, so one drawing serves many tomatoes.
    static func textureGrowth(_ growth: Double) -> Double {
        let g = max(0, growth)
        if g < ripeFrom { return ((g * 10) + 1e-9).rounded(.down) / 10 }
        return g < grinFrom ? ripeFrom : grinFrom
    }
}
```

`App/Garden/GardenText.swift`:

```swift
import Foundation
import RipelineCore

/// Localized text for the garden: labels, counts and what VoiceOver reads. The bundle is explicit so tests can ask for either language.
enum GardenText {
    /// The growth as a whole percentage: 1.0 is 100.
    static func percent(_ growth: Double) -> Int { Int((growth * 100).rounded()) }

    /// `Picked: 3`.
    static func basket(_ count: Int, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "garden.basket", value: nil, table: nil), count)
    }

    /// `12 in the crate`.
    static func crateTotal(_ total: Int, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "crate.total", value: nil, table: nil), total)
    }

    /// What VoiceOver reads for the crate.
    static func crateLabel(total: Int, bundle: Bundle = .main) -> String {
        String(format: bundle.localizedString(forKey: "a11y.crate", value: nil, table: nil), total)
    }

    /// What VoiceOver reads for one tomato.
    static func tomatoLabel(growth: Double, availability: TomatoAvailability, isPicked: Bool, bundle: Bundle = .main) -> String {
        let key: String
        if isPicked {
            key = "a11y.tomatoPicked"
        } else {
            key = availability == .pickable ? "a11y.tomatoReady" : "a11y.tomatoGrowing"
        }
        return String(format: bundle.localizedString(forKey: key, value: nil, table: nil), percent(growth))
    }
}
```

Add to `Localizable.xcstrings` (all `"extractionState": "manual"`, `en` and `uk`, state `translated`):

| key | en | uk |
|---|---|---|
| `garden.basket` | `Picked: %lld` | `Зібрано: %lld` |
| `garden.pick` | `Pick` | `Зібрати` |
| `crate.total` | `%lld in the crate` | `У ящику: %lld` |
| `crate.empty` | `The crate is empty` | `Ящик порожній` |
| `crate.emptyHint` | `Pick a ripe tomato after a work block and it lands here.` | `Збери стиглий помідор після робочого блоку, і він упаде сюди.` |
| `a11y.crate` | `Crate, tomatoes: %lld` | `Ящик, помідорів: %lld` |
| `a11y.tomatoGrowing` | `Tomato, %lld%% grown` | `Помідор, виріс на %lld%%` |
| `a11y.tomatoReady` | `Tomato, %lld%% grown, ready to pick` | `Помідор, виріс на %lld%%, можна зібрати` |
| `a11y.tomatoPicked` | `Picked tomato, %lld%%` | `Зібраний помідор, %lld%%` |
| `a11y.pickTomato` | `Pick the tomato` | `Зібрати помідор` |

Edit the JSON with a small script that keeps Xcode's formatting (`json.dump(…, indent=2, ensure_ascii=False, separators=(',', ' : '))`, trailing newline). After the first build, run `git diff App/Resources/Localizable.xcstrings`: keep the added keys and discard unrelated extraction noise (`stale` marks, an empty `""` key) with `git checkout -p` or by hand.

- [ ] **Step 4: Run to see the pure tests pass** — `scripts/test-app.sh TomatoLookTests` and `scripts/test-app.sh GardenTextTests` → success; then `scripts/test-app.sh LocalizationCatalogTests` → success (en/uk keys equal, filled in, different).

- [ ] **Step 5: Draw the tomato** — `App/Garden/TomatoArt.swift`. The numbers are starting values; Step 6 tunes them by eye.

```swift
import SwiftUI

/// A cartoon tomato that fills its frame: a seedling while it is small, then green, yellow, red,
/// and bigger and grinning when it has grown past 100%.
struct TomatoArt: View {
    let growth: Double

    var body: some View {
        let look = TomatoLook(growth: growth)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if look.stage == .sprout {
                    SproutArt(side: side)
                } else {
                    FruitArt(look: look, side: side)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

private struct SproutArt: View {
    let side: CGFloat
    var body: some View {
        let line = side * 0.045
        ZStack {
            Ellipse().fill(TomatoPalette.soil.color).frame(width: side * 0.8, height: side * 0.34)
                .overlay(Ellipse().stroke(TomatoPalette.outline.color, lineWidth: line))
                .offset(y: side * 0.28)
            Capsule().fill(TomatoPalette.leaf.color).frame(width: side * 0.07, height: side * 0.34)
                .overlay(Capsule().stroke(TomatoPalette.outline.color, lineWidth: line * 0.7))
                .offset(y: side * 0.02)
            leaf(side, angle: -38).offset(x: -side * 0.17, y: -side * 0.17)
            leaf(side, angle: 38).offset(x: side * 0.17, y: -side * 0.17)
        }
    }

    private func leaf(_ side: CGFloat, angle: Double) -> some View {
        Ellipse().fill(TomatoPalette.green.color).frame(width: side * 0.3, height: side * 0.17)
            .overlay(Ellipse().stroke(TomatoPalette.outline.color, lineWidth: side * 0.035))
            .rotationEffect(.degrees(angle))
    }
}

private struct FruitArt: View {
    let look: TomatoLook
    let side: CGFloat

    var body: some View {
        let body = TomatoPalette.body(ripeness: look.ripeness)
        let line = side * 0.05
        ZStack {
            // The fruit: a soft, a little squashed ball with a darker underside.
            Ellipse()
                .fill(LinearGradient(colors: [body.color, body.mixed(with: TomatoPalette.outline, 0.22).color], startPoint: .top, endPoint: .bottom))
                .frame(width: side * 0.88, height: side * 0.78)
                .overlay(Ellipse().stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineJoin: .round)))
                .offset(y: side * 0.08)
            // The shine.
            Capsule().fill(Color.white.opacity(0.6)).frame(width: side * 0.17, height: side * 0.08)
                .rotationEffect(.degrees(-35)).offset(x: -side * 0.23, y: -side * 0.1)
            // The leaves and the stem.
            Capsule().fill(TomatoPalette.leaf.color).frame(width: side * 0.07, height: side * 0.13)
                .overlay(Capsule().stroke(TomatoPalette.outline.color, lineWidth: line * 0.7))
                .offset(y: -side * 0.36)
            StarShape(points: 5, innerRatio: 0.42).fill(TomatoPalette.leaf.color)
                .overlay(StarShape(points: 5, innerRatio: 0.42).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line * 0.7, lineJoin: .round)))
                .frame(width: side * 0.34, height: side * 0.34).offset(y: -side * 0.28)
            face
            if look.isBig { sparkles }
        }
    }

    private var face: some View {
        let line = side * 0.04
        return ZStack {
            Circle().fill(TomatoPalette.blush.color.opacity(0.45)).frame(width: side * 0.12).offset(x: -side * 0.25, y: side * 0.2)
            Circle().fill(TomatoPalette.blush.color.opacity(0.45)).frame(width: side * 0.12).offset(x: side * 0.25, y: side * 0.2)
            switch look.face {
            case .sleepy:
                ArcShape(smile: false).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: side * 0.12, height: side * 0.05).offset(x: -side * 0.14, y: side * 0.1)
                ArcShape(smile: false).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .frame(width: side * 0.12, height: side * 0.05).offset(x: side * 0.14, y: side * 0.1)
                Circle().fill(TomatoPalette.outline.color).frame(width: side * 0.05).offset(y: side * 0.24)
            case .smile, .grin:
                Circle().fill(TomatoPalette.outline.color).frame(width: side * 0.07).offset(x: -side * 0.14, y: side * 0.08)
                Circle().fill(TomatoPalette.outline.color).frame(width: side * 0.07).offset(x: side * 0.14, y: side * 0.08)
                if look.face == .grin {
                    ArcShape(smile: true, closed: true).fill(TomatoPalette.outline.color)
                        .frame(width: side * 0.26, height: side * 0.14).offset(y: side * 0.22)
                } else {
                    ArcShape(smile: true).stroke(TomatoPalette.outline.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                        .frame(width: side * 0.2, height: side * 0.08).offset(y: side * 0.2)
                }
            }
        }
    }

    private var sparkles: some View {
        ZStack {
            StarShape(points: 4, innerRatio: 0.3).fill(Color.yellow).frame(width: side * 0.16, height: side * 0.16)
                .offset(x: side * 0.4, y: -side * 0.28)
            StarShape(points: 4, innerRatio: 0.3).fill(Color.yellow).frame(width: side * 0.1, height: side * 0.1)
                .offset(x: -side * 0.42, y: -side * 0.36)
        }
    }
}

/// A star with `points` tips; `innerRatio` is how deep the notches go.
struct StarShape: Shape {
    let points: Int
    let innerRatio: Double

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2, inner = outer * innerRatio
        var path = Path()
        for step in 0..<(points * 2) {
            let radius = step.isMultiple(of: 2) ? outer : inner
            let angle = Double(step) * .pi / Double(points) - .pi / 2
            let point = CGPoint(x: centre.x + radius * cos(angle), y: centre.y + radius * sin(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// A smile (curving down) or the upper arc of a closed eye; `closed` makes the open mouth of a grin.
struct ArcShape: Shape {
    let smile: Bool
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if closed {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
            path.closeSubpath()
        } else if smile {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        }
        return path
    }
}
```

`App/Garden/TomatoTextures.swift`:

```swift
import SpriteKit
import SwiftUI

/// Drawings of tomatoes as textures for the crate, rendered once per look.
@MainActor
final class TomatoTextures {
    private var cache: [Double: SKTexture] = [:]

    func texture(growth: Double) -> SKTexture {
        let snapped = TomatoLook.textureGrowth(growth)
        if let hit = cache[snapped] { return hit }
        let renderer = ImageRenderer(content: TomatoArt(growth: snapped).frame(width: 96, height: 96))
        renderer.scale = 2
        let texture = renderer.cgImage.map { SKTexture(cgImage: $0) } ?? SKTexture()
        cache[snapped] = texture
        return texture
    }
}
```

- [ ] **Step 6: Look at it** (throwaway, not committed). Add a temporary test `AppTests/TomatoContactSheetTests.swift` that renders `HStack` of `TomatoArt(growth:)` at 0, 0.15, 0.4, 0.7, 0.95, 1.0, 1.3, 1.8, 2.5 (each 120 pt, on a light and a dark background) with `ImageRenderer`, writes the PNG to `FileManager.default.temporaryDirectory/tomato-sheet.png` and prints the path via `print`. Run it, open the PNG with the Read tool, and adjust sizes, colours and offsets until the sheet looks cheerful and readable: the face is legible at 36 pt, the outline is not heavy, the stages are distinct, the sprout reads as a sprout. Delete the temporary test before the commit.

Expected: a recognisable cartoon tomato at every stage. If the hosted test sandbox forbids writing there, write into `NSTemporaryDirectory()` of the host app and read it from the container path the test prints.

- [ ] **Step 7: Full app suite, then commit** — `scripts/test-app.sh` → success, zero warnings.

```bash
git add App AppTests
git commit -m "Draw the tomatoes"
```

---

### Task 5: Growing and picking in the popover and on the day screen

**Files:**
- Create: `App/Garden/TomatoButton.swift`, `App/Garden/GardenBedView.swift`
- Modify: `App/Views/PopoverView.swift`, `App/Views/TimelineRowsView.swift`, `App/RipelineApp.swift`
- No new unit tests: the logic is in tasks 1–4. The look goes on the PR checklist. Run the whole suite to catch regressions (`TimelineLookTests` renders `TimelineRowsView` headless).

**Interfaces:**
- Consumes: `GardenModel`, `Tomato`, `TomatoArt`, `TomatoLook`, `GardenText`, `DayOverviewModel.bed`, `BedPlot`, `SessionController.tomatoes`.
- Produces: `TomatoButton(tomato:diameter:)`, `TomatoPatchView(tomatoes:)`, `GardenBedView(plots:width:height:)`. Views read the garden from the environment as an optional (`@Environment(GardenModel.self) private var garden: GardenModel?`) so a view tree without it (headless tests) draws the tomatoes without picking.

- [ ] **Step 1: The tomato button** — `App/Garden/TomatoButton.swift`

```swift
import RipelineCore
import SwiftUI

/// One tomato. When it can be picked it wiggles and a click picks it; a picked one is shown faded.
struct TomatoButton: View {
    let tomato: Tomato
    /// The size of a tomato at 100%.
    let diameter: CGFloat
    @Environment(GardenModel.self) private var garden: GardenModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wiggle = false

    var body: some View {
        let isPicked = garden?.isPicked(tomato.id) ?? false
        let ready = tomato.availability == .pickable && !isPicked && garden != nil
        let size = diameter * TomatoLook(growth: tomato.growth).scale
        Button {
            if reduceMotion { garden?.pick(tomato) } else { withAnimation(.spring(duration: 0.35)) { _ = garden?.pick(tomato) } }
        } label: {
            TomatoArt(growth: tomato.growth)
                .frame(width: size, height: size)
                .rotationEffect(.degrees(ready && wiggle ? 6 : (ready ? -6 : 0)))
                .opacity(isPicked ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(ready)
        .animation(ready && !reduceMotion ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default, value: wiggle)
        .task(id: ready) { wiggle = ready }
        .help(ready ? Text("garden.pick") : Text(verbatim: ""))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GardenText.tomatoLabel(growth: tomato.growth, availability: tomato.availability, isPicked: isPicked))
        .accessibilityAddTraits(ready ? .isButton : [])
        .accessibilityAction(named: Text("a11y.pickTomato")) { if ready { garden?.pick(tomato) } }
    }
}

/// The popover's row of tomatoes: those still on the bed, the one that is growing among them, and a count of the picked ones.
struct TomatoPatchView: View {
    let tomatoes: [Tomato]
    @Environment(GardenModel.self) private var garden: GardenModel?

    var body: some View {
        let shown = tomatoes.filter { $0.availability == .growing || $0.availability == .pickable }
        let waiting = shown.filter { !(garden?.isPicked($0.id) ?? false) }
        let pickedCount = shown.count - waiting.count
        if !shown.isEmpty {
            HStack(alignment: .bottom, spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(waiting) { tomato in
                            TomatoButton(tomato: tomato, diameter: 34)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(minHeight: 40, alignment: .bottom)
                }
                Spacer(minLength: 0)
                if pickedCount > 0 {
                    Text(verbatim: GardenText.basket(pickedCount)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Put the patch in the popover** — `PopoverView.swift`: after `header` (and before the quick-start section) add

```swift
            TomatoPatchView(tomatoes: controller.tomatoes)
```
In `RipelineApp.swift` add `.environment(environment.garden)` to the `PopoverView` and to the `RipelineWindowView`, and pass `crateModel: environment.crateModel` to the window view later (Task 6).

- [ ] **Step 3: The bed** — `App/Garden/GardenBedView.swift`

```swift
import SwiftUI

/// The garden bed above the timelines: a strip of soil with a wooden edge, and a tomato standing on every worked block.
struct GardenBedView: View {
    let plots: [BedPlot]
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4).fill(TomatoPalette.soil.color).frame(height: 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(TomatoPalette.woodDark.color).frame(height: 4)
                    }
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(TomatoPalette.outline.color.opacity(0.7), lineWidth: 1))
            }
            ForEach(plots) { plot in
                let diameter = min(34, max(16, plot.width * width * 1.3))
                let size = diameter * TomatoLook(growth: plot.tomato.growth).scale
                TomatoButton(tomato: plot.tomato, diameter: diameter)
                    .position(x: plot.x * width, y: height - 8 - size / 2)
            }
        }
        .frame(width: width, height: height)
    }
}
```

- [ ] **Step 4: The bed in `TimelineRowsView`** — add `private let bedHeight: CGFloat = 52`; in the label column (`VStack(alignment: .trailing, spacing: rowGap)`) insert `Color.clear.frame(height: bedHeight)` before the "plan" label; replace the `GeometryReader { proxy in tracks(width: proxy.size.width) }` with

```swift
                GeometryReader { proxy in
                    VStack(alignment: .leading, spacing: rowGap) {
                        GardenBedView(plots: model.bed, width: proxy.size.width, height: bedHeight)
                        tracks(width: proxy.size.width)
                    }
                }
                .frame(height: bedHeight + rowGap + rowHeight * 2 + rowGap + 24)
```
(Keep `tracks` unchanged: the "now" line and the ticks are positioned inside it.)

- [ ] **Step 5: Run the suite** — `scripts/test-app.sh` → success, zero warnings. If `TimelineLookTests` breaks because the layout moved, update its expectations only for the changed heights and say so in the commit.

- [ ] **Step 6: Look at it** — build and run (`xcodebuild build -project Ripeline.xcodeproj -scheme Ripeline -destination 'platform=macOS' -derivedDataPath build`, then `open build/Build/Products/Debug/Ripeline.app`). Choose "Plan day…", a Custom preset with 1-minute work and break and "Net focus" of 15 minutes, and press "Start day". Watch the tomato grow in the popover and on the bed; click it when the block is over. Fix layout problems (a bed that overlaps the labels, a tomato wider than its block, a wiggle that never stops) before committing. GUI behaviour that cannot be clicked from the CLI goes on the PR checklist and is said so in the ledger.

- [ ] **Step 7: Commit**

```bash
git add App AppTests
git commit -m "Grow and pick tomatoes in the popover and on the day screen"
```

---

### Task 6: The crate

**Files:**
- Create: `App/Garden/CrateGeometry.swift`, `App/Garden/CrateScene.swift`, `App/Garden/CrateArt.swift`, `App/Garden/CrateView.swift`
- Modify: `App/Views/HistoryView.swift`, `App/Views/RipelineWindowView.swift`, `App/RipelineApp.swift`
- Test: `AppTests/CrateGeometryTests.swift`, `AppTests/CrateSceneTests.swift`

**Interfaces:**
- Consumes: `CrateModel`, `CrateTomato`, `GardenModel`, `TomatoTextures`, `TomatoLook`, `GardenText`, `HistoryModel.selection`.
- Produces: `CrateGeometry` (pure), `CrateScene.update(_:highlight:)`, `CrateView(model:highlight:)`.

- [ ] **Step 1: Write the failing tests**

`AppTests/CrateGeometryTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Ripeline

struct CrateGeometryTests {
    private let size = CGSize(width: 400, height: 260)

    @Test func theInteriorIsInsideTheCrate() {
        let interior = CrateGeometry.interior(in: size)
        #expect(interior.minX > 0 && interior.maxX < size.width)
        #expect(interior.minY > 0 && interior.maxY < size.height)
    }

    @Test func tomatoesShrinkAsTheCrateFillsAndStayInBounds() {
        let counts = [0, 1, 10, 60, 100, 200, 300, 500]
        let diameters = counts.map { CrateGeometry.baseDiameter(forCount: $0) }
        #expect(zip(diameters, diameters.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(diameters.allSatisfy { $0 >= 14 && $0 <= 30 })
        #expect(CrateGeometry.baseDiameter(forCount: 300) == 14)
        #expect(CrateGeometry.baseDiameter(forCount: 60) == 30)
    }

    /// Review focus 4: with 300 tomatoes the still pile (Reduce Motion) fits in the crate.
    @Test func threeHundredSettledTomatoesFitInTheInterior() {
        let interior = CrateGeometry.interior(in: size)
        let d = CrateGeometry.baseDiameter(forCount: 300)
        let points = (0..<300).map { CrateGeometry.settledPosition(index: $0, in: interior, diameter: d) }
        #expect(points.allSatisfy { $0.x - d / 2 >= interior.minX - 0.5 && $0.x + d / 2 <= interior.maxX + 0.5 })
        #expect(points.allSatisfy { $0.y - d / 2 >= interior.minY - 0.5 && $0.y + d / 2 <= interior.maxY + 0.5 })
        #expect(Set(points.map { "\($0.x),\($0.y)" }).count == 300)
    }

    @Test func aTomatoAlwaysDropsFromTheSameSpot() {
        let interior = CrateGeometry.interior(in: size)
        let id = UUID()
        let x = CrateGeometry.dropX(for: id, in: interior, diameter: 20)
        #expect(x == CrateGeometry.dropX(for: id, in: interior, diameter: 20))
        #expect(x >= interior.minX + 10 && x <= interior.maxX - 10)
    }
}
```

`AppTests/CrateSceneTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Ripeline

@MainActor
struct CrateSceneTests {
    private func tomatoes(_ count: Int) -> [CrateTomato] {
        (0..<count).map { CrateTomato(id: UUID(), dayID: "2026-01-1\($0 % 3)", growth: 1 + Double($0 % 5) * 0.2, start: d(15, 9).addingTimeInterval(Double($0) * 60)) }
    }

    /// Review focus 4: no tomatoes, one, and more than the crate keeps.
    @Test(arguments: [0, 1, 300, 400])
    func theSceneHoldsOneNodePerTomatoItIsGiven(count: Int) {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.update(tomatoes(count), highlight: nil)
        #expect(scene.tomatoNodeCount == count)
    }

    @Test func updatingAddsNewTomatoesAndRemovesGoneOnes() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        let all = tomatoes(5)
        scene.update(all, highlight: nil)
        scene.update(Array(all.dropFirst(2)) + tomatoes(1), highlight: nil)
        #expect(scene.tomatoNodeCount == 4)
    }

    @Test func oneDaysTomatoesCanBeHighlighted() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        let all = tomatoes(6)
        scene.update(all, highlight: "2026-01-10")
        #expect(scene.highlightedCount == all.filter { $0.dayID == "2026-01-10" }.count)
        scene.update(all, highlight: nil)
        #expect(scene.highlightedCount == 0)
    }

    @Test func withReduceMotionTheTomatoesHaveNoPhysics() {
        let scene = CrateScene(size: CGSize(width: 400, height: 260))
        scene.reduceMotion = true
        scene.update(tomatoes(5), highlight: nil)
        #expect(scene.dynamicBodyCount == 0)
    }
}
```

If SpriteKit cannot create a scene or render textures inside the hosted test run, replace the scene tests with the model-level coverage already in `CrateModelTests`, record that as a ruling in the ledger, and put the scene on the PR checklist. Do not delete the geometry tests.

- [ ] **Step 2: Run to see them fail** — `scripts/test-app.sh CrateGeometryTests` → compile error.

- [ ] **Step 3: Implement the geometry** — `App/Garden/CrateGeometry.swift`

```swift
import CoreGraphics
import Foundation

/// Where things are in the crate. Fractions of the view; the scene's origin is the bottom left, as in SpriteKit.
enum CrateGeometry {
    static let insetX = 0.07
    static let floorY = 0.10
    static let rimY = 0.80
    /// The front boards hide the lowest tomatoes, so the pile looks like it is inside.
    static let frontHeight = 0.22

    /// The inside of the crate, in scene coordinates.
    static func interior(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * insetX, y: size.height * floorY,
            width: size.width * (1 - 2 * insetX), height: size.height * (rimY - floorY)
        )
    }

    /// How wide a tomato at 100% is drawn: 30 pt up to 60 tomatoes, shrinking to 14 pt at 300 so the crate can hold them all.
    static func baseDiameter(forCount count: Int) -> CGFloat {
        let fill = min(1, max(0, Double(count - 60) / 240))
        return CGFloat(30 - 16 * fill)
    }

    /// Where the `index`th tomato lies in a still pile (Reduce Motion): rows from the floor up.
    static func settledPosition(index: Int, in interior: CGRect, diameter: CGFloat) -> CGPoint {
        let columns = max(1, Int(interior.width / diameter))
        let column = index % columns, row = index / columns
        let step = interior.width / CGFloat(columns)
        return CGPoint(
            x: interior.minX + (CGFloat(column) + 0.5) * step,
            y: interior.minY + diameter / 2 + CGFloat(row) * diameter * 0.86
        )
    }

    /// Where a tomato is let go, the same every time for the same tomato.
    static func dropX(for id: UUID, in interior: CGRect, diameter: CGFloat) -> CGFloat {
        let fraction = CGFloat(id.uuid.0) / 255
        return interior.minX + diameter / 2 + fraction * max(0, interior.width - diameter)
    }
}
```

- [ ] **Step 4: Implement the scene** — `App/Garden/CrateScene.swift`

```swift
import SpriteKit

/// The physics of the crate: tomatoes drop in, bounce and settle. The scene is transparent; the wooden crate is drawn around it.
@MainActor
final class CrateScene: SKScene {
    private let textures = TomatoTextures()
    private var nodes: [UUID: SKSpriteNode] = [:]
    private var current: [CrateTomato] = []
    private var highlighted: String?
    private let walls = SKNode()

    /// With Reduce Motion the tomatoes lie still where they would end up, with no bodies and no falling.
    var reduceMotion = false {
        didSet { if oldValue != reduceMotion { respawn() } }
    }

    var tomatoNodeCount: Int { nodes.count }
    var highlightedCount: Int { nodes.values.filter { $0.childNode(withName: "ring") != nil }.count }
    var dynamicBodyCount: Int { nodes.values.filter { $0.physicsBody?.isDynamic == true }.count }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        physicsWorld.gravity = CGVector(dx: 0, dy: -12)
        addChild(walls)
        rebuildWalls()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didChangeSize(_ oldSize: CGSize) {
        rebuildWalls()
        if size != oldSize { respawn() }
    }

    /// Shows `tomatoes` (oldest first) and rings the ones of the day `highlight`. New ones drop in;
    /// ones that are gone are removed. The first fill drops the tomatoes one after another.
    func update(_ tomatoes: [CrateTomato], highlight: String?) {
        current = tomatoes
        highlighted = highlight
        guard size.width > 1, size.height > 1 else { return }

        let initialFill = nodes.isEmpty
        let ids = Set(tomatoes.map(\.id))
        for (id, node) in nodes where !ids.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
        let diameter = CrateGeometry.baseDiameter(forCount: tomatoes.count)
        for tomato in tomatoes {
            if let node = nodes[tomato.id] { resize(node, growth: tomato.growth, diameter: diameter) }
        }
        let fresh = tomatoes.enumerated().filter { nodes[$0.element.id] == nil }
        let spacing = min(0.04, 2.5 / Double(max(fresh.count, 1)))
        for (order, entry) in fresh.enumerated() {
            spawn(entry.element, index: entry.offset, diameter: diameter, delay: initialFill ? Double(order) * spacing : 0)
        }
        refreshHighlight()
    }

    // MARK: Building

    private func respawn() {
        for node in nodes.values { node.removeFromParent() }
        nodes = [:]
        update(current, highlight: highlighted)
    }

    private func rebuildWalls() {
        let interior = CrateGeometry.interior(in: size)
        guard interior.width > 0 else {
            walls.physicsBody = nil
            return
        }
        let top = size.height * 3                                   // tall walls: tomatoes never fall out sideways
        let path = CGMutablePath()
        path.move(to: CGPoint(x: interior.minX, y: top))
        path.addLine(to: CGPoint(x: interior.minX, y: interior.minY))
        path.addLine(to: CGPoint(x: interior.maxX, y: interior.minY))
        path.addLine(to: CGPoint(x: interior.maxX, y: top))
        walls.physicsBody = SKPhysicsBody(edgeChainFrom: path)
    }

    private func spawn(_ tomato: CrateTomato, index: Int, diameter: CGFloat, delay: TimeInterval) {
        let interior = CrateGeometry.interior(in: size)
        let node = SKSpriteNode(texture: textures.texture(growth: tomato.growth))
        nodes[tomato.id] = node
        resize(node, growth: tomato.growth, diameter: diameter)
        if reduceMotion {
            node.position = CrateGeometry.settledPosition(index: index, in: interior, diameter: diameter)
            addChild(node)
            return
        }
        node.position = CGPoint(
            x: CrateGeometry.dropX(for: tomato.id, in: interior, diameter: diameter),
            y: size.height + diameter * 2
        )
        node.zRotation = CGFloat(tomato.id.uuid.1) / 255 * .pi
        let drop = SKAction.run { [weak self, weak node] in
            guard let self, let node, node.parent == nil, self.nodes.values.contains(node) else { return }
            self.addChild(node)
        }
        run(.sequence([.wait(forDuration: delay), drop]))
    }

    private func resize(_ node: SKSpriteNode, growth: Double, diameter: CGFloat) {
        let side = diameter * CGFloat(TomatoLook(growth: growth).scale)
        node.size = CGSize(width: side, height: side)
        guard !reduceMotion else {
            node.physicsBody = nil
            return
        }
        let body = SKPhysicsBody(circleOfRadius: side * 0.46)
        body.restitution = 0.35
        body.friction = 0.4
        body.angularDamping = 0.4
        node.physicsBody = body
    }

    private func refreshHighlight() {
        for tomato in current {
            guard let node = nodes[tomato.id] else { continue }
            let want = highlighted != nil && tomato.dayID == highlighted
            let ring = node.childNode(withName: "ring")
            if want, ring == nil {
                let shape = SKShapeNode(circleOfRadius: node.size.width * 0.55)
                shape.name = "ring"
                shape.strokeColor = .systemYellow
                shape.lineWidth = 2.5
                shape.fillColor = .clear
                shape.glowWidth = 2
                node.addChild(shape)
                node.zPosition = 1
            } else if !want, let ring {
                ring.removeFromParent()
                node.zPosition = 0
            }
        }
    }
}
```

- [ ] **Step 5: The crate drawing and the view**

`App/Garden/CrateArt.swift`: two small SwiftUI views using `CrateGeometry` fractions (SwiftUI's y axis points down, so the floor is at `1 - floorY`):

```swift
import SwiftUI

/// The back and the front of the wooden crate. The scene with the tomatoes sits between them.
enum CrateArt {
    /// The back wall and the inside.
    struct Back: View {
        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let x = w * (CrateGeometry.insetX - 0.03)
                let top = h * (1 - CrateGeometry.rimY - 0.02)
                let box = CGRect(x: x, y: top, width: w - 2 * x, height: h * 0.97 - top)
                RoundedRectangle(cornerRadius: 10).fill(TomatoPalette.woodDark.color)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(TomatoPalette.outline.color, lineWidth: 3))
                    .frame(width: box.width, height: box.height)
                    .position(x: box.midX, y: box.midY)
            }
        }
    }

    /// The front boards, rope handles and the plank that carries the total.
    struct Front: View {
        let total: Int
        var body: some View {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let boardHeight = h * CrateGeometry.frontHeight
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        ForEach(0..<2, id: \.self) { _ in
                            Rectangle().fill(TomatoPalette.wood.color).overlay(Rectangle().stroke(TomatoPalette.outline.color, lineWidth: 3))
                        }
                    }
                    .frame(width: w * (1 - 2 * (CrateGeometry.insetX - 0.04)), height: boardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(verbatim: GardenText.crateTotal(total))
                        .font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(Color(red: 0.33, green: 0.16, blue: 0.10))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.97, green: 0.89, blue: 0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(TomatoPalette.outline.color, lineWidth: 2))
                        .padding(.bottom, boardHeight * 0.25)
                }
                .frame(width: w, height: h, alignment: .bottom)
            }
            .allowsHitTesting(false)
        }
    }
}
```
Tune the proportions by eye (Step 7); the aim is a cartoon wooden crate with a darker inside, two light boards in front, and a small plank with the count.

`App/Garden/CrateView.swift`:

```swift
import SpriteKit
import SwiftUI

/// The crate: tomatoes fall into it with physics. Rings the tomatoes of `highlight`, the chosen day.
struct CrateView: View {
    let model: CrateModel
    let highlight: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene = CrateScene(size: CGSize(width: 1, height: 1))

    var body: some View {
        ZStack {
            CrateArt.Back()
            SpriteView(scene: scene, options: [.allowsTransparency])
            CrateArt.Front(total: model.total)
            if model.total == 0 {
                VStack(spacing: 4) {
                    Text("crate.empty").font(.headline)
                    Text("crate.emptyHint").font(.caption).multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            }
        }
        .frame(height: 260)
        .onAppear { push() }
        .onChange(of: model.tomatoes) { push() }
        .onChange(of: highlight) { push() }
        .onChange(of: reduceMotion) { push() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GardenText.crateLabel(total: model.total))
    }

    private func push() {
        scene.reduceMotion = reduceMotion
        scene.update(model.tomatoes, highlight: highlight)
    }
}
```

- [ ] **Step 6: Put it in the History tab** — `HistoryView` gets `let crate: CrateModel` and `@Environment(GardenModel.self) private var garden: GardenModel?`. The right pane becomes `VStack(spacing: 0) { CrateView(model: crate, highlight: model.selection); Divider(); detail }`. `.onAppear { model.refresh(); crate.refresh() }`, and `.onChange(of: garden?.picked) { crate.refresh() }`, and after a delete (`.onChange(of: model.entries)`) call `crate.refresh()` so a deleted day's tomatoes leave the crate. `RipelineWindowView` takes `crateModel` and passes it on; `RipelineApp` passes `environment.crateModel`. Update the call sites that construct these views in tests, if any.

- [ ] **Step 7: Run and look** — `scripts/test-app.sh` → success, zero warnings. Then run the app with a few days recorded (use a throwaway Custom 1-minute preset and pick tomatoes) and check: tomatoes drop and settle inside the crate, the pile does not poke through the front boards, a day's tomatoes light up when it is selected, deleting a day removes them, and with Reduce Motion on (System Settings → Accessibility → Display) the pile is static. Tune `CrateGeometry` fractions, gravity and restitution by eye. If a smoothness problem shows with ~300 tomatoes, lower the physics cost first (sleeping bodies, fewer solver iterations) before cutting the cap.

- [ ] **Step 8: Commit**

```bash
git add App AppTests
git commit -m "Drop the picked tomatoes into a crate in the history"
```

---

### Task 7: Document the garden

**Files:**
- Modify: `SPEC.md`, `README.md`, `docs/specs/2026-10-01-tomato-garden-design.md`

- [ ] **Step 1: SPEC.md** — read it first. Add a "Tomato garden" section after the quick-session behaviour: a work block is a tomato; growth = recorded work ÷ planned length; pause and breaks do not grow it; extension and overtime grow it past 100%; pickable when the block is over or waits in overtime and has recorded work; unpicked tomatoes wait; picking is stored in `harvest.json`, day files untouched; the crate shows the newest 300 picked tomatoes and a total; deleting a day forgets its tomatoes; Reduce Motion shows a still pile. Add rows to the stage table and decisions log (D-T1…): derived not stored; separate harvest file; forget on delete, no prune on load; crate size read at the last record; fixed palette; no plural variations. Match the file's existing style and numbering.

- [ ] **Step 2: README.md** — in the status paragraph add one sentence: every work block is a tomato that grows while you work and can be picked into a crate in the History tab. In "To try it quickly" add: after a block ends, click its tomato to pick it, then open History to see the crate.

- [ ] **Step 3: The spec** — set `Status: implemented` in the tomato garden spec and append a section "9. Decisions made during planning and implementation" with the five amendments from this plan plus anything you ruled during execution.

- [ ] **Step 4: Verify and commit**

Run: `swift test --package-path Packages/RipelineCore | tail -3` and `scripts/test-app.sh` → both green, zero warnings.

```bash
git add SPEC.md README.md docs
git commit -m "Document the tomato garden"
```

## Manual checklist for the PR

- A running block's tomato grows in the popover and on the day-screen bed; a paused block's does not.
- "+5 min" and overtime make it bigger than 100% and it grins.
- When the block is over the tomato wiggles; a click picks it; it cannot be picked while the block still runs.
- A picked tomato shows in the Picked count; after a relaunch it is still picked.
- History: the crate shows the picked tomatoes dropping in; selecting a day rings its tomatoes; deleting the day removes them and the total drops.
- Reduce Motion: no falling, no wiggle. Dark appearance: the tomatoes and the crate still look right.
- VoiceOver reads each tomato and the crate; picking works from the actions menu.
- The popover still fits three buttons per row in Ukrainian with the tomato row above them.
- Many tomatoes (create a few dozen with a throwaway 1-minute preset): the crate stays smooth.
