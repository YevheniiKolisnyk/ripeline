# Ripeline — Specification

Ripeline is a native macOS menu bar app for the Pomodoro technique.

- **Stack:** Swift 6 (strict concurrency), SwiftUI.
- **Target:** macOS 26+ (Liquid Glass).
- **License:** MIT, open source.
- **Distribution:** intended for the Mac App Store later.

## 1. Project constraints

These apply from day one, to every stage.

1. **Public APIs only.** No private frameworks, SPI or undocumented behavior.
2. **App Sandbox.** The app must work inside the App Sandbox with minimal entitlements.
3. **No personal data in the repository.** `DEVELOPMENT_TEAM` and the bundle identifier
   come from `Config/Local.xcconfig` (gitignored). `Config/Local.example.xcconfig` is
   committed as a template.
4. **Privacy.** The app collects no data and sends no data.
5. **English.** All code, comments, README and SPEC are written in English.
6. **Localization.** UI strings go through a String Catalog from the start, with
   English (`en`) and Ukrainian (`uk`).

## 2. Concept

At the start of the day the user picks a preset (e.g. 50 min work / 10 min break /
45 min long break) and defines a day plan. The app generates the plan once, as a list of
segments.

The plan is **fixed**: it is never recalculated after the day starts. The timer walks
through the segments, and for each segment the app records what actually happened.

The UI shows two timelines on a shared time axis: **planned** and **actual**.

## 3. Stages

| Stage | Scope |
|-------|-------|
| 1 | Domain logic only (`RipelineCore` package). |
| 2+ | UI, Xcode app project, persistence (not specified yet). |

## 4. Stage 1 — Domain logic

A local Swift package `RipelineCore` in `Packages/`, with no SwiftUI or AppKit
dependencies. Tests use Swift Testing and run via `swift test`.

### 4.1 Models

All models are `Codable`, `Sendable` and `Equatable`.

- **Preset:** `workMinutes`, `shortBreakMinutes`, `longBreakMinutes`.
- **SegmentKind:** `work`, `shortBreak`, `longBreak`.
- **PlannedSegment:** `id`, `index`, `kind`, `start: Date`, `end: Date`.
- **DayPlanRequest:**
  - `mode`: `.untilTime(start, end)` | `.netFocus(start, focusMinutes)`;
  - `longBreak`: `.none` | `.atTime(Date)` | `.afterWorkBlock(Int)`;
  - `remainderStrategy`: `.shortBlock(minMinutes)` | `.leaveFree` | `.stretchBlocks`;
  - `preset`.
- **Settings:**
  - `pausesCountAsRest: Bool` — default `true`;
  - `autoAdvanceWorkToBreak: Bool` — default `false`;
  - `autoAdvanceBreakToWork: Bool` — default `false`.

### 4.2 Plan generation

`PlanGenerator`: `DayPlanRequest` → `[PlannedSegment]`.

General rules:

- There is no break after the last work block.
- The long break **replaces** the short break at a junction between two work blocks.
  - `.atTime(t)`: use the junction closest to `t` (the earlier one on a tie).
  - `.afterWorkBlock(n)`: use the junction after the n-th work block.

Mode `.untilTime(start, end)`:

- Fit as many full cycles as possible before `end`.
- Handle the remainder according to `remainderStrategy`:
  - `.shortBlock(minMinutes)`: a short break plus a work block filling the rest, if that
    block is ≥ `minMinutes`; otherwise leave the remainder free.
  - `.leaveFree`: leave the remainder free.
  - `.stretchBlocks`: lengthen work blocks evenly so the plan ends exactly at `end`.

Mode `.netFocus(start, focusMinutes)`:

- Generate work blocks until total work minutes reach `focusMinutes`.
- The last block may be shorter.

Required test case:

- Input: `.untilTime(09:00, 17:00)`, preset 50/10/45, `.atTime(13:00)`,
  `.shortBlock(minMinutes: 15)`.
- Expected:
  - long break 12:50–13:35;
  - 7 work blocks of 50 min plus one work block 16:35–17:00 (25 min);
  - total focus 375 min.

Edge cases to test:

- a day shorter than one block;
- a long break requested before the first junction or after the last one;
- a remainder below `minMinutes`;
- `.stretchBlocks`.

### 4.3 Actual data

Each `PlannedSegment` has a `SegmentActual`:

- `status`: `notStarted` | `active` | `completed` | `skipped`;
- `intervals: [ActualInterval]`, where `ActualInterval` = `kind` (`.work` | `.rest` |
  `.untracked`), `start`, `end`.

Rules:

- Running time in a work segment → `.work`; running time in a break segment → `.rest`.
- Pause: if `pausesCountAsRest` is `true` → `.rest`, otherwise → `.untracked`.
  Untracked time is shown on the timeline as a neutral gap and counted as neither work
  nor rest.
- Pausing stops the segment countdown (remaining time is preserved), for both work and
  break segments.

One segment can therefore contain, for example, work 35 min → rest 2 min → work 3 min.

