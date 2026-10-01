# Stage 2c — Day Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show how the day goes against the plan: planned and actual timelines on one horizontal axis with a "now" marker, the lag, a plan-versus-actual summary and a segment table, plus the session settings, in one window that also hosts the 2b planning form.

**Architecture:** The core already computes `Timeline`, `DayComparison` and `ScheduleStatus`. `SessionController` exposes them for the current time. A pure `TimeAxis` and a `@MainActor @Observable DayOverviewModel` (reading through a small `DayOverviewSource` protocol) turn them into geometry, lag, summary and table rows. Plain SwiftUI views draw that output. One `Window` shows the planning form when there is no day and the day screen otherwise; the popover gets one entry that opens it.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (`Window`, `GeometryReader`, `Grid`, `DisclosureGroup`), Observation, Swift Testing, `RipelineCore` (unchanged), `xcodebuild`.

**Spec:** [`docs/specs/2026-10-01-stage-2c-day-screen-design.md`](../specs/2026-10-01-stage-2c-day-screen-design.md). Parents: [`SPEC.md`](../../SPEC.md), [2a](../specs/2026-10-01-stage-2a-app-shell-design.md), [2b](../specs/2026-10-01-stage-2b-day-setup-design.md).

## Global Constraints

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, zero warnings from our code.
- `MACOSX_DEPLOYMENT_TARGET = 26.0`; only APIs available on macOS 26.
- Public APIs only; App Sandbox; **entitlements stay exactly `com.apple.security.app-sandbox`**; no network; no data collected.
- No personal data in the repo; a fresh clone must build and test without `Config/Local.xcconfig`.
- All code, comments and docs in English. Every user-facing string from `Localizable.xcstrings` with `en` (base) and `uk`; the catalog completeness test stays green. No counts are shown (no plural variations).
- `RipelineCore` is not modified by this plan.
- Commit identity is configured; **no Claude attribution** in commits or PR text.
- Tests: Swift Testing. No real sleeping, no real `Application Support`, no real notification center in unit tests (the inert environment stays). A test that can hang must be guarded so that failure is a failure, not a hang.
- Commands: `scripts/test-app.sh [SuiteName]` (app; wrap in `timeout 115`), `swift test --package-path Packages/RipelineCore` (core).

## Decisions where the spec is silent or this plan refines it (please confirm)

| # | Decision | Why |
|---|----------|-----|
| R1 | The model reads the controller through a protocol `DayOverviewSource` (a stub in tests). | Tests drive the model without a controller, store or notifier. |
| R2 | `PopoverAction.sessionAction` becomes optional; `nil` means "always shown" (the overview link and summary button do not map to an engine action). | The two new actions are not engine actions. |
| R3 | The 2b `Window("window.setup.title", id: "day-setup")` and `DaySetupWindow` are replaced by one `Window("app.name", id: MainWindow.id)`. The catalog key `window.setup.title` is removed. | One window for both contents (spec C3); the title is the app name, so no new key. |
| R4 | The axis domain is floored and ceiled to the step in the calendar's wall-clock time; ticks then advance by the absolute step. Across a daylight-saving change a tick label is the real local time of that instant. | Deterministic and correct positions; no crash on missing or repeated hours. |
| R5 | "Now" on screen comes from the clock (`clock.now`), not from the controller's `now`. | `controller.now` is frozen while paused or idle; the marker must keep moving. |
| R6 | Minimum drawn block width (spec C8) is applied by the view; the model returns exact fractions. | Keeps the arithmetic exact and testable. |
| R7 | No overtime marker (spec C10). | The core records overtime as ordinary time. |
| R8 | Timelines are rendered once with a throwaway `ImageRenderer` test to check them by eye (not committed). | Screenshots are not available from the command line; plain SwiftUI shapes do render there, forms and pickers do not. |
| R9 | The "Behaviour" switches call `SessionController.updateSessionSettings(_:)` in every mode, including with no day. | Settings apply to the next day too; an idle engine accepts them harmlessly. |

## Review Focus

