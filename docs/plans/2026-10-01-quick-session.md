# Quick Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start work in one tap without planning a day: pick a block length (25, 50 or 90 minutes), press Start, and the block runs; add five minutes or another block (a short break plus a block) as the task grows; finish with "Done". One session in the history, without lag or plan-only figures.

**Architecture:** A quick session is a day whose plan grows. The core gets a `SessionKind` flag on the snapshot and a way to append segments to a `quick` session while it runs. The app builds the plan and the added blocks with a pure `QuickSession`, and `SessionController` starts and extends it; notifications, ticking, saving and restoring need no change because they already follow the engine's state. The overview, history and popover learn to treat a quick session specially.

**Tech Stack:** Swift 6 (strict concurrency), `RipelineCore` (small backward-compatible change), SwiftUI, Observation, Swift Testing, `swift test`, `xcodebuild`.

**Spec:** [`docs/specs/2026-10-01-quick-session-design.md`](../specs/2026-10-01-quick-session-design.md). Parents: [`SPEC.md`](../../SPEC.md), stages 1 and 2a–2d.

## Global Constraints

- Swift 6 language mode, strict concurrency, zero warnings from our code (core and app).
- `MACOSX_DEPLOYMENT_TARGET = 26.0`; only APIs available on macOS 26.
- Public APIs only; App Sandbox; **entitlements stay exactly `com.apple.security.app-sandbox`**; no network; no data collected.
- `RipelineCore` imports `Foundation` only; no user-facing text in the core; time always derived from `Date`s; the plan of an ordinary day stays fixed.
- No personal data in the repo; a fresh clone must build and test without `Config/Local.xcconfig`.
- All code, comments and docs in English. Every user-facing string from `Localizable.xcstrings` with `en` (base) and `uk`; the catalog completeness test stays green; keys looked up by name are added with `"extractionState": "manual"` so Xcode does not mark them stale. No counts are shown (no plural variations).
- Commit identity is configured; **no Claude attribution** in commits or PR text.
- Tests: Swift Testing. No real sleeping, no real `Application Support`, no real notification center in unit tests. A test that can hang must be guarded so that failure is a failure, not a hang. Wrap test runs in `timeout 115`.
- A throwaway check that reads the developer's real day files must be **read-only** and never committed.
- Commands: `swift test --package-path Packages/RipelineCore` (core), `scripts/test-app.sh [SuiteName]` (app).

## Decisions where the spec is silent or this plan refines it (please confirm)

| # | Decision | Why |
|---|----------|-----|
| S1 | For a quick session the segment-end notification is "block finished" for work and "break over" for a break, even for the **last** segment; "day finished" is never used. | The last segment of a growing plan is only the last so far; "Day finished" at the end of the first block would be wrong. |
| S2 | `SessionSnapshot` gets a hand-written `Codable` that reads `kind` with `decodeIfPresent` (default `day`); it still writes every field. | Backward compatibility with every file written before. |
| S3 | `appendSegments` first catches the engine up to the current time; if that finishes the session it is refused (`notAllowed(.append)`), never silently lost. | A block added in the instant the last one ended with auto-advance must not vanish. |
| S4 | The planned figures (focus and rest planned) stay for a quick session; only lag, planned end and projected end are hidden. | Spec §5; the planned figures are the blocks chosen so far. |
| S5 | The history row shows "Quick" in place of the lag figure, and the spoken label ends with "quick session" in place of the lag. | Spec §5. |
| S6 | The popover lays its buttons out in rows of three. | A quick session has up to five buttons; one row of five does not fit in 300 pt. |
| S7 | The "Quick start" section is shown whenever starting is allowed (no day, or the last one finished). | It is the same condition as "Plan day…". |
| S8 | The chosen length is stored in `AppSettings.quickBlockLength` (minutes). | Spec Q4. |
| S9 | A quick session never counts as stale while its plan is still ahead; the stale rule (a finished day, or a plan that ended before today) is unchanged. | Spec: it behaves like a day for restoring. |
| S10 | The break added with a block is chosen from the first block's length (25→5, 50→10, 90→15); an unexpected first length falls back to 5 minutes. | Spec Q5 and Q6, with a safe default. |

