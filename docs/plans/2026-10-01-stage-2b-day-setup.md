# Stage 2b — Day Setup Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user define the day in a separate window (preset, mode, end time or focus, long break, remainder strategy), see the exact generated plan before committing, and start it from "now"; replace 2a's temporary quick-start.

**Architecture:** A pure `DaySetup.evaluate(form:now:calendar:)` turns a `DayPlanForm` into a `DayPlanRequest`, runs `PlanGenerator`, and returns a preview with issues and notices. A `@MainActor @Observable DaySetupModel` holds the form (persisted in `AppSettings`), recomputes the preview, and starts the day by re-evaluating at click time and calling `SessionController.startDay(request:)`. The popover offers "Plan day…", which opens a single-instance `Window` scene with the form and the preview. Views only display the model.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (`Window`, `openWindow`, `Form`, `DatePicker`), Observation, Swift Testing, `RipelineCore` (unchanged), `xcodebuild`.

**Spec:** [`docs/specs/2026-10-01-stage-2b-day-setup-design.md`](../specs/2026-10-01-stage-2b-day-setup-design.md). Parents: [`SPEC.md`](../../SPEC.md), [stage 2a spec](../specs/2026-10-01-stage-2a-app-shell-design.md).

## Global Constraints

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, zero warnings from our code.
- `MACOSX_DEPLOYMENT_TARGET = 26.0`; only APIs available on macOS 26.
- Public APIs only; App Sandbox; **entitlements stay exactly `com.apple.security.app-sandbox`**; no network; no data collected.
- No personal data in the repo; a fresh clone must build and test without `Config/Local.xcconfig`.
- All code, comments and docs in English. Every user-facing string comes from `Localizable.xcstrings` with `en` (base) and `uk`; the catalog completeness test must stay green. No counts are shown (no plural variations).
- `RipelineCore` is not modified by this plan.
- Commit identity is configured; **no Claude attribution** in commits or PR text.
- Tests: Swift Testing. No real sleeping, no real `Application Support`, no real notification center in unit tests (the inert environment stays).
- Commands: `scripts/test-app.sh [SuiteName]` (app), `swift test --package-path Packages/RipelineCore` (core).

## Decisions where the spec is silent or this plan refines it (please confirm)

| # | Decision | Why |
|---|----------|-----|
| Q1 | `DaySetupIssue` gets a defensive third case `invalidInput` (the generator threw). It cannot happen after normalization. Spec §3.2 is amended in Task 2. | A thrown `PlanError` must not crash or look like "day too short". |
| Q2 | `SessionController.startQuickDay` stays as a thin wrapper over `startDay(request:)` until Task 5 removes it. | Keeps every task compiling and green; the popover moves to "Plan day…" in Task 5. |
| Q3 | Out-of-range stored form values are clamped, not rounded to the stepper step (focus 100 stays 100). | Never alter a value the user could have entered. |
| Q4 | `TimeOfDay.date(on:calendar:)` uses `matchingPolicy: .nextTime`, so a time that does not exist on a DST day (02:30 on spring-forward) becomes the next valid instant. | Deterministic, no crash. |
| Q5 | `DaySetupModel.startDay()` ignores a second call while one is in flight. | The first start awaits notification authorization; a double click must not start two days. |
| Q6 | While a day is running the window shows the message and an "End day" button (calls `controller.endDay()`), not the form. | Spec §4. |
| Q7 | Durations are formatted with the locale-aware `Duration.UnitsFormatStyle` (`6 h 15 min` / `6 год 15 хв`); clock times with the system locale's short time style. | Correct per language without our own tables. |
| Q8 | The preview refreshes through `TimelineView(.periodic(from: .now, by: 30))` calling `model.refresh()`; tests call `refresh()` directly. | No timers in the model; `now` comes from the injected clock. |
| Q9 | `startDay()` returns whether a day was started; the view dismisses the window only on `true`. | A refused start (invalid, running, stale) keeps the window open with the reason. |

## Review Focus