1. **Axis edges.** A single instant, zero-length blocks, a day crossing midnight, a daylight-saving day, an actual block that starts before the plan or ends after it, a 12-hour day: no division by zero, no negative width, all `x` in 0…1. *Tests in Tasks 2 and 3.*
2. **Mode transitions.** Running → finished → new day, and "New day" pressed in the finished screen then a start: the content switches without a stuck state; the planning form state is kept. *Tests in Tasks 3 and 6.*
3. **Settings mid-day apply only to the future.** Changing auto-advance or "pauses count as rest" during a day must not rewrite recorded time or advance a segment that is already in overtime; an open pause keeps its kind. *Tests in Task 1.*
4. **Odd data.** No day; a day ended before anything was recorded (nothing actual, no actual end); a day with only skipped segments; the model never crashes and shows "—" where there is no value. *Tests in Task 3.*
5. **Cost when closed.** The model does nothing unless the window refreshes it; `refresh()` is idempotent and cheap for a long day. *Tests in Task 3; the view owns the refresh timer (Task 5).*

---

## File Structure

```
App/
  Overview/
    TimeAxis.swift             TimeAxis, TimeAxis.Tick
    DayOverviewModel.swift     DayOverviewSource, Mode, BlockLayout, LagState, DaySummary, SegmentRow, model
    OverviewText.swift         lag chip, block label and tooltip, delta, status texts
  Views/
    TimelineRowsView.swift     the two rows, axis labels, now marker, legend
    SegmentTableView.swift     the table
    DaySummaryView.swift       summary figures
    BehaviourSection.swift     the three switches
    DayScreenView.swift        header + rows + summary + table + behaviour + End day
    RipelineWindowView.swift   chooses the planning form or the day screen
    DaySetupView.swift         (modified) hosts the Behaviour section; DaySetupWindow removed
  Presentation/PopoverActions.swift  (modified) overview / summary actions
  Runtime/SessionController.swift    (modified) timeline, comparison, updateSessionSettings, DayOverviewSource
  AppEnvironment.swift, RipelineApp.swift, Views/PopoverView.swift  (modified)
AppTests/
  SessionControllerOverviewTests.swift, TimeAxisTests.swift, DayOverviewModelTests.swift,
  OverviewTextTests.swift, OverviewRelaunchTests.swift
  Support/EngineSource.swift    DayOverviewSource over a real SessionEngine and TestClock
```

Fixtures as in the earlier plans: `t(h, m, s)` is 2026-01-15, UTC; `utcDate(...)`, `calendar(offsetHours:)`, `calendar(zone:)`, `makePlan`, `Harness`, `TestClock` exist. The "stage 1 day" is 09:00–17:00, 50/10/45, long break 12:50–13:35, 7 blocks of 50 minutes plus 25, as `DaySetup` produces it.

---

### Task 1: Controller read models and session settings

**Files:**
- Modify: `App/Runtime/SessionController.swift`
- Create: `AppTests/SessionControllerOverviewTests.swift`

**Interfaces — Produces:**
```swift
extension SessionController {
    var timeline: Timeline { get }            // engine.timeline(), current time; reads `now` for observation
    var comparison: DayComparison { get }
    /// Writes AppSettings.session and the running engine; effective from the next transition.
    func updateSessionSettings(_ settings: SessionSettings)
}
```
`scheduleStatus` already exists. `updateSessionSettings` sets `settings.session`, calls `engine.updateSettings`, and does not touch recorded time; the snapshot (which carries the settings) is saved by the next `persistIfChanged` (call `didChange()`).

- [ ] **Step 1: Failing tests** (`Harness`, standard day 4 h of 50/10 from 09:00):
  - `timeline.planned` mirrors the plan; at 09:20 `timeline.actual == [work 09:00–09:20]`; `comparison.rows[0].work == 20 min`, `comparison.totals.focusPlanned` matches the plan.
  - after an overtime (`clock` 09:55, no auto-advance) the actual block runs to now and `comparison.rows[0].delta == +5 min`.
  - `updateSessionSettings(autoAdvanceWorkToBreak: true)` writes `settings.session`, and the snapshot saved by the next change carries it (`store.saved.last?.settings`).
  - **Review Focus 3:** with auto-advance off, in overtime at 09:55, enabling it does **not** advance the segment (phase stays overtime) and does not rewrite recorded intervals; during a pause with `pausesCountAsRest == true` the open pause stays `.rest` after switching the setting off, and the next pause is `.untracked`; enabling auto-advance at 09:20 makes the segment that ends at 09:50 advance by itself.
  - before any day: `updateSessionSettings` stores the value and the next `startDay(request:)` uses it.