## Review Focus

1. **Old files still load.** A snapshot written before this change (no `kind`) decodes as a day, in the core and from the developer's real day files (read-only check); a quick session round-trips. *Tests in Tasks 1 and 7.*
2. **Appending at awkward moments.** During a pause, in overtime, in a break, on the last segment, in the instant the last segment ends (with and without auto-advance), many times in a row, and with the planned end far from "now": always contiguous, never lost, never allowed for a day, an idle or a finished session. *Tests in Tasks 2 and 4.*
3. **Notifications.** Every added segment gets its notification when it starts; the first block never says "Day finished"; appending while paused or in overtime leaves no stale or duplicate request. *Tests in Task 4.*
4. **No plan-only figures leak.** A quick session shows no lag chip, planned end or projected end on the day screen, in the menu bar or in the history, while a day still shows them. *Tests in Task 5.*
5. **Restoring.** A quick session with several blocks survives a relaunch; one left unfinished from yesterday is listed as not finished and not restored as running. *Tests in Tasks 4 and 7.*

---

## File Structure

```
Packages/RipelineCore/Sources/RipelineCore/
  Session/SessionKind.swift                new: SessionKind
  Session/SessionSnapshot.swift            (modified) kind, Codable, isAllowed(.append)
  Session/SessionSnapshot+Transitions.swift(modified) startDay kind, appendSegments
  Session/SessionState.swift               (modified) SessionAction.append
  Session/SessionEngine.swift              (modified) startDay(kind:), appendSegments
Packages/RipelineCore/Tests/RipelineCoreTests/
  SessionKindTests.swift, AppendSegmentsTests.swift   new; existing exhaustive switches updated
App/
  Quick/QuickSession.swift                 QuickBlockLength, QuickSession
  Settings/AppSettings.swift               (modified) quickBlockLength
  Runtime/SessionController.swift          (modified) startQuickSession, addBlock, isQuickSession, notification kinds
  Overview/DayOverviewModel.swift          (modified) overviewIsQuick, isQuick, hidden figures
  History/HistoryEntry.swift, HistoryText.swift, SnapshotSource.swift   (modified)
  Presentation/PopoverActions.swift        (modified) addBlock, done, isQuick
  Views/PopoverView.swift                  (modified) quick start section, rows of three
  Views/QuickStartSection.swift            new
  Views/DaySummaryView.swift, DayScreenView.swift, HistoryRowView.swift  (modified)
  Resources/Localizable.xcstrings          (modified)
AppTests/
  QuickSessionTests.swift, SessionControllerQuickTests.swift, QuickOverviewTests.swift, QuickRelaunchTests.swift
```

Fixtures as before. Core tests use the core's `makePlan` (UTC, 2026-01-15) and `ManualClock`; app tests the app fixtures.

---

### Task 1: SessionKind and backward-compatible snapshots

**Files:**
- Create: `Packages/RipelineCore/Sources/RipelineCore/Session/SessionKind.swift`, `Packages/RipelineCore/Tests/RipelineCoreTests/SessionKindTests.swift`
- Modify: `Session/SessionSnapshot.swift`, `Session/SessionSnapshot+Transitions.swift`, `Session/SessionEngine.swift`

**Interfaces — Produces:**
```swift
public enum SessionKind: String, Codable, Sendable, Equatable { case day, quick }

// SessionSnapshot
public internal(set) var kind: SessionKind              // .empty has .day
// Codable: encodes every field; `kind` is decoded with decodeIfPresent, default .day

// SessionEngine
public mutating func startDay(plan: [PlannedSegment], settings: SessionSettings, kind: SessionKind = .day) throws(SessionError)
```
`SessionSnapshot.startDay(plan:settings:kind:)` carries the kind into the new snapshot.

