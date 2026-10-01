# Tomato garden: design

Status: proposed. Parent specs: [`SPEC.md`](../../SPEC.md), stages 1 and 2a–2d, the quick session. Adds a reward for work that was actually done: every work block is a tomato that grows while you work, can be picked when the block is over, and ends up in a big crate in the history.

## 1. Goal

Make tracked focus time feel good. A work block is a tomato; the more you really work, the bigger it grows; you pick the ripe ones and watch them drop into a crate that fills up over the weeks.

**Success criteria**

1. While a work block runs, a tomato grows from a seedling to a ripe one. It reaches 100% exactly when the planned length of the block has been worked.
2. Only recorded work grows a tomato. A pause, a break and an idle app do not.
3. Work beyond the plan (the "+5 min" button, overtime) keeps growing the tomato past 100%: the tomato gets bigger.
4. When the block is over, the tomato can be picked with one click, in the popover and on the day screen. A tomato that is not picked stays on the bed: nothing rots, nothing is lost, no streaks.
5. The day screen draws the timeline as a garden bed with a tomato on every work block.
6. The history has one big crate. Picked tomatoes fall into it with physics. Choosing a day in the history highlights that day's tomatoes.
7. A quick session gives tomatoes in the same way: a block is a tomato.
8. Everything is drawn in a cheerful cartoon style, in code, and respects Reduce Motion and VoiceOver.
9. Existing day files are not touched or rewritten. No new entitlement, no network, no personal data. All text in the String Catalog (`en`, `uk`).

## 2. Decisions

| # | Decision | Chosen by |
|---|---|---|
| T1 | A work block is a tomato; breaks give none. | user |
| T2 | Size is the real work in the block divided by its planned length. 100% is ripe; extra work makes it bigger than 100%. | user |
| T3 | A tomato grows live in the popover and on the day screen; it is picked by a click once the block is over. | user |
| T4 | The history shows one crate in which picked tomatoes pile up with physics; a selected day is highlighted. | user |
| T5 | The existing recorded days were test data and were deleted; there is no migration. | user |
| T6 | Cartoon look, drawn in code. | user |
| T7 | Nothing is punished: an unpicked tomato waits as long as needed. | proposed |
| T8 | Picking is stored in its own file, not in the day files. | proposed |
| T9 | A tomato can be picked when its block is over (completed or skipped), or while it waits in overtime, and only if some work was recorded in it. A block skipped before any work gives nothing. | proposed |
| T10 | A block of the day or quick session that is still running or paused cannot be picked yet. | proposed |
| T11 | Tomatoes below 100% are picked as they are: smaller and greener. | proposed |
| T12 | Physics is SpriteKit (`SpriteView`), a public API. The crate shows at most the 300 most recent picked tomatoes; the total is written on the crate. | proposed |
| T13 | The art is vector drawing in SwiftUI behind one small interface, so it can be swapped for drawn assets later. | proposed |

## 3. Core (`RipelineCore`)

Pure, `Foundation` only, no text. The core exposes values; the app draws and words them.