- [ ] **Step 2:** Run `timeout 115 scripts/test-app.sh SessionControllerOverviewTests` → fails to compile. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Expose the day's timeline and comparison and update session settings`.

### Task 2: TimeAxis

**Files:**
- Create: `App/Overview/TimeAxis.swift`, `AppTests/TimeAxisTests.swift`

**Interfaces — Produces:**
```swift
struct TimeAxis: Equatable, Sendable {
    struct Tick: Equatable, Sendable { let date: Date; let x: Double }
    let start: Date, end: Date          // the domain, a whole number of steps wide
    let step: TimeInterval              // 1800, 3600 or 7200 seconds
    let ticks: [Tick]                   // first at `start` (x 0), last at `end` (x 1)
    init?(covering dates: [Date], calendar: Calendar)    // nil when `dates` is empty
    func x(for date: Date) -> Double    // clamped to 0...1
    static func step(forSpan span: TimeInterval) -> TimeInterval
}
```
Rules (spec C7): span up to 4 h → 1800 s, up to 10 h → 3600 s, beyond → 7200 s. The domain starts at the earliest date floored, and ends at the latest date ceiled, to a multiple of the step counted from local midnight in `calendar` (R4). If that gives zero width (a single instant on a tick), the domain is one step wide. Ticks are `start + k·step`.

- [ ] **Step 1: Failing tests** (UTC unless noted):

| Test | Input | Expected |
|------|-------|----------|
| the stage 1 day | dates 09:00 and 17:00 | step 3600; domain 09:00–17:00; 9 ticks; x of 09:00 is 0, of 17:00 is 1; `x(for: 12:50)` ≈ 0.4792 |
| rounding out | 09:07 and 11:42 | span 2 h 35 → step 1800; domain 09:00–12:00 |
| ceil and floor on a boundary | 09:00 and 11:00 exactly | domain unchanged |
| long day | 08:00 and 20:00 | step 7200; ticks 08:00,10:00,…,20:00 |
| 10-hour boundary | 08:00 and 18:00 | step 3600 (10 h is "up to 10 h") |
| single instant | one date 09:00 (exactly on a tick); one date 09:20 | 09:00–09:30 for the first (widened by one step); 09:00–09:30 for the second (floor and ceil already one step wide) |
| empty | `[]` | `nil` |
| clamping | `x(for:)` before start / after end | 0 / 1 |
| time zone | +03:00 calendar, dates 06:00Z and 14:00Z | ticks on local whole hours (09:00…17:00 local); labels' instants are 06:00Z…14:00Z |
| crossing midnight | 22:00 and 02:00 next day | step 3600; ticks continue past midnight; strictly increasing |
| daylight saving | New York 2026-03-08, 00:30 EST to 05:00 EDT | ticks strictly increasing, all inside the domain, first x 0, last x 1, no crash |
| property | for 200 generated pairs of dates (seeded) | `start ≤ min`, `end ≥ max`, ticks increasing, x in 0…1 |

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS. **Step 5:** Commit `Add the time axis`.

### Task 3: DayOverviewModel

**Files:**
- Create: `App/Overview/DayOverviewModel.swift`, `AppTests/Support/EngineSource.swift`, `AppTests/DayOverviewModelTests.swift`
- Modify: `App/Runtime/SessionController.swift` (conform to `DayOverviewSource`)