1. **Time-of-day edges.** End 00:00, end 23:59, now 23:58, end equal to now, a DST gap (02:30 on spring-forward) and a repeated hour: no crash, a sensible issue or plan. *Tests in Tasks 1 and 2.*
2. **Preview vs click.** The preview is ready but at the click the end time has passed (or the minute rolled): nothing starts, the model's result becomes the issue, and the request that starts is the one evaluated at click time. *Tests in Task 4.*
3. **Starting while a day runs, and double clicks.** The window opened before a day started; or two quick clicks: no second day, at most one `start` call, one authorization. *Tests in Tasks 3 and 4.*
4. **Garbage in storage.** Undecodable form data, a case removed in a later version, out-of-range numbers, `afterBlock(0)`: the form falls back to defaults or is clamped, never crashes, never writes invalid data back. *Tests in Task 1.*
5. **Window lifecycle.** The window opened twice, closed while a start is in flight, or opened by the popover for an app without a Dock icon: one window, the model survives, the start completes once. *Verified by the single-instance scene, the model tests, and the PR checklist (Task 7).*

---

## File Structure

```
App/
  Setup/
    TimeOfDay.swift            TimeOfDay
    DayPlanForm.swift          BuiltInPreset, PresetChoice, DayModeChoice, LongBreakChoice,
                               RemainderChoice, DayPlanForm (+ normalized(), .standard)
    DaySetup.swift             DaySetupIssue, DaySetupNotice, DayPreview, DaySetupResult, DaySetup.evaluate
    DaySetupModel.swift        the observable model
    SetupText.swift            localized texts for issues, notices, durations, rows
  Views/
    DaySetupView.swift         the window content (form + preview + bottom bar)
    PlanPreviewView.swift      summary and segment list
  Settings/AppSettings.swift   (modified) dayPlanForm
  Runtime/SessionController.swift   (modified) startDay(request:)
  Presentation/PopoverActions.swift (modified) planDay replaces startDay
  Views/PopoverView.swift      (modified) opens the window
  AppEnvironment.swift         (modified) builds the model
  RipelineApp.swift            (modified) Window scene
  Resources/Localizable.xcstrings   (modified) new keys
AppTests/
  TimeOfDayTests.swift, DayPlanFormTests.swift, DaySetupTests.swift, DaySetupModelTests.swift,
  SetupTextTests.swift, SessionControllerStartDayTests.swift, SetupRelaunchTests.swift
  Support/Fixtures.swift       (modified) standardRequest(at:), Harness.startStandardDay()
```

---

### Task 1: Form types and persistence

**Files:**
- Create: `App/Setup/TimeOfDay.swift`, `App/Setup/DayPlanForm.swift`, `AppTests/TimeOfDayTests.swift`, `AppTests/DayPlanFormTests.swift`
- Modify: `App/Settings/AppSettings.swift`, `AppTests/AppSettingsTests.swift`

**Interfaces — Produces:**
```swift
struct TimeOfDay: Codable, Equatable, Hashable, Sendable {
    let hour: Int, minute: Int                      // init clamps to 0...23 and 0...59
    init(hour: Int, minute: Int)
    init(date: Date, calendar: Calendar)            // the date's wall-clock time in the calendar
    func date(on day: Date, calendar: Calendar) -> Date   // that wall-clock time on `day`, .nextTime on DST gaps
}

enum BuiltInPreset: String, Codable, CaseIterable, Sendable {
    case classic, deepWork, longBlocks
    var preset: Preset { get }                      // 25/5/15, 50/10/45, 90/15/30
}
enum PresetChoice: Codable, Equatable, Sendable { case builtIn(BuiltInPreset), custom }
enum DayModeChoice: String, Codable, CaseIterable, Sendable { case untilTime, netFocus }
enum LongBreakChoice: Codable, Equatable, Sendable { case none, atTime(TimeOfDay), afterBlock(Int) }
enum RemainderChoice: String, Codable, CaseIterable, Sendable { case shortBlock, leaveFree, stretchBlocks }

struct DayPlanForm: Codable, Equatable, Sendable {
    var presetChoice: PresetChoice          // .builtIn(.deepWork)
    var customPreset: Preset                // 50/10/45
    var mode: DayModeChoice                 // .untilTime
    var endTime: TimeOfDay                  // 17:00
    var focusMinutes: Int                   // 240
    var longBreak: LongBreakChoice          // .none
    var remainder: RemainderChoice          // .shortBlock
    var minBlockMinutes: Int                // 15
    static let standard: DayPlanForm
    var preset: Preset { get }              // the chosen preset (built-in or custom)
    func normalized() -> DayPlanForm        // clamps every number into its range
}
```
Ranges: custom work 1–240, short break 1–120, long break 1–120; focus 15–720; `afterBlock` 1–20; `minBlockMinutes` 1–120.
`AppSettings` gains `var dayPlanForm: DayPlanForm` stored under key `dayPlanForm` as JSON; reading returns the normalized form, or `.standard` when absent or undecodable; writing stores the normalized form.