- [ ] **Step 1: Failing tests** (`SessionKindTests`):
  - a snapshot started with `startDay(plan:settings:)` has kind `.day`; with `kind: .quick` it has `.quick`; the kind survives `start`, `pause`, `endDay`.
  - `.empty.kind == .day`.
  - **Review Focus 1:** encode a started day with `JSONEncoder`, delete the `"kind"` key from the JSON object (`JSONSerialization`), decode: the result equals the original and its kind is `.day`; do the same for a snapshot in each state (idle, running, paused, overtime, finished).
  - a quick snapshot encodes `"kind": "quick"` and round-trips equal; `SessionEngine(restoring:)` accepts it.
  - a literal JSON string of a snapshot as written by the previous version (captured from the encoder at the start of this task, kept as a fixture in the test) decodes as a day.
- [ ] **Step 2:** `swift test --package-path Packages/RipelineCore --filter SessionKindTests` → fails to compile. **Step 3:** Implement (hand-written `init(from:)`/`encode(to:)` with `CodingKeys`). **Step 4:** Run the whole core suite → PASS, zero warnings. **Step 5:** Commit `Add the session kind`.

### Task 2: Appending segments to a quick session

**Files:**
- Create: `Packages/RipelineCore/Tests/RipelineCoreTests/AppendSegmentsTests.swift`
- Modify: `Session/SessionState.swift`, `Session/SessionSnapshot.swift`, `Session/SessionSnapshot+Transitions.swift`, `Session/SessionEngine.swift`, existing core tests with exhaustive switches over `SessionAction` (`SessionTransitionTests.swift`)

**Interfaces — Produces:**
```swift
public enum SessionAction { /* existing */ case append }

// SessionSnapshot.isAllowed(.append): kind == .quick and state is running, paused or overtime
// SessionEngine
/// Adds segments to the end of a quick session's plan. They must continue the indices, start exactly
/// where the plan ends and have a positive length, else `SessionError.invalidPlan`.
public mutating func appendSegments(_ segments: [PlannedSegment]) throws(SessionError)
```
Rules: catch up first (S3); not allowed → `.notAllowed(.append)`; an empty list → `.emptyPlan`; the combined plan must pass `isWellFormed` (indices by position, positive length, contiguous) → else `.invalidPlan`, and nothing changes; on success the plan and `actuals` grow (new records `.notStarted`), the state and open interval are untouched.

- [ ] **Step 1: Failing tests** (`AppendSegmentsTests`; a quick session of one work block 09:00–09:25, then more):

| Test | Behavior |
|------|----------|
| allowed table | quick: idle ✗, running ✓, paused ✓, overtime ✓, finished ✗; day kind: ✗ in every state (`isAllowed(.append)` and the call throws `notAllowed(.append)`) |
| appends a break and a block | after `appendSegments([break 09:25–09:30, work 09:30–09:55])` the plan has 3 segments, `actuals` has 3, the new ones `.notStarted`, the running segment's state and `endsAt` unchanged |
| during a pause | pause at 09:10, append, resume → the original block continues with its remaining time |
| in overtime | block expired at 09:25, clock 09:28, append, `advance` → the added break starts at 09:28 and runs to 09:33 |
| in a break | quick session already on its break, append another block → both queued in order |
| many times (Review Focus 2) | 20 successive appends: indices 0…, contiguous, plan length 41, `isWellFormed` holds, restoring accepts it |
| gap, overlap, wrong index, zero length, negative length, empty list | each throws the right error and **leaves the snapshot byte-for-byte unchanged** (compare encoded JSON before and after) |
| the instant the last segment ends (S3) | single block 09:00–09:25 with auto-advance on; clock 09:25 exactly, then `appendSegments` → catch-up finishes the session first, the call throws `notAllowed(.append)`, the finished session is intact (status `completed`) |
| the same without auto-advance | clock 09:25, no auto-advance: state becomes overtime, append succeeds |
| planned end far from now | clock two hours past the planned end of the last segment (overtime): the appended segments still start at the **plan's** end (the past), and `advance` starts the next one now |
| lag and projection | `ScheduleStatus` after appending: planned end is the new last end, projected end counts the appended segments; `DayComparison` has a row for each |
| catch-up over appended segments | all-auto settings, append two segments, tick far later → walks through every one and finishes; intervals have their real times |
| persistence | a quick session with appended segments encodes, decodes equal, restores, and keeps accepting appends |
| existing suite | every existing core test still passes; exhaustive switches over `SessionAction` handle `.append` |

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run the core suite → PASS. **Step 5:** Commit `Let a quick session grow`.

