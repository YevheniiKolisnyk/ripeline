# Stage 2d — History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "History" tab in the app's one window that lists the recorded days except the running one, shows a chosen day with the day screen's timelines, summary and table (read only), and lets the user delete a day after a confirmation.

**Architecture:** `DayStore` gains `loadAll()` and `delete(_:)`. A pure `HistoryEntry` is built from a stored snapshot at its last recorded instant. A `@MainActor @Observable HistoryModel` holds the entries, the selection and the deletion flow; the selected day's details are a 2c `DayOverviewModel` fed by a snapshot-backed `SnapshotSource`, so the 2c views are reused unchanged. A small `AppRouter` holds the selected tab so the popover can open the window on the right one.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (`List`, `confirmationDialog`, `Picker`), Observation, Swift Testing, `RipelineCore` (unchanged), `xcodebuild`.

**Spec:** [`docs/specs/2026-10-01-stage-2d-history-design.md`](../specs/2026-10-01-stage-2d-history-design.md). Parents: [`SPEC.md`](../../SPEC.md), specs 2a, 2b, 2c.

## Global Constraints

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, zero warnings from our code.
- `MACOSX_DEPLOYMENT_TARGET = 26.0`; only APIs available on macOS 26.
- Public APIs only; App Sandbox; **entitlements stay exactly `com.apple.security.app-sandbox`**; no network; no data collected.
- No personal data in the repo; a fresh clone must build and test without `Config/Local.xcconfig`.
- All code, comments and docs in English. Every user-facing string from `Localizable.xcstrings` with `en` (base) and `uk`; the catalog completeness test stays green. No counts are shown (no plural variations).
- `RipelineCore` is not modified by this plan.
- Commit identity is configured; **no Claude attribution** in commits or PR text.
- Tests: Swift Testing. No real sleeping, no real `Application Support`, no real notification center in unit tests (the inert environment stays). A test that can hang must be guarded so that failure is a failure, not a hang.
- A throwaway check that reads the developer's real day files must be **read-only** and must never be committed.
- Commands: `scripts/test-app.sh [SuiteName]` (app; wrap in `timeout 115`), `swift test --package-path Packages/RipelineCore` (core).

## Decisions where the spec is silent or this plan refines it (please confirm)

| # | Decision | Why |
|---|----------|-----|
| X1 | `DaySummary.endIsFinal: Bool` becomes `endKind` (`projected`, `final`, `lastRecord`); `DayOverviewSource` gains `overviewLastRecord: Date?` with a default of `nil`. For a finished day with an actual end the kind is `final`; for a day never ended but with records it is `lastRecord`; with nothing recorded it is `final` with no time. | Spec §3.3: the summary says "Last record at" for a day that was never ended. |
| X2 | `loadAll()` skips damaged and newer-version files **without renaming them** (unlike `loadLatest()`), and skips any entry that cannot be read. | Spec §3.1; listing must be side-effect free. |
| X3 | Order is by the plan's first start, newest first; ties (several days with the same start) by file name, higher number first. | Matches `loadLatest`'s notion of "latest"; stable. |
| X4 | `delete` of a day whose file is already gone is a silent success. | Spec: "deleting twice is safe". |
| X5 | The running day is the controller's day while its phase is working, on break, paused or overtime, identified by the id of its first segment; a finished current day *is* listed. | Spec H4 excludes only the running day; a day just finished is history. |
| X6 | A row shows its lag (actual end minus planned end) as a small signed text for a finished day. | Spec §3.2 lists the figure; it costs one label. |
| X7 | The recorded start of a row is the first recorded interval's start, falling back to the plan's start; the end is the last recorded instant, `nil` when nothing was recorded. | A day cut short or never started must not show plan times as if they happened. |
| X8 | The row's date title uses the locale's abbreviated weekday, day and month (`Thu 15 Jan`, `чт, 15 січ.`); the VoiceOver label uses the wide forms. | Locale-aware without our own tables. |
| X9 | The History tab is not shown to be selected after a day starts; the tab choice only changes when the user or the popover changes it. | Starting a day on "Today" must not hop tabs. |