If a break auto-advances into work and the user pauses immediately, that pause becomes
rest by the same rule. No special case is needed for this.

### 4.4 Session engine

`SessionEngine` is a state machine. All time is computed from `Date`s
(`endsAt − now`), never by decrementing a counter, so it stays correct after the Mac
sleeps.

States:

- `idle`
- `running(segmentIndex, endsAt)`
- `paused(segmentIndex, remaining)`
- `overtime(segmentIndex, since)`
- `finished`

When a segment's time runs out:

- if auto-advance is on for that transition, the next segment starts immediately;
- otherwise the engine enters overtime and counts up until the user advances.

Overtime is recorded in the **current** segment with that segment's kind
(work → `.work`, break → `.rest`). This is how "the 45-minute segment actually took 47"
is captured.

Actions: `startDay(plan, settings)`, `start`, `pause`, `resume`, `extend(minutes)`,
`skip`, `advance` (leave overtime / go to the next segment), `endDay`.

After a sleep or a long gap, when the engine is ticked with a later "now", it catches up
correctly:

- with auto-advance, it walks through every segment that ended in between and records
  intervals with their real times;
- without auto-advance, it ends up in overtime of the segment that was running.

The clock is injected via a protocol so tests control time.

The full engine state (plan + actuals + current state) is `Codable`, so stage 2 can
persist and restore it.

### 4.5 Schedule status (lag indicator)

```
projectedEnd = now
             + remaining time of the current segment (0 if in overtime)
             + durations of all remaining not-started segments

lag = projectedEnd − planned end of the day
```

Positive lag = behind schedule; negative lag = ahead of schedule.

### 4.6 Day comparison (plan vs actual)

`DayComparison`:

- per segment: planned minutes, actual work / rest / untracked minutes, delta;
- totals: focus planned / actual, rest planned / actual, total untracked, planned vs
  actual end of day.

### 4.7 Timeline data

Data prepared for the UI, so the UI only has to draw:

- planned blocks: `[(kind, start, end)]`;
- actual blocks: `[(kind, start, end)]`, with adjacent intervals of the same kind
  merged.

### 4.8 Test coverage

Cover with tests:

- the plan generator;
- every state machine transition;
- overtime;
- pause in both `pausesCountAsRest` modes;
- skip;
- extend;
- catch-up after sleep, with and without auto-advance;
- lag calculation;
- comparison totals.

### 4.9 Out of scope for stage 1

- any UI;
- the Xcode app project;
- persistence (everything is just made `Codable`).

## 5. Decisions log

Clarifications of this specification are recorded here as they are made.

### Units and input validation

- **D2 — Units.** Inputs stay in whole minutes (preset, focus, `minMinutes`, `extend`).
  Computed durations are `TimeInterval` (seconds); the UI formats them.
- **D3 — Invalid input.** `PlanGenerator.generate` throws `PlanError` for non-positive
  preset values, `end <= start`, `focusMinutes <= 0`, `afterWorkBlock(n < 1)` and
  `minMinutes < 1`. A valid request whose day is too short for any block returns `[]`.

### Plan generation

- **D6 — Day shorter than one block.** `.shortBlock(min)`: one block filling the whole
  window if it is at least `min`, otherwise `[]`. `.leaveFree` and `.stretchBlocks`: `[]`
  (there is no full block to stretch).
- **D7 — Stretch rounding.** Extra time is spread in whole minutes, earliest blocks first.
  Any sub-minute residue (only possible with non-minute-aligned input) goes to the last
  block.
- **D8 — `.netFocus`.** `remainderStrategy` is ignored.
- **D4 — Long break junction.** A junction's time is the end of the work block before it,
  measured on the nominal layout (full blocks, short breaks). Candidates are tried
  closest-first (earlier wins a tie). If placing the long break pushes out the block after
  it (so the junction no longer exists), the next candidate is tried. If none fits, the plan
  has no long break. `.afterWorkBlock(n)` past the last junction gives no long break.
  The junction is chosen before stretching, so `.stretchBlocks` may move the long break later.
- **D5 — Long break and remainder.** With `.shortBlock`, if the remainder block follows the
  long-break junction, the long break is used there (it replaces the short one).

### Session engine

- **D1 — Naming.** `Settings` is `SessionSettings` (avoids clashing with SwiftUI's `Settings`
  scene). The clock protocol is `WallClock` (avoids Swift's `Clock`). The states enum is
  `SessionState`; the full persisted value is `SessionSnapshot`.
- **D12 — Segment statuses (part 1).** `endDay` while running or paused marks the current
  segment `.skipped` and keeps what was recorded. Untouched segments stay `.notStarted`.
- **D13 — `startDay` scope.** Valid only when idle or finished. A day in progress must be
  ended first.
- **D14 — Interval recording.** Every state change closes the open interval and opens the
  next one, so a segment holds one interval per stretch of running, paused or overtime.
  Zero-length intervals are dropped. Merging adjacent intervals is the timeline's job.
