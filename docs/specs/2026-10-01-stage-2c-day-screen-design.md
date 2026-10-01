# Stage 2c — Day screen: design

Status: draft for review. Parent specs: [`SPEC.md`](../../SPEC.md), [2a](2026-10-01-stage-2a-app-shell-design.md), [2b](2026-10-01-stage-2b-day-setup-design.md). Builds on the read models of `RipelineCore` (`Timeline`, `DayComparison`, `ScheduleStatus`), which already exist and are tested.

## 1. Goal

Show how the day is going against the plan: two timelines (planned and actual) on a shared time axis, how far ahead or behind the user is, and a plan-versus-actual summary with a table of segments. Let the user change how sessions behave (pauses, auto-advance) from the same window.

**Success criteria**

1. While a day runs, the window shows the planned and actual rows on one axis, a "now" marker, the lag, a summary and a segment table, all current to within five seconds.
2. After the day ends, the same screen shows the final comparison with a "New day" button.
3. The three session settings can be changed before a day and during one; changes apply from the next transition and are saved.
4. The numbers on screen are exactly those the core computes (`Timeline`, `DayComparison`, `ScheduleStatus`); the screen adds geometry and wording only.
5. All new text is in the String Catalog (`en`, `uk`); no new entitlement; no network.

## 2. Decisions

| # | Decision | Chosen by |
|---|---|---|
| C1 | Timelines run on a horizontal axis: time left to right, a "Plan" row above an "Actual" row, a "now" marker. | user |
| C2 | Session settings live in the window, in a collapsible "Behaviour" section available both when planning and during a day. No separate Settings scene. | user |
| C3 | One window that changes content: the planning form when there is no day, the day screen while a day runs or after it ended. The popover has one entry that opens it. | user |
| C4 | Layout and arithmetic live in a pure, testable `DayOverviewModel`; the views only draw its output. | user |
| C5 | The model refreshes every 5 seconds while the window is open and when it appears. | proposed |
| C6 | Lag within one minute either way counts as "on schedule". | proposed |
| C7 | Axis steps: 30 minutes for spans up to 4 hours, 1 hour up to 10 hours, 2 hours beyond. Ticks fall on whole steps of local wall-clock time. | proposed |
| C8 | Blocks have a minimum drawn width of 2 pt; labels are in tooltips and VoiceOver, not on the blocks. | proposed |
| C9 | Colour is never the only cue: work is full height, breaks are lower, the long break is highlighted, untracked time is grey and hatched. | proposed |
| C10 | There is no separate overtime marker. The core records overtime as ordinary work or rest time, so it cannot be told from planned time per block; it is visible as the actual row running past the plan row, and as a positive delta in the table. | proposed |

## 3. Logic

### 3.1 Controller

`SessionController` exposes, computed for the current time and tracked through `now`:

- `timeline: Timeline`, `comparison: DayComparison` and the existing `scheduleStatus`, straight from the engine;
- `updateSessionSettings(_:)`: writes `AppSettings.session` and calls the engine's `updateSettings`, so the values apply from the next transition of the current day; the snapshot, which carries the settings, is saved with the next change.

### 3.2 DayOverviewModel

`@MainActor @Observable final class DayOverviewModel`, reading through a small protocol `DayOverviewSource` (implemented by the controller; a stub in tests) and an injected clock and calendar.

**Mode:** `.noDay` (no plan loaded), `.running` (a segment is running, paused or in overtime), `.finished`.

**`TimeAxis`:** the domain runs from the earliest start to the latest end among planned blocks, actual blocks and, while running, now; its start is rounded down and its end up to the tick step (C7). Ticks are the multiples of the step in the calendar's time zone. `x(for:)` maps a date to 0…1.

**Rows:** `planned` and `actual`, each an array of `BlockLayout` (kind, start, end, `x`, `width` as fractions of the axis, with the C8 minimum applied when drawing). The merging of adjacent actual intervals is the core's (`Timeline`).

**Now marker:** `nowX`, present only in `.running`.