- [ ] **Step 1: Failing tests.**
  - `TimeOfDayTests`: init clamps (25:99 → 23:59, -1:-5 → 0:00); `date(on:calendar:)` for UTC and a +03:00 calendar on the same day (17:00 → the right instant); `init(date:calendar:)` is the inverse for both; **DST** (calendar `America/New_York`, day 2026-03-08): 02:30 does not exist → result is 03:00 local (`.nextTime`); day 2026-11-01: 01:30 exists twice → a valid instant, no crash; midnight 00:00 and 23:59 round-trip; Codable round trip.
  - `DayPlanFormTests`: `.standard` values; built-in presets are 25/5/15, 50/10/45, 90/15/30; `preset` returns the built-in or the custom one; `normalized()` table — custom work 0→1, 999→240; short 500→120; long 0→1; focus 7→15, 1000→720, 100→100; `afterBlock(0)`→1, `afterBlock(99)`→20; `minBlockMinutes` 0→1, 500→120; an already valid form is unchanged; Codable round trip over every case of every enum (parameterized); decoding JSON with an unknown preset case throws.
  - `AppSettingsTests` additions: default `dayPlanForm == .standard`; a changed form survives a new `AppSettings` on the same suite; out-of-range stored numbers come back clamped; undecodable data and an unknown enum case give `.standard`; writing an out-of-range form stores the clamped one.
- [ ] **Step 2:** Run `scripts/test-app.sh` → fails to compile.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS (full suite).
- [ ] **Step 5:** Commit `Add day plan form types and persistence`.

### Task 2: DaySetup.evaluate

**Files:**
- Create: `App/Setup/DaySetup.swift`, `AppTests/DaySetupTests.swift`
- Modify: `docs/specs/2026-10-01-stage-2b-day-setup-design.md` (§3.2: add `invalidInput`)

**Interfaces — Consumes:** Task 1. **Produces:**
```swift
enum DaySetupIssue: Equatable, Sendable { case endNotAfterNow, dayTooShort, invalidInput }
enum DaySetupNotice: Equatable, Sendable { case longBreakNotPlaced, remainderLeftFree(minutes: Int) }

struct DayPreview: Equatable, Sendable {
    let segments: [PlannedSegment]
    let focus: TimeInterval, rest: TimeInterval     // seconds of work and of breaks
    let endsAt: Date                                // end of the last segment
    let freeRemainder: TimeInterval                 // requested end minus endsAt; 0 in net-focus mode
}

enum DaySetupResult: Equatable, Sendable {
    case ready(request: DayPlanRequest, preview: DayPreview, notices: [DaySetupNotice])
    case invalid(DaySetupIssue)
}

enum DaySetup {
    static func evaluate(form: DayPlanForm, now: Date, calendar: Calendar) -> DaySetupResult
}
```
Rules: normalize the form first. Start = `now`. `endTime`, `.atTime` are converted with `TimeOfDay.date(on: now, calendar:)`. `.untilTime` with end ≤ now → `.invalid(.endNotAfterNow)`. Mapping: `.afterBlock(n)` → `.afterWorkBlock(n)`; `.shortBlock` → `.shortBlock(minMinutes: minBlockMinutes)`; `.netFocus` → `.netFocus(start: now, focusMinutes:)`. Generator throws → `.invalid(.invalidInput)`; empty plan → `.invalid(.dayTooShort)`. Notices: `longBreakNotPlaced` if a long break was requested and the plan has no long-break segment; `remainderLeftFree(minutes: Int(freeRemainder / 60))` when that is ≥ 1.

- [ ] **Step 1: Failing tests** (UTC, day 2026-01-15, deep work 50/10/45 unless noted):