- `Tomato`: `id` (the segment's id), `segmentIndex`, `workTime` (seconds of recorded work), `plannedTime`, `growth` (`workTime / plannedTime`, 1.0 is 100%, not capped) and `availability`: `.growing` (the block is running or paused), `.pickable` (T9) or `.empty` (no work recorded and the block is over).
- `Tomatoes.of(_ snapshot: SessionSnapshot, at now: Date) -> [Tomato]`: one entry per work segment, in plan order. It reads `plan` and `actuals(at:)`, so an open interval counts up to `now`, and an extended or overtime block counts its extra work. Paused and untracked intervals are not work. Breaks are left out.
- The functions are pure over the snapshot, so growth is derived, never stored, and survives relaunch, sleep and catch-up unchanged. The snapshot and the day files do not change.

## 4. App

### 4.1 Harvest store

- `HarvestStore` protocol with a file implementation and an in-memory one for tests, like `DayStore`. One file, `harvest.json` next to the day folder: `{"version":1,"picked":["<segment id>", …]}`. Writes are atomic.
- `pick(_ id)` adds an id; picking an id twice is harmless. Only `Tomatoes.of(...)` entries that are `.pickable` can be picked.
- On load the set is intersected with the work segments of the days that exist. A deleted day takes its tomatoes with it. The file is rewritten only when the set changed.
- A missing or unreadable file reads as nothing picked; an unreadable file is renamed aside, as the day store already does, and never crashes the app.

### 4.2 Garden model

`GardenModel` (main actor, observable) holds the tomatoes of the running day and the picked set, and offers `pick(_:)`. It is driven by the controller's tick, like the other models, so the live tomato needs no timer of its own. `CrateModel` produces the crate's content: picked tomatoes of all stored days, newest 300 by segment start, plus the total.

### 4.3 Look (T6, T13)

`TomatoArt` draws a tomato from `growth` and a state, and nothing else decides how a tomato looks.

- **Style:** flat vector with a thick warm-brown outline (never pure black), two-tone fill, a white highlight blob, a green star-shaped calyx with a small stem. Round, soft, a little squashed.
- **Growth:** under about 25% a sprout in the soil; then a small green tomato; from about 60% it turns yellow, orange, then red; at 100% it is fully red and gives a small wiggle to say "pick me" once the block is over.
- **Past 100%:** bigger and rounder, with a tiny sparkle. Display scale is capped at the equivalent of 200% so the layout and the physics stay sane; the figures stay honest.
- **Face:** two dot eyes and a small mouth. Sleepy while growing, a smile when ripe, a wide grin when it is bigger than 100%. Faces are cheap to remove if they are not liked.
- **Bed:** a strip of soil with a wooden edge under the timeline. **Crate:** a wooden crate with slats and rope handles, a cartoon wood grain, the total on a small plank.
- Colors are tokens from the asset catalog, with dark appearance variants. The art works at a few sizes: popover, timeline, crate.

The numbers above (the 25/60/100% steps, the 200% cap) are starting values, tuned by eye during implementation.

## 5. Interface

- **Popover:** during a work block a tomato grows next to the timer. Once the block is over, and during overtime, it is picked with one click; a short pick animation plays and the tomato goes into a small basket count. Unpicked tomatoes of the day appear as a little row. In a break the basket is shown.
- **Day screen:** the timeline is the bed. Each work block has its tomato, growing for the block in progress. A pickable one is highlighted and picked with a click. Picked ones show in a "picked" look.
- **History:** a crate view above or beside the list of days. Tomatoes fall into the crate when it is opened; picking a tomato while the history is open drops it in. Selecting a day lifts that day's tomatoes with a glow. The total is shown on the crate.
- **Reduce Motion:** no falling and no wiggle; the crate appears already filled and the tomatoes are static.
- **VoiceOver:** each tomato says what it is, its percentage and whether it can be picked; picking is an accessibility action, not only a click.
- **Localization:** new text only for labels and accessibility; counts use plural variations in `en` and `uk`.

## 6. Testing and verification

- **Core:** growth for a block worked exactly as planned, less, and more; a "+5 min" extension and overtime counted as extra work; a pause not counted; a block skipped with and without work; an open interval counted up to `now`; a quick session with added blocks; breaks give no tomato; availability in each state.
- **App:** the harvest store round trip, atomic write, harmless double pick, pruning of deleted days, a damaged file; `GardenModel` picking only pickable tomatoes; `CrateModel` taking the newest 300 and reporting the total; a relaunch keeping the picked set; deleting a day removing its tomatoes; the catalog is complete.
- **End to end:** record days over real files, pick tomatoes, relaunch, the same crate content.
- **Not covered by tests, so on the PR checklist:** the look of the tomatoes and the crate, the physics feel, the animations, Reduce Motion and the dark appearance, and the layout of the popover in Ukrainian.
- Before the PR: both suites green, a warning-free build, a run of the app.

## 7. Risks

1. **Physics cost and jitter** with hundreds of bodies. Mitigation: the 300 cap, bodies put to sleep when they rest, a fixed seed for the drop order, a performance check on the checklist.
2. **SpriteKit inside SwiftUI** is a new dependency of the app. Mitigation: it stays in one view; no other screen needs it.
3. **Picking state that drifts from the days.** Mitigation: pruning on load; the id is the segment's id, which is stable.
4. **Art that does not please.** Mitigation: all drawing is behind `TomatoArt` and tuned by eye; the faces and the sparkle are optional.
5. **A pick during overtime, then more overtime.** The tomato's size is always derived from the final record, so the crate shows the final size. Accepted: the harvest is the block, not a moment.

## 8. Out of scope

Menu-bar icon animation; varieties and unlockables; achievements, streaks and goals; sound; sharing or exporting the crate; any penalty for unpicked tomatoes; a stored picking time; drawn bitmap assets.