## Review Focus

1. **Deleting the wrong thing.** Delete removes exactly the chosen day's file; the running day cannot be requested; a day that becomes the running day between the request and the confirmation is refused; deleting twice, or while the file is already gone, is safe; `.corrupt`/`.unsupported` files are never removed. *Tests in Tasks 1 and 3.*
2. **Selection integrity.** After refresh, delete (middle, last, only day), cancel and a failed delete the selection points at a day that exists and the details match it; a selection that vanished falls to the neighbour. *Tests in Task 3.*
3. **Abandoned vs finished vs running.** A day left unfinished by an earlier run is listed as "Not finished" and drawn at its last record (it does not grow with the clock); the restored running day is excluded; a day ended before anything was recorded shows no end. *Tests in Tasks 2 and 3.*
4. **Odd files.** Corrupt JSON, a newer version, a directory named like a day, an empty directory: the rest still lists, nothing is renamed or deleted by listing. *Tests in Task 1.*
5. **Time zones and dates.** Titles and times use the current zone; days saved in other zones, a day crossing midnight and a daylight-saving day sort and read sensibly. *Tests in Tasks 1, 3 and 4.*

---

## File Structure

```
App/
  Persistence/DayStore.swift            (modified) loadAll, delete
  Persistence/FileDayStore.swift        (modified)
  Persistence/InMemoryDayStore.swift    (modified)
  Overview/DayOverviewModel.swift       (modified) overviewLastRecord, DaySummary.endKind
  History/
    SnapshotSource.swift                DayOverviewSource over one snapshot
    HistoryEntry.swift                  HistoryEntry + construction
    HistoryModel.swift
    HistoryText.swift                   date title, row line, badge, VoiceOver label
  Navigation/AppRouter.swift            WindowTab, AppRouter
  Views/
    HistoryRowView.swift, HistoryDetailView.swift, HistoryView.swift
    RipelineWindowView.swift            (modified) tabs
    DaySummaryView.swift                (modified) the end label
    PopoverView.swift                   (modified) History link
  Presentation/PopoverActions.swift     (modified) .history
  Runtime/SessionController.swift       (modified) activeDayID
  AppEnvironment.swift                  (modified) router, historyModel
AppTests/
  Support/MemoryDayStore.swift          (modified)
  FileDayStoreHistoryTests.swift, SnapshotSourceTests.swift, HistoryEntryTests.swift,
  HistoryModelTests.swift, HistoryTextTests.swift, HistoryRelaunchTests.swift
```

Fixtures as before: `t(h, m, s)` (2026-01-15, UTC), `d(day, h, m, s)`, `utcDate(...)`, `calendar(offsetHours:)`, `calendar(zone:)`, `makePlan`, `fivePlan(start:)`, `idleSnapshot`, `startedSnapshot`, `finishedSnapshot`, `Harness`, `TestClock`, `EngineSource`. New helpers (in `Fixtures.swift`):

```swift
/// A day played on a real engine and returned as a snapshot. `script` receives the engine and the clock.
func playedDay(
    plan: [PlannedSegment] = fivePlan(), settings: SessionSettings = SessionSettings(),
    _ script: (inout SessionEngine, TestClock) throws -> Void
) throws -> SessionSnapshot
```
`finishedDay(start:)` = a day on `fivePlan(start:)` started at its start and ended 30 minutes later. `abandonedDay(start:)` = the same, started and left running with a pause recorded, never ended.

---

### Task 1: DayStore.loadAll and delete

**Files:**
- Modify: `App/Persistence/DayStore.swift`, `FileDayStore.swift`, `InMemoryDayStore.swift`, `AppTests/Support/MemoryDayStore.swift`, `AppTests/Support/Fixtures.swift`
- Create: `AppTests/FileDayStoreHistoryTests.swift`

