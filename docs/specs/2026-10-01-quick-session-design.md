# Quick session: design

Status: draft for review. Parent specs: [`SPEC.md`](../../SPEC.md), stages 1 and 2a–2d. Adds a way to start work in one tap, without planning a day, and a small change to `RipelineCore` to support it.

## 1. Goal

Let the user start a task immediately, without planning a day: pick a block length from a short list, press Start, and the block runs. If the task takes longer the user adds five minutes, or another block, and presses "Done" when finished. The result is one session in the history.

**Success criteria**

1. With no day running, the popover offers a block length (25, 50 or 90 minutes) and a Start button; one press starts a block right away, with no other step.
2. While a quick session runs the user can pause and resume, add five minutes, skip, add another block and finish with "Done".
3. "Another block" adds a short break and a block of the same length to the same session; it can be pressed any number of times, including during a pause or overtime.
4. The session behaves like a day for everything else: menu bar, popover timer, notification at the end of each segment, saving, restoring after a relaunch, and the history.
5. For a quick session the day screen and the history hide what only makes sense with a plan (lag, planned end, projected end) and mark the session as "Quick".
6. Existing day files still load, and ordinary days keep their fixed plan.
7. All new text is in the String Catalog (`en`, `uk`); no new entitlement; no network.

## 2. Decisions

| # | Decision | Chosen by |
|---|---|---|
| Q1 | A selector of block lengths and an immediate start; no planning screen. | user |
| Q2 | While it runs: "+5 min", "Another block" and "Done", besides pause and skip. | user |
| Q3 | One session, to which blocks are added: all blocks of the task are one history entry. | user |
| Q4 | The block lengths offered are 25, 50 and 90 minutes; the last choice is remembered. | proposed |
| Q5 | "Another block" adds a short break and then a block: 5, 10 or 15 minutes of break for 25, 50 or 90. The break can be skipped like any break. | proposed |
| Q6 | The new block has the length of the first block of the session. | proposed |
| Q7 | Lag, planned end and projected end are hidden for a quick session: there is no plan to be behind. | proposed |
| Q8 | The session kind is a flag in the core's snapshot (`day` or `quick`); files without it read as `day`. | proposed |
| Q9 | Only a quick session can have segments added, and only while it runs, is paused or is in overtime. | proposed |

## 3. Core (`RipelineCore`)

The only change to the core; everything else is the app. All additions are backward compatible.

- `SessionKind` (`day`, `quick`), `Codable`. `SessionSnapshot` gains `kind`, read with a default of `day` when absent, so files written before this change decode as ordinary days.
- `SessionEngine.startDay(plan:settings:kind:)` takes the kind, defaulting to `.day`; behavior is unchanged for days.
- `SessionAction.append`, allowed when the kind is `quick` and the state is running, paused or overtime.
- `SessionEngine.appendSegments(_:)` adds segments to the end of the plan and an empty record for each. They must continue the indices, start exactly where the plan ends, and have a positive length; otherwise it throws `SessionError.invalidPlan`. When not allowed it throws `SessionError.notAllowed(.append)`. Nothing else changes: catch-up, restoring, lag and the read models treat the result as a longer plan.

## 4. App

### 4.1 QuickSession (pure logic)

- `QuickBlockLength`: 25, 50, 90 minutes, with the matching break of 5, 10, 15.
- `plan(length, now)`: one work block of that length starting at `now`.
- `nextBlocks(after plan)`: a short break followed by a block, starting where the plan ends, with the length of the plan's first block (Q6) and the break from the table (Q5).

### 4.2 SessionController

`startQuickSession(length:)` generates the plan, starts the engine with kind `quick`, saves, and requests notification permission as for any first day. `addBlock()` appends `nextBlocks(after:)` and saves. `isQuickSession` reflects the kind. The chosen length is stored in `AppSettings`. Notifications, the ticker and persistence need no change: the controller already reconciles them with every state change.

## 5. Interface

- **Popover, no day:** above "Plan day…", a "Quick start" row with a menu of the three lengths and a "Start" button. Pressing Start begins the block at once.
- **Popover, quick session running:** pause or resume, "+5 min", "Another block", skip, and "Done" in place of "End day". The overview and history links stay.
- **Day screen:** for a quick session the lag chip, the planned end and the projected end are hidden; the timelines, the focus, rest and paused figures and the segment table are shown. The end button reads "Done".
- **History:** a "Quick" badge in place of the lag figure; the details hide the same figures as the day screen.
- **Localization:** all new text in the catalog in `en` and `uk`; no counts are shown, so no plural variations.

## 6. Testing and verification

- **Core:** appending in each state and refusal in the others (day kind, idle, finished); index, start and length checks; the actual records stay in step with the plan; JSON without `kind` decodes as a day and a quick session round-trips; catch-up and restoring over a plan that grew; the projected end counts appended segments.
- **App:** `QuickSession` plans and break sizes, and the length taken from the first block; the controller starting, adding blocks (also during a pause and an overtime) and finishing; a relaunch with several blocks; a notification scheduled for each new segment; the day overview hides plan-only figures for a quick session and keeps them for a day; the history badge; catalog completeness.
- **End to end:** a quick session with two added blocks over real files, a relaunch, the same overview and history.
- **Backward compatibility on real days:** the core with the new field must read the developer's existing day files (a read-only throwaway check, never committed).
- Before the PR: both suites green, a warning-free build, a run of the app. The look of the popover section and the "Quick" badge go on the checklist in the PR.

## 7. Risks

1. Changing the snapshot's `Codable` could break reading old files. Mitigation: the field is optional on read, with a test on real JSON written without it.
2. Adding a block while a break or overtime is running. Mitigation: allowed and tested; the new segments simply follow the current end of the plan.
3. A quick session is a day to the history, so an ordinary "Plan day" is not blocked during one. Mitigation: starting a day needs the engine to be idle or finished, as before; a running quick session must be finished first.

## 8. Out of scope

A mode with no block length (a stopwatch); custom block lengths; a name or label for a task; templates; changing the plan of an ordinary day.
