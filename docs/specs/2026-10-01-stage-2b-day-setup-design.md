# Stage 2b — Day setup screen: design

Status: implemented. Parent specs: [`SPEC.md`](../../SPEC.md), [stage 2a](2026-10-01-stage-2a-app-shell-design.md). Builds on `RipelineCore` (`DayPlanRequest`, `PlanGenerator`) and the 2a app shell.

## 1. Goal

Let the user define the day: choose a preset and describe the day, see the generated plan before committing, and start it. This replaces 2a's temporary "Start day" with a fixed default plan.

**Success criteria**

1. Every option of `DayPlanRequest` (mode, end time or focus, long break, remainder strategy, preset) can be set in the UI, and the preview is exactly what `PlanGenerator` returns for it.
2. "Start" creates the plan from the moment of the click, so plan and reality coincide from the first second.
3. The last choices are remembered across launches.
4. The 2a quick-start is gone; the popover offers "Plan day…" instead.
5. The window comes to the front when opened from the menu bar item of an app without a Dock icon.
6. All new text is in the String Catalog (`en`, `uk`); no new entitlement; no network.

## 2. Decisions

| # | Decision | Chosen by |
|---|---|---|
| D1 | UI paradigm: the popover stays the quick control panel; day setup (2b) and the day screen (2c) open in a separate window from the popover. | user |
| D2 | Presets: three built-in presets plus "Custom" (three values); the last choice is remembered. No user-managed preset library. | user |
| D3 | The day always starts "now": only the end of the day (or the focus amount) is entered; the plan is generated at the moment of the click. No planning ahead, no auto-start. | user |
| D4 | Logic lives in a testable `@MainActor @Observable DaySetupModel`; views only display it. | user |
| D5 | Built-in presets: Classic 25/5/15, Deep work 50/10/45 (default), Long blocks 90/15/30. | proposed |
| D6 | A day stays within one calendar day: an end time at or before now is an error, not "tomorrow". | proposed |
| D7 | The window is a single-instance `Window` scene; the form state lives in `AppEnvironment` and survives closing the window. | proposed |

## 3. Logic

### 3.1 Form

`DayPlanForm` (`Codable`, `Equatable`, `Sendable`), stored in `AppSettings` as JSON:

| Field | Type | Default |
|---|---|---|
| `presetChoice` | `.builtIn(BuiltInPreset)` or `.custom` | `.builtIn(.deepWork)` |
| `customPreset` | `Preset` (work 1–240, short break 1–120, long break 1–120 minutes) | 50 / 10 / 45 |
| `mode` | `.untilTime` or `.netFocus` | `.untilTime` |
| `endTime` | `TimeOfDay` (hour, minute) | 17:00 |
| `focusMinutes` | `Int`, step 15, 15–720 | 240 |
| `longBreak` | `.none`, `.atTime(TimeOfDay)`, `.afterBlock(Int)` (1–20) | `.none` |
| `remainder` | `.shortBlock`, `.leaveFree`, `.stretchBlocks` | `.shortBlock` |
| `minBlockMinutes` | `Int` (1–120) | 15 |

`BuiltInPreset` is `classic`, `deepWork`, `longBlocks` with the values from D5. The remainder choice has no effect in `.netFocus` (the core ignores it); the UI disables it there. Values read back from storage that fall outside their ranges are clamped; data that cannot be decoded gives the defaults.

### 3.2 Evaluation

A pure function `DaySetup.evaluate(form:now:calendar:) -> DaySetupResult`:

- Converts `TimeOfDay` values to dates on the calendar day of `now` (in the calendar's time zone). The start is `now`.
- Builds the `DayPlanRequest` and generates the plan with `PlanGenerator`.
- Result is `.ready(request, preview, notices)` or `.invalid(issue)`.

`DayPreview`: `segments`, `focus`, `rest`, `endsAt`, `freeRemainder` (seconds between the end of the last segment and the requested end; zero in `.netFocus`).

Issues, which block "Start":

- `endNotAfterNow`: in `.untilTime`, the end time is at or before now.
- `dayTooShort`: the generated plan is empty.
- `invalidInput`: the generator refused the request. It cannot happen after the form is normalized; it exists so a refusal is never mistaken for a short day.

Notices, which do not block:

- `longBreakNotPlaced`: a long break was requested but the plan has none (the core drops it when it does not fit; core decision D4).
- `remainderLeftFree(minutes)`: part of the day is left free.

### 3.3 DaySetupModel

`@MainActor @Observable final class DaySetupModel`, with dependencies passed in: `AppSettings`, `WallClock`, `Calendar`, a `canStart` closure and a `start(DayPlanRequest) async` closure (wired to the controller).

- `form`: every change is saved to `AppSettings` and the preview is recomputed.
- `now` and `refresh()`: the preview is recomputed from the clock when the window appears and every 30 seconds while it is open.
- `result` and `canStartNow` (a ready result and `canStart()`).
- `startDay()`: re-evaluates at the clock's current time (not the preview's `now`), and if the result is ready calls `start(request)`. It does nothing when invalid or not allowed.