**Interfaces — Produces:**
```swift
@MainActor protocol DayStore {
    // existing: loadLatest, save, quarantine
    /// Every readable day, newest first (X3). Damaged and newer-version files, and anything unreadable, are skipped without being renamed (X2).
    func loadAll() throws -> [StoredDay]
    /// Removes the day's file. A file that is already gone is not an error (X4); `.corrupt` and `.unsupported` files are never touched.
    func delete(_ day: StoredDay) throws
}
```
`InMemoryDayStore` returns its one day and deletes it. `MemoryDayStore` (test double) gets `var days: [StoredDay]` used by `loadAll` (falls back to `[latest]`), records `deleted: [StoredDay]`, and can be told `failDelete`.

- [ ] **Step 1: Failing tests** (`FileDayStoreHistoryTests`, temp directory per test):

| Test | Behavior |
|------|----------|
| order | days starting 01-13, 01-15 09:00, 01-14, and a second 01-15 at 13:00 (saved as `-2`) → `loadAll` keys `[2026-01-15-2, 2026-01-15, 2026-01-14, 2026-01-13]` |
| one date, several days | three days on one date come back newest first and none is lost |
| other time zones | a day saved by a +03:00 calendar (key from that zone) and one by UTC sort by their real start, not by key |
| corrupt and newer files skipped (Review Focus 4) | a corrupt `…json` and a `{"version":2,…}` among valid days: the valid ones list; **no file is renamed** (directory listing unchanged) |
| unreadable entry | a directory named `2026-01-16.json` is skipped; the rest list |
| empty and missing directory | `[]` |
| `.corrupt` and `.unsupported` ignored | such files next to valid days are not returned |
| delete | `delete(day)` removes `<key>.json`; the other days remain and `loadAll` no longer returns it |
| delete safety (Review Focus 1) | `.corrupt` and `.unsupported` files and other days' files are untouched; deleting the same day twice does not throw; deleting a day whose file never existed does not throw |
| delete failure keeps the file | make the removal fail (a non-empty directory named like a day file) → throws; nothing else removed |
| a deleted day can be saved again | save, delete, save a new day on the same date → it takes the first free name |

- [ ] **Step 2:** Run `timeout 115 scripts/test-app.sh FileDayStoreHistoryTests` → fails to compile. **Step 3:** Implement (`loadAll` reuses `dayFiles()` and `read`; sorts by plan start desc, then by file sequence desc; `delete` also clears `fileForDay` entries for that day). **Step 4:** Run → PASS (full suite). **Step 5:** Commit `List and delete days in the store`.

### Task 2: SnapshotSource and the end kind

**Files:**
- Create: `App/History/SnapshotSource.swift`, `AppTests/SnapshotSourceTests.swift`
- Modify: `App/Overview/DayOverviewModel.swift`, `App/Views/DaySummaryView.swift`, `AppTests/DayOverviewModelTests.swift`, `AppTests/OverviewRelaunchTests.swift`, `AppTests/Support/EngineSource.swift`

**Interfaces — Produces:**
```swift
extension DayOverviewSource { var overviewLastRecord: Date? { nil } }       // in the protocol: `var overviewLastRecord: Date? { get }`

@MainActor final class SnapshotSource: DayOverviewSource {
    init(snapshot: SessionSnapshot)
    /// The latest end of a recorded interval, or the start of the open one; nil if nothing was recorded.
    static func lastRecordedInstant(of snapshot: SessionSnapshot) -> Date?
    // hasDay true; overviewPhase .finished; overviewNow == overviewLastRecord ?? the plan's first start;
    // timeline/comparison from Timeline(snapshot:now:) and DayComparison(snapshot:now:) at that instant; status nil.
}

struct DaySummary { /* … */ let endKind: EndKind; enum EndKind: Equatable, Sendable { case projected, final, lastRecord } }
```
Model rule (X1): running → `endsAt = status.projectedEnd`, `.projected`; finished with `totals.actualEnd` → that, `.final`; finished without it but with `overviewLastRecord` → that, `.lastRecord`; otherwise `nil`, `.final`. `DaySummaryView`: `.projected` → "Projected end", `.final` → "Finished at", `.lastRecord` → "Last record at" (`history.lastRecord`, added in Task 4; use the key now with its catalog entry).