**Lag:** `LagState` is `.onSchedule`, `.behind(seconds)` or `.ahead(seconds)` from `ScheduleStatus.lag` and C6; absent when there is no status.

**Summary (`DaySummary`):** focus planned and actual, rest planned and actual, untracked time, the planned end, and the projected end while running or the actual end once finished.

**Segment rows (`SegmentRow`):** planned start, kind, planned, work, rest and untracked seconds, delta, and status (`active`, `completed`, `skipped`, `notStarted`), taken from `DayComparison`.

`refresh()` re-reads the source and the clock. With no day it does nothing and never fails.

## 4. Interface

- **Window:** one single-instance `Window` scene, "Ripeline", minimum about 720×620 and resizable. The 2b scene and its identifier are replaced by this one. Content by mode (C3): `.noDay` shows the 2b planning form unchanged; `.running` and `.finished` show the day screen. In `.finished` a "New day" button switches the content to the planning form; starting a day switches back.
- **Day screen, top to bottom:**
  1. header: the phase, the lag chip ("3 min behind", "on schedule", "2 min ahead"), the planned end and the projected (or final) end;
  2. the two timelines with hour labels under them, the "now" line and a legend;
  3. the summary (focus, rest, untracked);
  4. the segment table (planned start, kind, planned, actual, delta, status);
  5. the "Behaviour" section with three switches: "Count pauses as rest", "Start the break automatically when work ends", "Start work automatically when a break ends", with the note that changes apply from the next transition; and, while a day runs, an "End day" button.
- **Drawing:** plain SwiftUI rectangles placed from the model's fractions inside a `GeometryReader` (not `Canvas`), so a headless `ImageRenderer` can draw them for visual checks. Block tooltips use `.help`; each block has a VoiceOver label ("Plan: Work, from 9:00 to 9:50").
- **Popover:** while a day runs, a "Day overview…" link under the control buttons opens the window; when the day is finished the single button is "Day summary…"; with no day it is still "Plan day…". The control buttons stay in the popover.
- **Localization:** all new text in the catalog in `en` and `uk`; durations use `SetupText.duration`; no counts are shown, so no plural variations.

## 5. Testing and verification

Unit tests (Swift Testing):

- `TimeAxis`: domain from plan, actual and now; rounding to the step; ticks for each step size in UTC, +03:00 and New York across a daylight-saving change; a day crossing midnight.
- Layout on the stage 1 day (09:00–17:00, long break 12:50–13:35): `x` and `width` of each block; actual running past the plan; starting before the plan; a skipped segment; an untracked pause.
- `DayOverviewModel`: the three modes; `nowX` only while running; lag thresholds; summary and table on the scenario of the 2a review (work 52 min, 5 min untracked pause, rest 12 min, a skipped segment); refreshing as the clock moves; no day without a crash.
- Controller: `timeline` and `comparison` equal the core's; `updateSessionSettings` changes the engine and is saved; after enabling auto-advance the next segment starts by itself.
- Texts: block labels and the lag chip in `en` and `uk`; catalog completeness.
- `PopoverActions`: the new link and the finished-day button.
- End to end: a day with several transitions over real files, a relaunch, and the screen shows the same plan and actual.

Before the PR: both suites green, a warning-free build, and a run of the app. The timelines and table are rendered once with a throwaway `ImageRenderer` test to check them by eye (forms and pickers do not render that way); the form, bringing the window to the front and real behaviour go on a checklist in the PR.

## 6. Risks

1. Narrow blocks: a 10-minute break is about 11 pt on a 700 pt axis. Mitigation: C8 minimum width, tooltips, resizable window.
2. A 12-hour day compresses blocks. Mitigation: the axis scales to the width; the window can be enlarged.
3. The window's content switches with the controller's state; it must not flicker. Mitigation: tested modes and a run of the app.
4. A refresh every 5 seconds must stay cheap when the window is closed. Mitigation: the model does nothing unless the window is open.

## 7. Out of scope

History of past days (2d); export; zooming the axis; editing recorded time; reminders and sounds beyond 2a; autostart; a redesign of the popover.