**Interfaces — Consumes:** Tasks 1–2. **Produces:**
```swift
@MainActor protocol DayOverviewSource: AnyObject {
    var hasDay: Bool { get }
    var overviewPhase: Phase { get }
    var overviewTimeline: Timeline { get }
    var overviewComparison: DayComparison { get }
    var overviewStatus: ScheduleStatus? { get }
    var overviewNow: Date { get }                    // the clock (R5), not the controller's frozen `now`
}

struct BlockLayout<Kind: Equatable & Sendable>: Equatable, Sendable {
    let kind: Kind; let start: Date; let end: Date
    let x: Double; let width: Double                 // fractions of the axis, 0...1
}
enum LagState: Equatable, Sendable { case onSchedule, behind(TimeInterval), ahead(TimeInterval) }   // |lag| < 60 s is onSchedule
struct DaySummary: Equatable, Sendable {
    let focusPlanned, focusActual, restPlanned, restActual, untracked: TimeInterval
    let plannedEnd: Date?
    let endsAt: Date?          // projected end while running; actual end once finished; nil if unknown
    let endIsFinal: Bool
}
struct SegmentRow: Equatable, Sendable {
    let index: Int; let start: Date; let kind: SegmentKind
    let planned, work, rest, untracked: TimeInterval
    var actual: TimeInterval { get }; var delta: TimeInterval { get }
    let status: SegmentStatus
}

@MainActor @Observable final class DayOverviewModel {
    enum Mode: Equatable, Sendable { case noDay, running, finished }
    init(source: any DayOverviewSource, calendar: Calendar = .autoupdatingCurrent)
    private(set) var mode: Mode
    private(set) var axis: TimeAxis?
    private(set) var planned: [BlockLayout<SegmentKind>]
    private(set) var actual: [BlockLayout<ActualKind>]
    private(set) var nowX: Double?                       // only while running
    private(set) var lag: LagState?
    private(set) var summary: DaySummary?
    private(set) var segments: [SegmentRow]
    func refresh()                                       // idempotent; no day gives empty values, never fails
}
```
`EngineSource` (test support): wraps a `SessionEngine` and a `TestClock`, implementing `DayOverviewSource` from `engine.timeline()`, `.comparison()`, `.scheduleStatus()`.
Rules: axis covers planned blocks, actual blocks and, while running, now. `mode`: `!hasDay` or phase `.idle` → `.noDay`; phase `.finished` → `.finished`; otherwise `.running`. Summary end: running → `overviewStatus.projectedEnd`; finished → `comparison.totals.actualEnd` (nil if nothing was recorded).

- [ ] **Step 1: Failing tests** (`EngineSource` with plan W50 S10 W50 S10 W50 from 09:00 unless noted):