| Test | Input | Expected |
|------|-------|----------|
| the stage-1 day | now 09:00, until 17:00, long break at 13:00, short block 15 | `.ready`; long break 12:50–13:35; focus 375 min; rest 105 min; endsAt 17:00; free 0; no notices |
| leave free | now 09:00, until 17:00, none, leaveFree | 8 work blocks, endsAt 16:50, free 10 min, notice `remainderLeftFree(10)` |
| stretch | now 09:00, until 17:30, none, stretch | endsAt 17:30, free 0, no notice |
| net focus | now 09:00, 120 min, preset 50/10 | segments 50,10,50,10,20; focus 120 min; endsAt 11:20; free 0; remainder choice has no effect (same result for all three) |
| net focus keeps a stored end time | net-focus mode with `endTime` 08:00 (earlier than now) | `.ready` (end time ignored) |
| end not after now | now 17:00 and 17:30, until 17:00 | `.invalid(.endNotAfterNow)` |
| day too short | now 16:30, until 17:00, leaveFree | `.invalid(.dayTooShort)` |
| short block rescues a short day | now 16:30, until 17:00, short block 15 | `.ready`, one 30-minute work block |
| long break dropped | now 09:00, until 11:00, long break at 10:00, leaveFree | `.ready`, no long break segment, notices contain `longBreakNotPlaced` and `remainderLeftFree(10)` |
| long break after block | afterBlock(2) | long break right after the 2nd work block |
| custom preset | 25/5/15 custom | blocks of 25 |
| clamped input | form with custom work 0 and afterBlock 99 | evaluates as work 1 / afterBlock 20 (no throw, no `.invalidInput`) |
| time zones | calendar +03:00, now = 22:30 UTC on the 14th (01:30 on the 15th local), until 17:00 | request end is 14:00 UTC on the 15th |
| midnight edges | now 23:58, until 23:59 | `.ready` with the generator's result (or `.dayTooShort`); end 00:00 with now 23:58 → `.invalid(.endNotAfterNow)` |
| DST | calendar New York, now 2026-03-08 01:00 local, until 02:30 (does not exist) | end resolves to 03:00 local; no crash |

- [ ] **Step 2:** Run `scripts/test-app.sh DaySetupTests` → fails to compile. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Amend the spec §3.2; commit `Add day setup evaluation`.

### Task 3: SessionController.startDay(request:)

**Files:**
- Modify: `App/Runtime/SessionController.swift`, `AppTests/Support/Fixtures.swift`, `AppTests/Support/ControllerHarness.swift`, `AppTests/SessionControllerActionTests.swift`, `AppTests/SessionControllerBookkeepingTests.swift`, `AppTests/RelaunchIntegrationTests.swift`, `AppTests/AppEnvironmentTests.swift`
- Create: `AppTests/SessionControllerStartDayTests.swift`

**Interfaces — Produces:**
```swift
extension SessionController {
    /// Starts a day from `request`: awaits authorization once, generates the plan, starts it, saves once.
    /// Does nothing when `startDay` is not allowed. Returns whether a day was started.
    @discardableResult func startDay(request: DayPlanRequest) async -> Bool
}
```
`startQuickDay()` becomes a wrapper building the 2a default request and calling `startDay(request:)` (removed in Task 5).
Test helper: `func standardRequest(at now: Date) -> DayPlanRequest` (net focus 240, 50/10/45, no long break, leave free — exactly the 2a quick-start) and `Harness.startStandardDay() async` calling `controller.startDay(request: standardRequest(at: clock.now))`. Every existing `startQuickDay()` call in the tests is replaced by `startStandardDay()`.

- [ ] **Step 1: Failing tests** (`SessionControllerStartDayTests`): a custom request (25/5/15, net focus 100 from now) produces exactly the generated plan, `phase == .working`, first segment ends 25 minutes after the clock, one save, one authorization, returns `true`; the plan equals `PlanGenerator.generate` of the same request; not allowed while a day runs → returns `false`, no extra save, no extra authorization (Review Focus 3); allowed again after `endDay`; a request the generator rejects (preset 0) → returns `false`, still idle, no crash, nothing saved; the day starts at the controller's clock, not at the request's start (request built for 08:00 while the clock says 09:00 still starts the first segment at 09:00).
- [ ] **Step 2:** Run `scripts/test-app.sh SessionControllerStartDayTests` → FAIL.
- [ ] **Step 3:** Implement `startDay(request:)` by extracting the body of `startQuickDay`; make `startQuickDay` a wrapper. Migrate the existing tests to the helper.
- [ ] **Step 4:** Run the full suite → PASS; the migrated tests keep their expectations unchanged.
- [ ] **Step 5:** Commit `Start a day from a plan request`.