- [ ] **Step 1: Failing tests:**
  - `lastRecordedInstant`: nothing recorded → `nil`; a started day → the open interval's start; a paused-and-resumed day → the latest closed interval end; a finished day → its end.
  - the same snapshot through `SnapshotSource` and through a live `DayOverviewModel` over `EngineSource` at the same instant gives the same planned and actual blocks, summary figures and segment table (the 2a review scenario, finished).
  - Review Focus 3: an abandoned day (started 09:00, paused 09:30–09:35, never ended) is drawn at 09:35 + its open interval: actual blocks stop at the last record and **do not grow** when the test clock moves a day later; `mode == .finished`; `nowX == nil`; `lag == nil`; summary `endKind == .lastRecord`, `endsAt` = the last record.
  - a day ended before anything was recorded: `endKind == .final`, `endsAt == nil`, no actual blocks, the axis from the plan.
  - the existing `endIsFinal` assertions in `DayOverviewModelTests` and `OverviewRelaunchTests` become `endKind == .final` / `.projected`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Draw a stored day at its last record`.

### Task 3: HistoryEntry and HistoryModel

**Files:**
- Create: `App/History/HistoryEntry.swift`, `App/History/HistoryModel.swift`, `AppTests/HistoryEntryTests.swift`, `AppTests/HistoryModelTests.swift`
- Modify: `App/Runtime/SessionController.swift`

**Interfaces — Produces:**
```swift
struct HistoryEntry: Equatable, Identifiable, Sendable {
    let id: String                       // the store key
    let snapshot: SessionSnapshot
    let startedAt: Date                  // first recorded start, else the plan's first start (X7)
    let endedAt: Date?                   // last recorded instant; nil if nothing was recorded
    let focusActual: TimeInterval, focusPlanned: TimeInterval, restActual: TimeInterval
    let isFinished: Bool
    let lag: TimeInterval?               // actual end − planned end, finished days with records only (X6)
    init(day: StoredDay)
}

