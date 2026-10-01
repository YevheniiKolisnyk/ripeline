# Stage 2d — History: design

Status: draft for review. Parent specs: [`SPEC.md`](../../SPEC.md), [2a](2026-10-01-stage-2a-app-shell-design.md), [2b](2026-10-01-stage-2b-day-setup-design.md), [2c](2026-10-01-stage-2c-day-screen-design.md). Reads the per-day files that 2a writes; reuses the day screen views of 2c.

## 1. Goal

Let the user look back at past days: a list of the days the app has recorded and, for a chosen day, the same timelines, summary and table as on the day screen. Let the user delete a day. Nothing leaves the Mac.

**Success criteria**

1. A "History" tab in the app's one window lists every recorded day except the one that is running, newest first, and shows the chosen day's planned and actual timelines, summary and segment table, read only.
2. A day that was never ended (the app was closed during it and a later day started) is listed and clearly marked "Not finished"; its blocks stop at the last record instead of growing to "now".
3. A day can be deleted after a confirmation; the running day cannot; a failed deletion leaves the file and says so.
4. One damaged or unreadable file never hides the others.
5. All new text is in the String Catalog (`en`, `uk`); no new entitlement; no network.

## 2. Decisions

| # | Decision | Chosen by |
|---|---|---|
| H1 | History is a "Today \| History" tab in the existing window, a list on the left and the day's details on the right. | user |
| H2 | Past days can be viewed and deleted (with confirmation). No export. | user |
| H3 | Logic lives in a testable `@MainActor @Observable HistoryModel`; the day's details are the 2c views fed by a snapshot-based `DayOverviewSource`. | user |
| H4 | The list excludes the day that is running now (it is on the "Today" tab). Finished days and abandoned days are listed. | proposed |
| H5 | Deletion is permanent and applies to one day at a time; damaged (`.corrupt`) and newer-version (`.unsupported`) files are never touched or listed. | proposed |
| H6 | A snapshot is drawn at its last recorded instant, not at "now": a finished day at its end, an abandoned day at its last record. | proposed |
| H7 | A small shared `AppRouter` holds the selected tab, so the popover can open the window on the right one. | proposed |
| H8 | The popover offers "History…" in every phase, as a link under the buttons. | proposed |
| H9 | The list is read in full when the tab appears and when the running day ends; if this ever gets slow it is limited to the latest 200 days. | proposed |

## 3. Logic

### 3.1 Store

`DayStore` gains:

- `loadAll() throws -> [StoredDay]`: every readable day, newest first by the start of its plan (ties by file name, newest number first). Damaged and newer-version files are skipped (not set aside again, not fatal); an unreadable entry never stops the rest.
- `delete(_ day: StoredDay) throws`: removes that day's file. It never touches `.corrupt` or `.unsupported` files. If the removal fails the error is thrown and the file stays.

### 3.2 Entries

`HistoryEntry` (one row): the key, the plan's first start and last end, the actual end (or `nil`), focus actual and planned, rest actual, whether the day was finished, and a lag figure for a finished day (actual end minus planned end). Figures come from the core's `DayComparison(snapshot:now:)` at the snapshot's fixed instant (H6).

### 3.3 SnapshotSource

A `DayOverviewSource` over one `SessionSnapshot`, with `now` fixed at its last recorded instant (the latest end of a recorded interval or the start of the open one; the plan's first start if nothing was recorded). Its phase is always "finished", so `DayOverviewModel` draws the day without a "now" line or a lag chip. A new optional `overviewLastRecord` lets the summary say "Last record at" for a day that was never ended, where a finished day says "Finished at". `DaySummary.endIsFinal` becomes `endKind` (`projected`, `final`, `lastRecord`).

### 3.4 HistoryModel

`@MainActor @Observable final class HistoryModel`, over a `DayStore` and an "active day" identifier (so the running day is left out):

- `entries`, `selection` (the newest by default), `detail: DayOverviewModel?` for the selection;
- `refresh()`: re-reads the store; keeps the selection if it still exists, otherwise picks the neighbour or the newest;
- `requestDelete(_:)`, `confirmDelete()`, `cancelDelete()`, `deleteError`: deleting moves the selection to the neighbouring row and refreshes; the active day cannot be requested; a failure keeps the day and sets `deleteError`;
- an empty state when there are no days.

## 4. Interface

- **Tabs:** a "Today | History" segmented control at the top of the window. "Today" is the existing screen (planning form or day screen). The selected tab lives in `AppRouter`.
- **History tab:** on the left a list of days: a title ("Wed, 1 Oct" in the locale), a second line ("10:02–12:40 · Focus 2 hr 13 min / 4 hr") and a badge ("Finished" or "Not finished"); on the right the chosen day: its date and times, the two timelines, the summary and the segment table from 2c, and a "Delete day…" button. For a day that was never ended the summary says "Last record at". An empty history says "No days yet" with the hint "Finished days appear here."
- **Deleting:** a confirmation dialog, "Delete this day? It is removed from this Mac and cannot be restored." with a destructive "Delete" and "Cancel". A failed deletion shows "The day could not be deleted." under the list.
- **Popover:** a "History…" link in every phase, under the buttons; it opens the window on the History tab. "Day overview…", "Plan day…" and "Day summary…" open it on "Today".
- **Accessibility:** each row reads as a whole ("Wednesday 1 October, 10:02 to 12:40, finished, focus 2 hr 13 min of 4 hr"); the details keep the block labels of 2c.
- **Localization:** all new text in the catalog in `en` and `uk`; dates and durations are locale-aware; no counts are shown, so no plural variations.

## 5. Testing and verification

Unit tests (Swift Testing):

- `FileDayStore.loadAll`: newest first; several days on one date; damaged and newer-version files skipped without hiding the rest; empty and missing directory; days saved under different time zones.
- `FileDayStore.delete`: the file disappears and the others stay; `.corrupt` and `.unsupported` files are untouched; a failure keeps the file; deleting the same day twice is safe.
- `HistoryModel`: entries and figures on the scenario of the 2a review; an abandoned day; the running day left out; the default selection; deleting (neighbouring selection, the last day gives the empty state, cancel changes nothing, a failure keeps the day and reports it); refreshing keeps the selection.
- `SnapshotSource`: the same blocks, summary and table as the live model for the same snapshot; an abandoned day does not grow with the clock; "Last record at" versus "Finished at".
- Texts: the date title, the row line and the VoiceOver label in `en` and `uk` and across time zones; catalog completeness.
- `PopoverActions`: the "History…" link in every phase.
- End to end: several days over real files, one deleted, a relaunch, and the history shows the rest while the running day is untouched.

Before the PR: both suites green, a warning-free build, and a run of the app against the days already in the container (they must load, and nothing is deleted). The rows and the details are rendered once headlessly to check them by eye; the `List`, the dialog and the tabs go on the checklist in the PR.

## 6. Risks

1. Many days: every file is read when the tab appears. Mitigation: files are a few kilobytes; H9 limits it if it becomes slow.
2. Deletion is permanent. Mitigation: a clear confirmation, no deletion of the running day, a failed deletion keeps the file.
3. A day recorded in one time zone and viewed in another: dates and the axis use the current zone, as on the day screen.
4. An abandoned day looks like it is still running. Mitigation: H6 fixes its instant at the last record.

## 7. Out of scope

Export; statistics and charts across weeks; search and filters; editing a recorded day; restoring a deleted day; cloud sync.