### Task 4: DaySetupModel

**Files:**
- Create: `App/Setup/DaySetupModel.swift`, `AppTests/DaySetupModelTests.swift`

**Interfaces — Consumes:** Tasks 1–3. **Produces:**
```swift
@MainActor @Observable final class DaySetupModel {
    init(settings: AppSettings, clock: any WallClock, calendar: Calendar = .current,
         canStart: @escaping @MainActor () -> Bool,
         start: @escaping @MainActor (DayPlanRequest) async -> Bool)

    var form: DayPlanForm { get set }            // every change is saved (normalized) to AppSettings
    private(set) var now: Date
    var result: DaySetupResult { get }           // DaySetup.evaluate(form, now, calendar)
    var isDayRunning: Bool { get }               // !canStart()
    var canStartNow: Bool { get }                // result is .ready and canStart()
    func refresh()                               // now = clock.now
    @discardableResult func startDay() async -> Bool
}
```
`startDay()`: ignores a second call while one is in flight (Q5); sets `now` to the clock, re-evaluates; only if `.ready` and `canStart()` calls `start(request)` with **that** request and returns its result; otherwise returns `false` and leaves the new `result` visible.

- [ ] **Step 1: Failing tests** (`TestClock`, a `SpyStart` recording requests, a `canStart` flag, `AppSettings` over a throwaway suite):
  - the form is loaded from settings; changing it saves a normalized copy and a new model restores it; undecodable stored data gives `.standard`.
  - `result` changes when the form changes and when `refresh()` moves the clock past the end time.
  - the preview equals `DaySetup.evaluate` for the same inputs (stage-1 day: long break 12:50–13:35, 375 min).
  - `startDay()` with a ready form calls `start` exactly once with the request evaluated **at click time** (clock moved one minute since the last refresh: the request's start is the new time).
  - Review Focus 2: preview ready at 16:59:30 for an end of 17:00; clock moves to 17:00:30; `startDay()` returns `false`, `start` not called, `result == .invalid(.endNotAfterNow)`.
  - Review Focus 3: `canStart` false → `canStartNow` false, `isDayRunning` true, `startDay()` returns `false`; two `startDay()` calls in flight (the `start` closure suspended on a continuation) → `start` called once, the second returns `false`; after the first completes a later call works again.
  - a `start` that returns `false` is reported as `false` and the model stays usable.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS (full suite). **Step 5:** Commit `Add day setup model`.

### Task 5: Popover entry point and wiring

**Files:**
- Modify: `App/Presentation/PopoverActions.swift`, `App/Views/PopoverView.swift`, `App/AppEnvironment.swift`, `App/RipelineApp.swift`, `App/Runtime/SessionController.swift` (remove `startQuickDay` and the quick-start constants), `App/Resources/Localizable.xcstrings`, `AppTests/PopoverActionsTests.swift`, `AppTests/AppEnvironmentTests.swift`
- Create: `App/Views/DaySetupView.swift` (placeholder, completed in Task 6)

**Interfaces — Produces:** `PopoverAction.planDay` replaces `.startDay` (title key `ui.planDay`, still tied to `SessionAction.startDay`). `AppEnvironment` gains `let setupModel: DaySetupModel` (built in both the live and the inert environment, wired to `controller.isAllowed(.startDay)` and `controller.startDay(request:)`). `RipelineApp` adds `Window("window.setup.title", id: "day-setup") { DaySetupView(...) }.defaultSize(width: 600, height: 640).windowResizability(.contentSize)`. The popover's "Plan day…" calls `openWindow(id: "day-setup")` then `NSApplication.shared.activate()`.
Catalog keys (en / uk): `ui.planDay` "Plan day…" / "Спланувати день…"; `window.setup.title` "Plan your day" / "План дня".

- [ ] **Step 1: Failing tests:** `PopoverActionsTests` — idle and finished give `[.planDay]` (was `[.startDay]`); hidden when `startDay` is not allowed; the other phases are unchanged. `AppEnvironmentTests` — the inert environment has a `setupModel` whose `startDay()` never touches the real directory (extend the existing real-directory test to start through the model).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement; remove `startQuickDay` and migrate nothing else (tests already use `startDay(request:)`). The placeholder window view shows the title and the model's `result` description.
- [ ] **Step 4:** Run the full suite → PASS. Build and launch the app; confirm it stays alive.
- [ ] **Step 5:** Commit `Open the day setup window from the popover`.

### Task 6: The day setup window

**Files:**
- Create: `App/Setup/SetupText.swift`, `App/Views/PlanPreviewView.swift`, `AppTests/SetupTextTests.swift`
- Modify: `App/Views/DaySetupView.swift`, `App/Resources/Localizable.xcstrings`

**Interfaces — Produces:**
```swift
enum SetupText {
    static func message(for issue: DaySetupIssue, bundle: Bundle = .main) -> String
    static func message(for notice: DaySetupNotice, locale: Locale, bundle: Bundle = .main) -> String
    static func duration(_ seconds: TimeInterval, locale: Locale) -> String                       // "6 h 15 min"
    static func time(_ date: Date, locale: Locale, timeZone: TimeZone) -> String                    // "09:00"
    static func segmentLabel(_ segment: PlannedSegment, locale: Locale, timeZone: TimeZone, bundle: Bundle = .main) -> String
        // accessibility text, e.g. "Work, from 09:00 to 09:50"
}
```
`DaySetupView` layout (spec §4): left `Form` — preset `Picker` (the three built-ins and "Custom"; for Custom three `Stepper`s), mode segmented `Picker`, `DatePicker(.hourAndMinute)` for the end time or a `Stepper` (step 15) for focus, long break `Picker` (none / at time / after block no.) with its field, remainder `Picker` with the minimum-block `Stepper` (disabled in net-focus mode); right `PlanPreviewView` — summary rows (focus, rest, ends at, free remainder), issue and notice messages, a scrollable segment list (kind symbol, time range, long break highlighted; each row `accessibilityElement(children: .combine)` with `segmentLabel`); a bottom bar with a prominent "Start day" (disabled with the issue text as its accessibility hint) and "Close". When `model.isDayRunning` the window shows `setup.dayRunning` and an "End day" button instead of the form. The view wraps its content in `TimelineView(.periodic(from: .now, by: 30))` that calls `model.refresh()`, calls `refresh()` on appear, and dismisses the window (`dismissWindow(id:)`) when `startDay()` returns `true`. `DatePicker` is bound to the form through `TimeOfDay` conversions.
Catalog keys (en / uk): `setup.preset` "Preset" / "Пресет"; `preset.classic` "Classic 25/5/15" / "Класичний 25/5/15"; `preset.deepWork` "Deep work 50/10/45" / "Глибока робота 50/10/45"; `preset.longBlocks` "Long blocks 90/15/30" / "Довгі блоки 90/15/30"; `preset.custom` "Custom" / "Свій"; `setup.work` "Work" / "Робота"; `setup.shortBreak` "Short break" / "Коротка перерва"; `setup.longBreak` "Long break" / "Довга перерва"; `setup.mode` "Day" / "День"; `mode.untilTime` "Until time" / "До часу"; `mode.netFocus` "Net focus" / "Чистий фокус"; `setup.endTime` "Day ends at" / "День закінчується о"; `setup.focus` "Focus time" / "Час фокусу"; `longBreak.none` "None" / "Немає"; `longBreak.atTime` "At a time" / "На час"; `longBreak.afterBlock` "After block no." / "Після блоку №"; `setup.remainder` "Leftover time" / "Залишок часу"; `remainder.shortBlock` "Short block" / "Короткий блок"; `remainder.leaveFree` "Leave free" / "Лишити вільним"; `remainder.stretch` "Stretch blocks" / "Розтягнути блоки"; `setup.minBlock` "Smallest block" / "Найменший блок"; `setup.fromNow` "The plan starts now" / "План починається зараз"; `summary.focus` "Focus" / "Фокус"; `summary.rest` "Rest" / "Відпочинок"; `summary.ends` "Ends at" / "Завершення о"; `summary.free` "Left free" / "Лишається вільним"; `setup.close` "Close" / "Закрити"; `setup.dayRunning` "End the current day first." / "Спершу завершіть поточний день."; `setup.issue.endNotAfterNow` "The end time must be later than now." / "Час завершення має бути пізніше за поточний."; `setup.issue.dayTooShort` "The day is too short for a block with these settings." / "День закороткий для блоку з такими налаштуваннями."; `setup.issue.invalidInput` "These settings cannot make a plan." / "З цими налаштуваннями план неможливий."; `setup.notice.longBreakNotPlaced` "The long break does not fit and was left out." / "Довга перерва не вмістилась і пропущена."; `setup.notice.remainderLeftFree` "%@ at the end of the day are left free." / "%@ наприкінці дня лишаються вільними."; `a11y.segment` "%@, from %@ to %@" / "%@, з %@ до %@"; `a11y.startBlocked` "Start is unavailable" / "Старт недоступний". Existing `ui.startDay` and `ui.endDay` are reused.

- [ ] **Step 1: Failing tests (`SetupTextTests`):** `duration` for en and uk — 6 h 15 min, 45 min, 2 h exactly, 0 → "0 min" style, never a raw key; `time` for 09:00 in UTC and +03:00 and in `en_US` (12-hour) vs `uk` (24-hour); messages for each issue and notice exist in `en` and `uk` bundles, are not raw keys, and differ between languages; the free-remainder notice contains the formatted duration; `segmentLabel` for a work and a break segment in both languages contains the kind name and both times; catalog completeness (existing test) covers every new key.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement `SetupText`, the views and the catalog keys. **Step 4:** Run the full suite → PASS; build without warnings.
- [ ] **Step 5:** Launch the app and check it stays alive; render the window content once with a throwaway `ImageRenderer` test (not committed) to check text and localization, as in 2a; record that buttons and pickers cannot be rendered this way.
- [ ] **Step 6:** Commit `Add the day setup window`.

### Task 7: End to end, documentation and verification

**Files:**
- Create: `AppTests/SetupRelaunchTests.swift`
- Modify: `README.md`, `docs/specs/2026-10-01-stage-2b-day-setup-design.md` (status, decisions Q1–Q9), `SPEC.md` (stage table: 2b done)

- [ ] **Step 1: End-to-end test** over a real `FileDayStore` in a temporary directory, as `RelaunchIntegrationTests`: a model with a non-default form (custom 25/5/15, net focus 100 minutes, long break after block 2) starts a day; a new controller over the same files continues it; the plan's segments match `DaySetup.evaluate` for the form and the start time; the form survives a new `AppSettings` on the same suite.
- [ ] **Step 2:** Update the docs.
- [ ] **Step 3:** Run everything and read the output: `swift test --package-path Packages/RipelineCore`, `scripts/test-app.sh`, a clean-clone `scripts/test-app.sh` (no `Local.xcconfig`), a warning-free `xcodebuild clean build`.
- [ ] **Step 4:** Launch the app; record what could and could not be checked from the command line.
- [ ] **Step 5:** Write the **manual checklist** for the PR: the popover offers "Plan day…" and the window comes to the front (and is not behind other windows); every control works and the preview matches what runs after "Start day"; the end-time `DatePicker` and the steppers behave; the window layout in English and Ukrainian; "Start day" is disabled with a reason for an end time in the past; the window shows "End the current day first" while a day runs; the choices are remembered after relaunch; closing and reopening the window keeps the form.
- [ ] **Step 6:** Commit `Document stage 2b`.

---

## Spec coverage check

| Spec section | Task |
|---|---|
| §1 criteria 1–2 (all options, exact preview, start from now) | 1, 2, 3, 4 |
| §1 criterion 3 (remembered) | 1, 4, 7 |
| §1 criterion 4 (quick-start gone, "Plan day…") | 5 |
| §1 criterion 5 (window to the front) | 5, 7 (manual) |
| §1 criterion 6 (strings, entitlements) | 5, 6 |
| §3.1 form | 1 |
| §3.2 evaluation | 2 |
| §3.3 model | 4 |
| §3.4 controller | 3, 5 |
| §4 interface | 5, 6 |
| §5 testing and verification | every task; 7 |