@MainActor @Observable final class HistoryModel {
    init(store: any DayStore, activeDayID: @escaping @MainActor () -> UUID?, calendar: Calendar = .autoupdatingCurrent)
    private(set) var entries: [HistoryEntry]
    private(set) var selection: String?                 // an entry id
    private(set) var detail: DayOverviewModel?          // for the selection, over a SnapshotSource
    private(set) var pendingDelete: HistoryEntry?
    private(set) var deleteFailed: Bool
    private(set) var loadFailed: Bool
    func refresh()                                      // reads the store; keeps the selection if it exists, else the newest
    func select(_ id: String?)
    func requestDelete(_ id: String)                    // refused for the running day or an unknown id
    func confirmDelete()                                // deletes, selects the neighbour (next older, else newer), refreshes
    func cancelDelete()
}
extension SessionController { var activeDayID: UUID? { get } }   // the first segment's id while working, on break, paused or in overtime
```
`refresh()` calls `loadAll()` and drops the running day (`entries` filter by `activeDayID`); a throwing `loadAll` sets `loadFailed` and keeps the previous entries.

- [ ] **Step 1: Failing tests:**
  - `HistoryEntryTests`: a finished day (`fivePlan` from 09:00, started 09:00, ended 09:30 after a pause counted untracked): `startedAt` 09:00, `endedAt` 09:30, focus actual and planned, `isFinished`, `lag == actual end − planned end`; the 2a review scenario figures (focus 83/100, rest 12); an abandoned day: not finished, `endedAt` = last record, `lag == nil`; a day ended before it began: `endedAt == nil`, `startedAt` = plan start, no lag; a day crossing midnight.
  - `HistoryModelTests` (`MemoryDayStore`, a stub `activeDayID`):

| Test | Behavior |
|------|----------|
| list | three days → entries newest first; the default selection is the newest and `detail` is its overview |
| running day excluded (Review Focus 3) | one stored day's first-segment id equals `activeDayID()` → not listed; a finished current day (not running → `activeDayID` nil) is listed |
| empty | no days → `entries` empty, `selection` nil, `detail` nil |
| select | `select(id)` swaps `detail`; selecting an unknown id leaves the selection unchanged |
| delete middle | request, confirm → the store got `delete` for exactly that day, entries lose it, selection moves to the next older day, `detail` matches |
| delete last in the list | selection moves to the newer neighbour |
| delete the only day | empty state |
| cancel | `cancelDelete()` changes nothing and calls no `delete` |
| refused | `requestDelete` of the running day or an unknown id leaves `pendingDelete` nil |
| becomes running before confirming (Review Focus 1) | request, then `activeDayID` returns that day's id, confirm → no `delete`, the request is dropped |
| failure | `failDelete` → the day stays in the list and the selection, `deleteFailed == true`; a later successful delete clears it |
| refresh keeps selection | add a newer day to the store, `refresh()` → selection unchanged, entries gain the new one |
| refresh drops a vanished selection | the selected day disappears from the store → selection falls to the newest; no crash |
| load failure | `loadAll` throws → `loadFailed`, entries kept |
| abandoned day detail | selecting an abandoned day gives a `.finished` overview that does not change as the clock moves |

  - `SessionController.activeDayID`: `nil` with no day and when finished; the first segment's id while working, on break, paused and in overtime.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Add the history model`.

### Task 4: History texts

**Files:**
- Create: `App/History/HistoryText.swift`, `AppTests/HistoryTextTests.swift`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces — Produces:**
```swift
enum HistoryText {
    static func dateTitle(_ date: Date, locale: Locale, timeZone: TimeZone) -> String          // "Thu 15 Jan" / "чт, 15 січ."
    static func rowSubtitle(_ entry: HistoryEntry, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String
        // "10:02–12:40 · Focus 2 hr, 13 min / 4 hr"; without an end: "10:02 · Focus …"
    static func badge(_ entry: HistoryEntry, bundle: Bundle = .main) -> String                  // "Finished" / "Not finished"
    static func accessibilityLabel(_ entry: HistoryEntry, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String
        // "Thursday 15 January, from 10:02 to 12:40, finished, focus 2 hr, 13 min of 4 hr"
}
```
Catalog keys (en / uk): `history.finished` "Finished" / "Завершено"; `history.notFinished` "Not finished" / "Не завершено"; `history.lastRecord` "Last record at" / "Останній запис о"; `history.empty` "No days yet" / "Поки немає днів"; `history.emptyHint` "Finished days appear here." / "Завершені дні зʼявляться тут."; `history.delete` "Delete day…" / "Видалити день…"; `history.deleteTitle` "Delete this day?" / "Видалити цей день?"; `history.deleteMessage` "It is removed from this Mac and cannot be restored." / "Його буде видалено з цього Mac без можливості відновлення."; `history.deleteConfirm` "Delete" / "Видалити"; `history.deleteFailed` "The day could not be deleted." / "Не вдалося видалити день."; `history.loadFailed` "The days could not be read." / "Не вдалося прочитати дні."; `tab.today` "Today" / "Сьогодні"; `tab.history` "History" / "Історія"; `ui.history` "History…" / "Історія…"; `a11y.historyRow` "%@, from %@ to %@, %@, focus %@ of %@" / "%@, з %@ до %@, %@, фокус %@ із %@"; `a11y.historyRowStarted` "%@, from %@, %@, focus %@ of %@" / "%@, з %@, %@, фокус %@ із %@". The `Cancel` button uses the system's localized "Cancel" (`.cancel` role).