### Task 3: QuickSession logic and settings

**Files:**
- Create: `App/Quick/QuickSession.swift`, `AppTests/QuickSessionTests.swift`
- Modify: `App/Settings/AppSettings.swift`, `AppTests/AppSettingsTests.swift`

**Interfaces — Produces:**
```swift
enum QuickBlockLength: Int, CaseIterable, Codable, Sendable {
    case short = 25, medium = 50, long = 90
    var minutes: Int { get }
    var breakMinutes: Int { get }          // 5, 10, 15
}

enum QuickSession {
    /// One work block of `length` starting at `start`.
    static func plan(length: QuickBlockLength, start: Date) -> [PlannedSegment]
    /// A short break and then a work block, starting where `plan` ends, indexed after it; the block has
    /// the length of the plan's first segment and the break comes from the table (S10). `[]` for an empty plan.
    static func nextBlocks(after plan: [PlannedSegment]) -> [PlannedSegment]
}

// AppSettings
var quickBlockLength: QuickBlockLength      // default .short, stored as minutes
```

- [ ] **Step 1: Failing tests:** `plan` for each length (one `.work` segment, index 0, start/end exact, duration 25/50/90 min); `nextBlocks` after a one-block plan: `[shortBreak(5), work(25)]` for 25, 10/50 for 50, 15/90 for 90, starting at the plan's end, indices continue; after a three-segment plan indices continue at 3; after a plan that ran far past `now` it still starts at the plan's end; an unexpected first length (say 30 minutes) gives a 5-minute break and a 30-minute block; empty plan gives `[]`; fresh UUIDs; the combined result passes the core's well-formed rules when appended (use the engine). `AppSettings`: default `.short`; a changed length persists across a new instance; an unknown stored number (say 33) reads as `.short`.
- [ ] **Step 2:** Run `timeout 115 scripts/test-app.sh QuickSessionTests` → fails to compile. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Add the quick session plan`.

### Task 4: Controller: start, add blocks, finish

**Files:**
- Create: `AppTests/SessionControllerQuickTests.swift`
- Modify: `App/Runtime/SessionController.swift`

**Interfaces — Consumes:** Tasks 1–3. **Produces:**
```swift
extension SessionController {
    var isQuickSession: Bool { get }                       // the running or last session's kind is quick
    /// Starts a quick session: one block of `length` from now. Remembers the length. Same refusal rule as `startDay`.
    @discardableResult func startQuickSession(length: QuickBlockLength) async -> Bool
    /// Adds a short break and a block to the running quick session.
    func addBlock()
}
```
`startQuickSession` generates the plan, starts the engine with kind `.quick`, saves once, remembers `settings.quickBlockLength`, and requests notification permission as `startDay` does (without waiting, S: same as 2b fix). `addBlock()` goes through the existing `act(.append)` path so it is refused when not allowed. **S1:** `signalKind(endOfSegment:)` for a quick session returns `.workEnded` / `.breakEnded` by the segment kind, never `.dayFinished`.

- [ ] **Step 1: Failing tests** (`Harness`):

| Test | Behavior |
|------|----------|
| start | `startQuickSession(.short)` → `phase == .working`, plan is one 25-minute work segment from the clock, `isQuickSession`, saved once with kind `.quick`, the chosen length remembered, one authorization, returns `true` |
| each length | 50 and 90 give blocks of those lengths |
| refused while a day runs | a running ordinary day or quick session → returns `false`, no extra save or authorization |
| after a day ended | allowed again |
| notification (S1, Review Focus 3) | the first block schedules `.workEnded` (not `.dayFinished`); after `addBlock` and `advance` into the break the schedule is `.breakEnded`, then `.workEnded` for the next block |
| add a block | `addBlock()` → plan has 3 segments (break, block), saved, running block unchanged, no notifier call (the running segment's request is unchanged) |
| during a pause | `addBlock()` while paused: allowed, nothing scheduled, resume keeps the request for the original end |
| in overtime | block over (clock 25:30), `addBlock()`, `advance()` → on break, then work |
| refused for a day | `addBlock()` on an ordinary day or with nothing running does nothing |
| many blocks | five `addBlock()` calls → 11 segments, kind quick |
| extend, skip, done | `extend(minutes: 5)` adds five minutes; skip goes to the next segment; `endDay()` finishes and allows the next quick start |
| relaunch (Review Focus 5) | a quick session with three blocks restored by a new controller: same plan and kind, correct phase, notification scheduled for the running segment; one left unfinished from yesterday (plan ended before today) starts fresh and the file is kept |
| ordinary days unchanged | `startDay(request:)` still gives kind `.day` and a `.dayFinished` signal on its last segment |

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Start and extend a quick session`.