| Test | Scenario | Expected |
|------|----------|----------|
| stage 1 day layout | the stage 1 day: first idle with the plan loaded, then started | idle: `.noDay` (an idle engine shows the planning form even if a plan is loaded); after `start`: `.running`, 15 planned blocks, long break `x ≈ 0.4792` and `width ≈ 0.09375`, axis 09:00–17:00 |
| now marker | running at 09:20 | `nowX == axis.x(for: 09:20)`; absent when `.noDay` and `.finished` |
| overshoot | work runs to 09:52 (no auto-advance, tick, advance at 09:52) | actual work block 09:00–09:52 is 2 minutes longer than planned; axis still covers all, widths positive |
| early start | started at 08:40 for a plan from 09:00 | axis starts 08:30 (step 1800, floor); actual block `x` > 0 but earlier than planned `x` |
| skipped segment | skip at 09:20 | actual blocks 09:00–09:20 work then the next segment's rest; row status `.skipped` |
| untracked pause | pause as untracked 09:30–09:35 | an `.untracked` actual block 09:30–09:35 between work blocks |
| lag thresholds | lag +59 s, +60 s, −59 s, −60 s, 0 | `.onSchedule`, `.behind(60)`, `.onSchedule`, `.ahead(60)`, `.onSchedule` |
| summary and table | the 2a review scenario (pauses untracked: start 09:00; pause 09:30–09:35; advance 09:57; break advance 10:09; skip 10:40; finished) | focus 100/83 min, rest 10/12, untracked 5, planned end 10:50, `endsAt` 10:40, `endIsFinal`; rows: deltas +7, +2, −19; statuses completed, completed, skipped |
| running summary | running at 09:30 | `endsAt` is the projected end, `endIsFinal == false` |
| Review Focus 4: nothing recorded | day ended from idle with a plan (`endDay` before `start`) | `.finished`, `summary.endsAt == nil`, `actual` empty, axis from the plan only, no crash |
| no day | empty source | `.noDay`, every output empty or `nil`, no crash |
| refresh follows the clock | running; clock 09:10 → 09:40, `refresh()` | `nowX` moves; calling `refresh()` twice at one instant changes nothing |
| Review Focus 1 | a source with a zero-length block and a block after the plan | all `x` in 0…1, widths ≥ 0 |
| mode transitions (Review Focus 2) | running → `endDay` → `refresh()` → `.finished`; a new day → `.running` | modes as expected, outputs replaced |

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement the model; make `SessionController` conform (`hasDay = !plan.isEmpty`, `overviewNow = clock.now`). **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Add the day overview model`.

### Task 4: Overview texts

**Files:**
- Create: `App/Overview/OverviewText.swift`, `AppTests/OverviewTextTests.swift`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces — Produces:**
```swift
enum OverviewText {
    static func lag(_ state: LagState, locale: Locale, bundle: Bundle = .main) -> String
        // "On schedule" / "3 min behind schedule" / "2 min ahead of schedule"
    static func delta(_ seconds: TimeInterval, locale: Locale) -> String       // "+2 min", "−19 min" (U+2212), "0 min"
    static func status(_ status: SegmentStatus, bundle: Bundle = .main) -> String
    static func plannedBlockLabel(_ block: BlockLayout<SegmentKind>, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String
        // "Plan: Work, from 9:00 to 9:50"
    static func actualBlockLabel(_ block: BlockLayout<ActualKind>, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String
        // "Actual: Paused (not counted), from 9:30 to 9:35"
    static func tooltip(kindName: String, start: Date, end: Date, locale: Locale, timeZone: TimeZone) -> String
        // "9:00–9:50 · Work · 50 min"
}
```
Catalog keys (en / uk): `overview.plan` "Plan" / "План"; `overview.actual` "Actual" / "Факт"; `overview.now` "Now" / "Зараз"; `lag.onSchedule` "On schedule" / "Вчасно"; `lag.behind` "%@ behind schedule" / "Відстаєш на %@"; `lag.ahead` "%@ ahead of schedule" / "Випереджаєш на %@"; `overview.kind.rest` "Rest" / "Відпочинок"; `summary.untracked` "Paused (not counted)" / "Паузи без обліку"; `summary.plannedEnd` "Planned end" / "Завершення за планом"; `summary.projectedEnd` "Projected end" / "Прогноз завершення"; `summary.finishedAt` "Finished at" / "Завершено о"; `table.start` "Start" / "Початок"; `table.segment` "Segment" / "Сегмент"; `table.plan` "Plan" / "План"; `table.actual` "Actual" / "Факт"; `table.delta` "Difference" / "Різниця"; `table.status` "Status" / "Статус"; `status.active` "Running" / "Триває"; `status.completed` "Done" / "Завершено"; `status.skipped` "Skipped" / "Пропущено"; `status.notStarted` "Planned" / "Заплановано"; `behaviour.title` "Behaviour" / "Поведінка"; `behaviour.pausesAsRest` "Count pauses as rest" / "Рахувати паузу як відпочинок"; `behaviour.autoBreak` "Start the break automatically when work ends" / "Автоматично починати перерву після роботи"; `behaviour.autoWork` "Start work automatically when a break ends" / "Автоматично починати роботу після перерви"; `behaviour.note` "Changes apply from the next transition." / "Зміни діють з наступного переходу."; `overview.newDay` "New day" / "Новий день"; `ui.overview` "Day overview…" / "Огляд дня…"; `ui.summary` "Day summary…" / "Підсумок дня…"; `a11y.block` "%@: %@, from %@ to %@" / "%@: %@, з %@ до %@"; `overview.noValue` "—" / "—" (added to the catalog test's "same in both languages" list). Existing keys reused: `setup.work`, `setup.shortBreak`, `setup.longBreak`, `summary.focus`, `summary.rest`, `ui.endDay`.

- [ ] **Step 1: Failing tests:** `lag` for each state in en and uk (`behind(180)` contains the duration "3 min" / "3 хв"; `onSchedule` differs between languages; none is a raw key); `delta` table — 120 → "+2 min", −1140 → "−19 min", 0 → "0 min", 59 → "0 min", uk "+2 хв"; `status` for every case in both languages, distinct from each other; block labels for a work, a break, a long break, a rest and an untracked block in `en` and `uk` containing both times (locale `en_GB`/`uk`, UTC and +03:00); `tooltip` format; catalog completeness (existing test).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement and add the keys. **Step 4:** Run → PASS. **Step 5:** Commit `Add the overview texts`.

### Task 5: The day screen views

**Files:**
- Create: `App/Views/TimelineRowsView.swift`, `SegmentTableView.swift`, `DaySummaryView.swift`, `BehaviourSection.swift`, `DayScreenView.swift`

**Interfaces — Consumes:** Tasks 1–4. **Produces:**
- `TimelineRowsView(model: DayOverviewModel)`: two rows ("Plan" above "Actual") of rectangles placed from `BlockLayout` fractions in a `GeometryReader`; drawn width is `max(width · available, 2)` (R6); work blocks full height, breaks 60 % height centred, the long break with an accent fill, untracked blocks grey with a hatch overlay; hour labels under the rows from `axis.ticks` (`SetupText.time`); a vertical "now" line with a small "Now" label at `nowX`; a legend (work, break, long break, paused); each block has `.help(tooltip)` and an accessibility label from `OverviewText`; the whole rows element is labelled "Plan" / "Actual".
- `DaySummaryView`: focus, rest, paused, planned end and the projected or final end as labelled values, "—" (`overview.noValue`) where there is none.
- `SegmentTableView`: a `Grid` with the table columns, delta coloured (positive orange, negative green, zero secondary) and signed through `OverviewText.delta`, status through `OverviewText.status`; the active row emphasised.
- `BehaviourSection`: a `DisclosureGroup("behaviour.title")` with three `Toggle`s bound through `Binding`s that read `settings.session` and call `controller.updateSessionSettings(_:)` with the changed copy (R9), and the `behaviour.note` caption.
- `DayScreenView(model:controller:settings:onNewDay:)`: header (phase label, lag chip from `OverviewText.lag` coloured by state, planned end, projected or final end), `TimelineRowsView`, `DaySummaryView`, `SegmentTableView`, `BehaviourSection`; an "End day" button while running (calls `controller.endDay()`), a "New day" button when finished (calls `onNewDay`). It wraps its content in `TimelineView(.periodic(from: .now, by: 5))` that calls `model.refresh()` on each date change and on appear (spec C5, Review Focus 5).

- [ ] **Step 1:** There are no unit tests for the views (they only display the model). Write the views.
- [ ] **Step 2:** `timeout 115 scripts/test-app.sh` → PASS; build without warnings.
- [ ] **Step 3 (visual check, R8):** a throwaway test (not committed) renders `TimelineRowsView`, `SegmentTableView` and `DaySummaryView` with `ImageRenderer` for the stage 1 day mid-afternoon (`en` and `uk`) and for the 2a review scenario; read the PNGs from the app container's temp directory and check by eye: block positions, heights, hatching, the now line, labels, delta colours. Fix what looks wrong. Delete the test and the images.
- [ ] **Step 4:** Commit `Add the day screen views`.

### Task 6: One window and the popover entry

**Files:**
- Create: `App/Views/RipelineWindowView.swift`
- Modify: `App/Views/DaySetupView.swift`, `App/RipelineApp.swift`, `App/AppEnvironment.swift`, `App/Presentation/PopoverActions.swift`, `App/Views/PopoverView.swift`, `App/Resources/Localizable.xcstrings`, `AppTests/PopoverActionsTests.swift`, `AppTests/AppEnvironmentTests.swift`

**Interfaces — Produces:**
```swift
enum MainWindow { static let id = "ripeline" }          // replaces DaySetupWindow

struct RipelineWindowView: View {
    // .noDay → DaySetupView (with the Behaviour section); .running → DayScreenView;
    // .finished → DayScreenView, until the user presses "New day" (local state), then DaySetupView.
}

enum PopoverAction { case planDay, overview, summary, pause, resume, extend, skip, next, endDay
    var sessionAction: SessionAction? { get }            // nil: always shown (R2)
}
```
`AppEnvironment` gains `let overviewModel: DayOverviewModel` (built over the controller in both the live and the inert environment). `RipelineApp` declares `Window("app.name", id: MainWindow.id)` containing `RipelineWindowView`, `.defaultSize(width: 760, height: 700)`, `.windowResizability(.contentMinSize)` with a minimum of 720×620; the 2b scene is removed. `DaySetupView` drops the fixed 600×640 frame, shows the `BehaviourSection` below its form, and uses `MainWindow.id` for `dismissWindow`; after a successful start the window stays open and switches to the day screen (no dismiss). `PopoverActions.visible`: idle → `[.planDay]`; working, on break, paused, overtime → the existing buttons plus `.overview` last; finished → `[.summary]`. The popover view draws `.overview` as a link-style button under the glass row and `.summary` as the prominent glass button, and opens the window with `openWindow(id: MainWindow.id)` then `NSApplication.shared.activate()`. The catalog key `window.setup.title` is removed.

- [ ] **Step 1: Failing tests:** `PopoverActionsTests` — idle `[.planDay]`; finished `[.summary]`; each running phase ends with `.overview`; `.overview` and `.summary` are shown whatever the engine allows; the other buttons still follow `isAllowed`; `sessionAction` is `nil` for the two new actions and unchanged for the rest. `AppEnvironmentTests` — the inert environment has an `overviewModel`; driving it through a day leaves the real directory alone (extend the existing real-directory test).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run the full suite → PASS; clean build, no warnings. Launch the app and confirm it stays alive.
- [ ] **Step 5:** Commit `Use one window for planning and the day`.

### Task 7: End to end, documentation and verification

**Files:**
- Create: `AppTests/OverviewRelaunchTests.swift`
- Modify: `README.md`, `docs/specs/2026-10-01-stage-2c-day-screen-design.md` (status, decisions R1–R9), `SPEC.md` (stage table: 2c done)

- [ ] **Step 1: End-to-end test** over a real `FileDayStore` in a temporary directory, as `SetupRelaunchTests`: plan a day through the setup model, run several transitions (pause with pauses as untracked, an overtime, an advance, a skip), build a `DayOverviewModel` over a **new** controller after a relaunch, and assert the model's planned and actual rows, summary and table equal those of the first controller; change a session setting through `updateSessionSettings`, relaunch, and assert it persisted and applies to the next transition.
- [ ] **Step 2:** Update the docs.
- [ ] **Step 3:** Run everything and read the output: `swift test --package-path Packages/RipelineCore`, `scripts/test-app.sh`, a clean-clone `scripts/test-app.sh` (no `Local.xcconfig`), a warning-free `xcodebuild clean build`.
- [ ] **Step 4:** Launch the app; record what could and could not be checked from the command line.
- [ ] **Step 5:** Write the **manual checklist** for the PR: the popover shows "Day overview…" while a day runs and "Day summary…" when it ended; the window opens in front and shows the planning form with no day; after starting, the same window shows the timelines, the "now" line moving, the lag chip, the summary and the table; pausing, skipping and overtime show up in the Actual row within a few seconds; ending the day shows the final comparison and "New day" returns to the form; the three Behaviour switches work before a day and during one and take effect at the next transition; the window is resizable and readable at the minimum size; English and Ukrainian; VoiceOver reads a block as "Plan: Work, from 9:00 to 9:50".
- [ ] **Step 6:** Commit `Document stage 2c`.

---

## Spec coverage check

| Spec section | Task |
|---|---|
| §1 criterion 1 (rows, marker, lag, summary, table, within 5 s) | 3, 5, 6 |
| §1 criterion 2 (final comparison, "New day") | 3, 5, 6 |
| §1 criterion 3 (settings before and during a day) | 1, 5, 6 |
| §1 criterion 4 (numbers are the core's) | 1, 3 |
| §1 criterion 5 (strings, entitlements) | 4, 6 |
| §3.1 controller | 1 |
| §3.2 model, axis, rows, now, lag, summary, table | 2, 3 |
| §4 window, day screen, drawing, popover, localization | 4, 5, 6 |
| §5 testing and verification | every task; 7 |