- [ ] **Step 1: Failing tests:** `dateTitle` for 2026-01-15 in `en_GB` ("Thu 15 Jan"), `uk` ("чт, 15 січ."), across zones (22:30 UTC on the 14th is the 15th at +03:00); `rowSubtitle` for a finished entry in `en` and `uk` (times, the focus label and both durations), for an entry without an end, and with a +03:00 zone; `badge` in both languages for finished and not finished, distinct and not raw keys; `accessibilityLabel` in `en` and `uk` for a finished day, an abandoned day and a day without an end, containing the wide date, the times and the focus; catalog completeness.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement and add the keys. **Step 4:** Run → PASS. **Step 5:** Commit `Add the history texts`.

### Task 5: History views

**Files:**
- Create: `App/Views/HistoryRowView.swift`, `HistoryDetailView.swift`, `HistoryView.swift`

**Interfaces — Consumes:** Tasks 1–4 and the 2c views. **Produces:**
- `HistoryRowView(entry:)`: the date title (headline), the subtitle (secondary), a badge ("Finished" green / "Not finished" orange, as text and not colour only) and, for a finished day with a lag, the signed `OverviewText.delta`; the row has `.accessibilityElement(children: .ignore)` and the label from `HistoryText.accessibilityLabel`.
- `HistoryDetailView(model: DayOverviewModel, entry:, onDelete:)`: the title and times, `TimelineRowsView`, `DaySummaryView`, `SegmentTableView`, a "Delete day…" button (destructive role) and the not-finished note; read only.
- `HistoryView(model: HistoryModel)`: a `List(selection:)` of rows on the left (about 260 pt) and the detail on the right; the empty state (`history.empty` + hint); the `loadFailed` and `deleteFailed` messages under the list; the delete `confirmationDialog` (`history.deleteTitle`, `history.deleteMessage`, destructive `history.deleteConfirm`, `.cancel`) bound to `model.pendingDelete`; `refresh()` on appear.

- [ ] **Step 1:** No unit tests for the views (they only display the model). Write them.
- [ ] **Step 2:** `timeout 115 scripts/test-app.sh` → PASS; build without warnings.
- [ ] **Step 3 (visual check):** a throwaway test (not committed) renders `HistoryRowView` for a finished day, an abandoned day and a day without an end, and `HistoryDetailView`'s timelines, summary and table for the 2a review scenario and an abandoned day (`en` and `uk`), through `ImageRenderer`; read the PNGs from the app container's temp directory and check them by eye; fix what looks wrong; delete the test and the images.
- [ ] **Step 4:** Commit `Add the history views`.

### Task 6: Tabs, router and the popover link

**Files:**
- Create: `App/Navigation/AppRouter.swift`
- Modify: `App/Views/RipelineWindowView.swift`, `App/Views/PopoverView.swift`, `App/Presentation/PopoverActions.swift`, `App/AppEnvironment.swift`, `App/RipelineApp.swift`, `AppTests/PopoverActionsTests.swift`, `AppTests/AppEnvironmentTests.swift`

**Interfaces — Produces:**
```swift
enum WindowTab: Hashable, Sendable { case today, history }
@MainActor @Observable final class AppRouter { var tab: WindowTab = .today }

enum PopoverAction { …, case history }   // titleKey "ui.history"; sessionAction nil
```
`PopoverActions.visible` appends `.history` last in every phase (after `.overview`). `AppEnvironment` gains `router: AppRouter` and `historyModel: HistoryModel` (store, `activeDayID` from the controller) in both the live and the inert environment. `RipelineWindowView` shows a segmented `Picker` ("Today | History", bound to `router.tab`) above its content: "Today" is the existing screen, "History" is `HistoryView`; it also calls `historyModel.refresh()` when the controller's phase changes (X9: it never changes the tab by itself). The popover's "Plan day…", "Day overview…" and "Day summary…" set `router.tab = .today` before opening the window; "History…" sets `.history`; the popover draws `.overview` and `.history` as link-style buttons under the glass row.