### 3.4 Controller

`SessionController.startDay(request:) async` replaces `startQuickDay`: guards `isAllowed(.startDay)`, awaits authorization once, generates the plan, calls `engine.startDay` and `start()`, saves once. The quick-start constants and tests are removed or migrated.

## 4. Interface

- **Scene:** a single-instance `Window("window.setup.title", id: "day-setup")`, about 600×640, not resizable, next to the `MenuBarExtra`.
- **Opening:** the popover's idle and finished states show "Plan day…" (`PopoverAction.planDay`, shown when `startDay` is allowed). It calls `openWindow(id:)` then `NSApplication.shared.activate()`, because an app without a Dock icon does not come to the front by itself. After a successful start the window is dismissed and the popover shows the timer.
- **Left, the form:** preset menu (three fields for "Custom"); mode segmented control; end time or focus amount; long break menu (none / at time / after block no.) with its field; remainder menu with the minimum block field, disabled in net-focus mode.
- **Right, the preview:** a summary (focus, rest, ends at, free remainder), issues and notices, and a scrollable list of segments with times in the system locale's format; the long break is highlighted. No counts are shown, so the catalog still needs no plural variations.
- **Bottom:** a prominent "Start" button, disabled with a stated reason on an issue, and "Close".
- **While a day is running:** the window shows "End the current day first" and an "End day" button instead of the form.
- **Accessibility:** every field is labelled; a segment row reads as a whole ("Work, from 09:00 to 09:50"); the reason "Start" is disabled is available to VoiceOver.
- **Localization:** all new text in the catalog in `en` and `uk`; durations use the locale-aware duration format.

## 5. Testing and verification

Unit tests (Swift Testing):

- `DaySetup.evaluate`: a request for every combination of the form; time-of-day to date conversion with different time zones and across a DST change; the issues and notices.
- The preview for the stage-1 example (09:00–17:00 from 09:00, 50/10/45, long break at 13:00, short block 15 min): long break 12:50–13:35, 375 minutes of focus.
- `DaySetupModel`: changing the form recomputes the preview and saves it; restore from `AppSettings`; undecodable or out-of-range stored data; `startDay()` calls `start` with the same request the preview shows (evaluated at click time); nothing happens when invalid or not allowed.
- `SessionController.startDay(request:)` (migrated quick-start tests): plan from the request, one save, one authorization.
- `PopoverActions`: "Plan day…" for idle and finished.
- Catalog completeness for the new keys (existing test).
- End to end: a request from the form starts a day, a new controller over the same files continues it.

Before the PR: both suites green, a warning-free build, and a run of the app. The window's look, `DatePicker` behaviour and bringing the window to the front are checked by the user on a real run (a checklist goes into the PR), because screenshots are not available from the command line.

## 6. Risks

1. `openWindow` plus `activate()` may leave the window behind other windows for an app without a Dock icon. Mitigation: check by running; fallback is switching the activation policy to `.regular` while the window is open.
2. `DatePicker` bound to `TimeOfDay` on macOS 26. Mitigation: the conversion is unit-tested; the look is checked on a real run.
3. The preview depends on the clock. Mitigation: injected clock in tests; 30-second refresh in the window.
4. Because the plan is generated at the click, it can differ from the preview by up to a minute. Mitigation: the preview is labelled "from now", and the request is built at click time.

## 7. Out of scope

The day screen with timelines and the plan-vs-actual summary, and the session settings UI (2c); history (2d); a user-managed preset library; planning ahead or starting automatically at a time; days that cross midnight.

## 8. Decisions made during planning and implementation

| # | Decision |
|---|---|
| Q1 | `DaySetupIssue` has a defensive third case `invalidInput` (the generator refused the request); it cannot happen after normalization. |
| Q2 | The 2a quick-start was kept as a thin wrapper while the popover moved to "Plan day…", then removed. |
| Q3 | Out-of-range stored form values are clamped, never rounded to the stepper step. |
| Q4 | A time of day that does not exist on a daylight-saving day becomes the next valid instant (`matchingPolicy: .nextTime`). |
| Q5 | A second `startDay()` while one is in flight is ignored. |
| Q6 | While a day runs, the window shows a notice and an "End day" button instead of the form. |
| Q7 | Durations use the locale-aware `Duration.UnitsFormatStyle` (`6 hr, 15 min` / `6 год, 15 хв`); times use the locale's short time style. |
| Q8 | The preview refreshes through a `TimelineView` every 30 seconds and when the window appears. |
| Q9 | `startDay()` returns whether a day was started; the window closes only on `true`. |
| Q10 | `SessionController.startDay(request:)` generates the plan before asking for notification permission, so a request the generator rejects never triggers the prompt, and it re-checks that starting is still allowed after the prompt. |