### Task 5: Overview and history for a quick session

**Files:**
- Create: `AppTests/QuickOverviewTests.swift`
- Modify: `App/Overview/DayOverviewModel.swift`, `App/History/SnapshotSource.swift`, `App/History/HistoryEntry.swift`, `App/History/HistoryText.swift`, `App/Resources/Localizable.xcstrings`, `App/Views/DaySummaryView.swift`, `App/Views/DayScreenView.swift`, `App/Views/HistoryRowView.swift`, `AppTests/Support/EngineSource.swift`

**Interfaces — Produces:**
```swift
// DayOverviewSource
var overviewIsQuick: Bool { get }      // default false (extension); the controller and SnapshotSource return the kind

// DayOverviewModel
private(set) var isQuick: Bool
// For a quick session: lag == nil; summary.plannedEnd == nil; the projected end is nil while running
// (the final end of a finished session is kept).

// HistoryEntry
let isQuick: Bool                      // lag is nil for a quick session
// HistoryText
static func accessibilityLabel(...)    // ends with ", quick session" for a quick session instead of the lag
```
Catalog keys (en / uk): `history.quick` "Quick" / "Швидка"; `a11y.historyQuick` "quick session" / "швидка сесія"; `ui.done` "Done" / "Готово". The views: `DaySummaryView` hides the planned-end row and the projected-end row for a quick session (the finished-at row stays); `DayScreenView` labels its end button `ui.done` for a quick session; `HistoryRowView` shows `history.quick` where the lag figure would be.

- [ ] **Step 1: Failing tests (Review Focus 4):** with an `EngineSource` over a quick engine: the model's `isQuick` is true, `lag == nil` even when the session is behind, `summary.plannedEnd == nil`, `summary.endsAt == nil` while running, and after `endDay` the final end is still shown with kind `.final`; the planned focus/rest figures are still present (S4); the same engine as a day keeps lag, planned end and projected end (no regression); `SnapshotSource` of a stored quick snapshot gives `isQuick`; `HistoryEntry` of a quick day has `isQuick` and no lag; `HistoryText.accessibilityLabel` ends with ", quick session" in `en` and `uk` and has no "against plan"; the day entry's label is unchanged; catalog completeness.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement the model, entries, texts, the three views and the catalog keys. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Show a quick session without plan-only figures`.

### Task 6: Popover: quick start, add block, done

**Files:**
- Create: `App/Views/QuickStartSection.swift`
- Modify: `App/Presentation/PopoverActions.swift`, `App/Views/PopoverView.swift`, `App/Resources/Localizable.xcstrings`, `AppTests/PopoverActionsTests.swift`

**Interfaces — Produces:**
```swift
enum PopoverAction { /* existing */ case addBlock, done }
// addBlock: sessionAction .append, titleKey "ui.addBlock"; done: sessionAction .endDay, titleKey "ui.done"