- [ ] **Step 1: Failing tests:** `PopoverActionsTests` — every phase's list ends with `.history` (idle `[.planDay, .history]`, finished `[.summary, .history]`, running `[…, .overview, .history]`); `.history` is shown whatever the engine allows; its `sessionAction` is `nil` and its title key `ui.history`. `AppEnvironmentTests` — the inert environment has a `router` (starting on `.today`) and a `historyModel`; driving a day leaves the real directory alone and the history model lists nothing from it; `router.tab` is unchanged by starting a day (X9).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run the full suite → PASS; clean build, no warnings. Launch the app and confirm it stays alive.
- [ ] **Step 5:** Commit `Add the history tab`.

### Task 7: End to end, documentation and verification

**Files:**
- Create: `AppTests/HistoryRelaunchTests.swift`
- Modify: `README.md`, `docs/specs/2026-10-01-stage-2d-history-design.md` (status, decisions X1–X9), `SPEC.md` (stage table: 2d done)

- [ ] **Step 1: End-to-end test** over a real `FileDayStore` in a temporary directory, as the earlier relaunch tests: several days (a finished one with an untracked pause, one abandoned, one more finished) are recorded through controllers; a `HistoryModel` over a new store instance lists them newest first with the right figures; one is deleted and a relaunch lists the rest; the running day of a live controller is not in the list and cannot be deleted; deleting leaves the other files byte-for-byte unchanged.
- [ ] **Step 2:** Update the docs.
- [ ] **Step 3:** Run everything and read the output: `swift test --package-path Packages/RipelineCore`, `scripts/test-app.sh`, a clean-clone `scripts/test-app.sh` (no `Local.xcconfig`), a warning-free `xcodebuild clean build`.
- [ ] **Step 4 (real days, read-only):** a throwaway hosted test (not committed) calls `FileDayStore(directory: defaultDirectory()).loadAll()` against the developer's real container, prints the keys and counts, and asserts nothing about them but that it does not throw; confirm the real files load (and that the directory listing is identical before and after). Delete the test.
- [ ] **Step 5:** Launch the app and record what could and could not be checked from the command line.
- [ ] **Step 6:** Write the **manual checklist** for the PR: the popover shows "History…" in every phase and opens the window on the History tab; the list shows the real days newest first with date, times, focus and the badge; selecting a day shows its timelines, summary and table, and a never-ended day says "Last record at"; the running day is not in the list; "Delete day…" asks first, deletes only that day, and the selection moves to a neighbour; the empty state reads well after deleting everything; "Today" keeps its state while on the History tab; English and Ukrainian; VoiceOver reads a row as a sentence.
- [ ] **Step 6b:** Commit `Document stage 2d`.

---

## Spec coverage check

| Spec section | Task |
|---|---|
| §1 criterion 1 (tab, list, read-only details) | 3, 5, 6 |
| §1 criterion 2 (abandoned day marked, drawn at its last record) | 2, 3, 4, 5 |
| §1 criterion 3 (delete with confirmation; running day safe; failure kept) | 1, 3, 5 |
| §1 criterion 4 (one damaged file hides nothing) | 1 |
| §1 criterion 5 (strings, entitlements) | 4, 6 |
| §3.1 store | 1 |
| §3.2 entries | 3 |
| §3.3 SnapshotSource | 2 |
| §3.4 HistoryModel | 3 |
| §4 interface (tabs, list, details, delete, popover, accessibility, localization) | 4, 5, 6 |
| §5 testing and verification | every task; 7 |