PopoverActions.visible(phase: Phase, isQuick: Bool = false, isAllowed: (SessionAction) -> Bool) -> [PopoverAction]
// ordinary day: unchanged. quick session: working/on break → [.pause, .extend, .addBlock, .skip, .done, .overview, .history];
// paused → [.resume, .extend, .addBlock, .skip, .done, .overview, .history]; overtime → [.next, .extend, .addBlock, .done, .overview, .history];
// idle → [.planDay, .history]; finished → [.summary, .history]. Each filtered by its session action, as before.
```
`QuickStartSection(controller:settings:)`: a title ("Quick start"), a `Picker` of the three lengths (labelled with `SetupText.duration`), and a prominent "Start" button that calls `controller.startQuickSession(length: settings.quickBlockLength)`; shown by `PopoverView` above the buttons when `controller.isAllowed(.startDay)`. The glass buttons are laid out in rows of three (S6); `.overview` and `.history` stay as links. Catalog keys (en / uk): `ui.quickStartTitle` "Quick start" / "Швидкий старт"; `ui.quickStartButton` "Start" / "Старт"; `ui.addBlock` "Another block" / "Ще один блок"; `ui.quickLength` "Block length" / "Довжина блоку".

- [ ] **Step 1: Failing tests:** `PopoverActionsTests` — the quick lists above for each phase with everything allowed; with `isQuick: false` every previous expectation is unchanged; `.addBlock` and `.done` are filtered by `.append` / `.endDay`; their `sessionAction` and `titleKey`; "Another block" never appears for an ordinary day or an idle state. Catalog completeness.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). Build and launch the app; confirm it stays alive.
- [ ] **Step 5:** Commit `Add the quick start to the popover`.

### Task 7: End to end, documentation and verification

**Files:**
- Create: `AppTests/QuickRelaunchTests.swift`
- Modify: `README.md`, `docs/specs/2026-10-01-quick-session-design.md` (status, decisions S1–S10), `SPEC.md` (a pointer)

- [ ] **Step 1: End-to-end test** over a real `FileDayStore` in a temporary directory: a quick session with two added blocks, a pause and a skipped break; a new controller restores it with the same plan, kind and phase; the overview (planned and actual rows, summary) is identical before and after the relaunch and has no lag; the history lists it with `isQuick`; deleting it from the history leaves other days untouched.
- [ ] **Step 2:** Update the docs.
- [ ] **Step 3:** Run everything and read the output: `swift test --package-path Packages/RipelineCore`, `scripts/test-app.sh`, a clean-clone `scripts/test-app.sh` (no `Local.xcconfig`), a warning-free `xcodebuild clean build`.
- [ ] **Step 4 (real days, read-only, Review Focus 1):** a throwaway hosted test (not committed) calls `FileDayStore(directory: defaultDirectory()).loadAll()` against the developer's real container with the new core, prints the keys and kinds, and asserts nothing but that it does not throw; confirm the real files load as days and that file checksums are identical before and after. Delete the test.
- [ ] **Step 5:** Launch the app and record what could and could not be checked from the command line.
- [ ] **Step 6:** Write the **manual checklist** for the PR: the popover with no day shows "Quick start" with a length menu and Start; one press starts a block at once; "+5 min", "Another block" and "Done" work, also during a pause and in overtime; the added break and block follow in order and notify; the menu bar and popover show the timer; the day screen shows no lag or planned end and "Done" ends it; the History tab lists it with "Quick"; a relaunch mid-session continues it; five buttons fit in the popover; English and Ukrainian.
- [ ] **Step 7:** Commit `Document the quick session`.

---

## Spec coverage check

| Spec section | Task |
|---|---|
| §1 criterion 1 (selector and immediate start) | 3, 4, 6 |
| §1 criterion 2 (pause, +5, skip, another block, Done) | 2, 4, 6 |
| §1 criterion 3 (another block adds a break and a block, repeatable, in pause and overtime) | 2, 3, 4 |
| §1 criterion 4 (behaves like a day otherwise) | 4, 7 |
| §1 criterion 5 (hides plan-only figures, marked "Quick") | 5 |
| §1 criterion 6 (old files load; days keep fixed plans) | 1, 2, 7 |
| §1 criterion 7 (strings, entitlements) | 5, 6 |
| §3 core | 1, 2 |
| §4 app logic | 3, 4 |
| §5 interface | 5, 6 |
| §6 testing and verification | every task; 7 |
