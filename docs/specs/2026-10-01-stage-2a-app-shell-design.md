# Stage 2a — App shell and runtime: design

Status: implemented. Parent spec: [`SPEC.md`](../../SPEC.md). Builds on `RipelineCore` (stage 1).

## 1. Goal

A working menu bar app, `Ripeline.app`, that hosts `RipelineCore`'s `SessionEngine`:
it ticks, survives sleep and relaunch, signals the end of a segment with a notification
and sound, and shows the current state in the menu bar and a popover. The screens that let
the user design a day and review it come in later sub-projects.

**Success criteria**

1. A fresh clone builds and tests with `xcodebuild` without any local configuration; with
   `Config/Local.xcconfig` it signs with the developer's own team and bundle id.
2. Start a day, quit and relaunch (or sleep the Mac): the day continues exactly where it
   was, with the elapsed time accounted for.
3. When a segment ends, a notification with sound appears, even if the app's timer ran late.
4. The app runs inside the App Sandbox with only `com.apple.security.app-sandbox`, uses
   public APIs only, collects nothing and makes no network calls.
5. All user-facing text is in the String Catalog (`en`, `uk`).

## 2. Decomposition of stage 2

| Sub-project | Scope |
|---|---|
| **2a (this spec)** | Xcode project, config, sandbox, localization, menu bar, runtime (ticking, sleep/wake, persistence, notifications), minimal popover with a temporary quick-start. |
| 2b | Day setup screen: preset, mode, long break, remainder strategy, plan preview. Replaces the quick-start. |
| 2c | Day screen: planned and actual timelines on a shared axis, lag indicator, plan-vs-actual summary, session settings UI. |
| 2d | History: list of past days and comparison. Reads the per-day files 2a writes. |

Each sub-project gets its own spec, plan and pull request.

## 3. Decisions

| # | Decision | Chosen by |
|---|---|---|
| S1 | The Xcode project is a hand-written, committed `.xcodeproj` using folder-synchronized groups. No project generator. | user |
| S2 | The menu bar item shows an icon plus the live remaining time; a setting hides the time and leaves only the icon. Default: shown. | user |
| S3 | End of a segment: a system notification with sound via `UserNotifications`. | user |
| S4 | Each day is stored as its own file; history UI is a later sub-project (2d). | user |
| S5 | Architecture: one `@MainActor @Observable SessionController` owns the engine and its collaborators, injected through protocols. | user |
| S6 | Idle state offers a temporary "Start day" with a fixed default plan until 2b exists. | proposed, part of this design |

## 4. Project and build

```
Ripeline.xcodeproj           hand-written; folder-synchronized groups
App/                         app target sources
  Resources/Localizable.xcstrings   en (base) + uk
  Resources/Assets.xcassets
  Resources/PrivacyInfo.xcprivacy
  Ripeline.entitlements
AppTests/                    app unit tests (Swift Testing)
Config/
  Shared.xcconfig            committed; all shared build settings
  Local.example.xcconfig     committed template
  Local.xcconfig             gitignored: DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER
Packages/RipelineCore        local package dependency
```

- `Shared.xcconfig` sets `MACOSX_DEPLOYMENT_TARGET = 26.0`, Swift 6 language mode,
  `SWIFT_STRICT_CONCURRENCY = complete`, App Sandbox and Hardened Runtime on, a default
  `PRODUCT_BUNDLE_IDENTIFIER = com.example.Ripeline`, ad-hoc signing, and ends with
  `#include? "Local.xcconfig"`, which overrides bundle id and team when present.
- `LSUIElement = YES` (no Dock icon). App Store category: Productivity.
- Entitlements: only `com.apple.security.app-sandbox`. No network, no file access outside
  the app's own container. `UserNotifications` and `NSWorkspace` wake notifications need no
  entitlement.
- `PrivacyInfo.xcprivacy`: no tracking, no collected data types, `UserDefaults` accessed with
  reason `CA92.1`.
- String Catalog: development language `en`, plus `uk`; plural variations where a count is shown.
  No user-facing string literals in code. Keys are semantic (`session.pause`).
- Only APIs available on macOS 26 are used even though the installed SDK is newer.

Commands (also recorded in `CLAUDE.md`):

```sh
swift test --package-path Packages/RipelineCore
xcodebuild test -project Ripeline.xcodeproj -scheme Ripeline -destination 'platform=macOS'
```

## 5. Runtime

Everything app-side runs on `@MainActor`. `RipelineCore` stays pure.

### 5.1 SessionController

`@MainActor @Observable final class SessionController`. Owns a `SessionEngine` and receives
its collaborators through initializer parameters: `WallClock`, `DayStore`, `Notifier`,
`Ticker`, `AppSettings`.

- Exposes read-only state for the UI: current phase, current segment, `remaining`,
  `overtimeElapsed`, `now`, lag, and which actions are allowed.
- Exposes actions mirroring the engine: `startQuickDay()`, `start`, `pause`, `resume`,
  `extend(minutes:)`, `skip`, `advance`, `endDay`.
- After every action it: persists the snapshot, reschedules the pending notification, restarts
  or stops the ticker as needed, and refreshes the exposed state.
- `refresh()` calls `engine.tick()` and then does the same bookkeeping. It is called by the
  ticker, by wake and by system-clock changes. It is idempotent.

### 5.2 Ticker

A protocol with `start(handler:)` and `stop()`. The real implementation runs a `Task` that
sleeps one second and calls the handler. It runs only while a segment is running or in
overtime; there are no timers while idle, paused or finished. Correctness never depends on
the timer: all time comes from `Date`s, so a late or missed tick changes nothing but the
display.

### 5.3 DayStore

Protocol: load the most recent stored day, save a snapshot. `FileDayStore` is the
implementation.

- Location: `Application Support/Ripeline/days/YYYY-MM-DD.json` inside the sandbox container.
  The key is the local calendar date of the plan's first segment; a second day that starts on the same date is
  stored as `YYYY-MM-DD-2.json`, `-3`, … so it never overwrites the first (decision P12).
- Format: `{"version": 1, "snapshot": <SessionSnapshot>}`. Dates use the default
  (exact `Double`) encoding so restored instants keep full precision. Writes are atomic.
- Saved on every state change, not on every tick: a running segment is fully described by
  `endsAt`.
- A snapshot with an empty plan is never saved.
- A file that cannot be decoded or fails `SessionEngine(restoring:)` is renamed to
  `<name>.corrupt` and the app starts idle. It never crashes or blocks the UI.

### 5.4 Launch and new day

On launch: load the latest day, restore the engine, call `tick()`. If the restored day is
`finished`, or its date is before today, the controller starts from a fresh idle state; the
old file stays on disk for stage 2d. A day that started before midnight and is still
running stays active.

### 5.5 Notifier

A protocol over `UserNotifications`.

- When a segment is running, one local notification is scheduled for its `endsAt`, with the
  default system sound. Each segment has its own request id (the segment's id), so scheduling
  the next segment never replaces one that is due. A request is cancelled only when the user
  makes it obsolete before it is due (pause, skip, end of day); a request whose time has come is
  never cancelled or replaced, because it is firing right now. Because it is scheduled ahead of
  time it still fires if the timer is late.
- When catch-up (sleep, relaunch) crosses one or more segment ends, one immediate
  notification summarizes the current situation instead of one per missed segment.
- Text: work ended → "Time for a break"; break ended → "Back to work"; last segment ended →
  "Day finished". All through the String Catalog.
- Authorization is requested the first time a day starts, not at launch. If denied, the app
  works without notifications; the menu bar item still changes.
- The notification center delegate presents banner and sound even while the app is active.

### 5.6 WakeObserver

The only file that imports AppKit. Observes `NSWorkspace.didWakeNotification` and
`NSNotification.Name.NSSystemClockDidChange` and calls `controller.refresh()`.

### 5.7 AppSettings

`UserDefaults`-backed `@Observable`. Holds `showTimeInMenuBar` (default `true`) and a
`SessionSettings` value (defaults from the core). Stage 2c adds UI for the session settings.

### 5.8 Errors

Store and notification failures are logged with `os.Logger` (local only) and never block the
user.

## 6. UI

- `RipelineApp` (`@main`) declares a `MenuBarExtra` with the `.window` style.
- **Menu bar label:** an SF Symbol chosen by phase (work, break, paused, overtime, idle or
  finished) plus, unless hidden by `showTimeInMenuBar`, the time in monospaced digits:
  `m:ss`, `h:mm:ss` from one hour up, `+m:ss` in overtime. Formatting is locale-aware.
- **Popover:**
  - header: current segment kind and a large timer with a progress indicator;
  - actions shown according to `isAllowed`: Start, Pause / Resume, +5 min, Skip, Next (overtime
    only), End day, using the Liquid Glass button style;
  - idle: a "Start day" button that starts the temporary default plan (preset 50/10/45, net
    focus 240 minutes from now, no long break), replaced by the setup screen in 2b;
  - footer: the "Show time in menu bar" toggle and Quit.
- Accessibility: labels on every control; the timer's accessibility value is not updated
  every second.

## 7. Testing and verification

Unit tests in `AppTests` with a manual clock, an in-memory store, a recording notifier and a
manual ticker:

- restore on launch; stale and finished days start fresh; corrupt file is quarantined;
- a snapshot is saved after every action and not on ticks;
- notification scheduled on start, replaced on extend, cancelled on pause and end of day,
  rescheduled on resume;
- catch-up across several segments produces one summarizing notification;
- the ticker runs only while running or in overtime;
- menu bar text formatting, including overtime, hours and both locales;
- `FileDayStore` on a temporary directory: round trip, atomic replace, version field,
  corrupt file handling.

Verification before the PR: `swift test` and `xcodebuild test` green, a warning-free
`xcodebuild build` from a clean clone without `Local.xcconfig`, and launching the app to check
the menu bar item, popover, relaunch restore and the show-time toggle. Real notification
delivery is verified together with the developer on a signed build.

## 8. Risks

1. A hand-written `project.pbxproj` may not open or may be reformatted by Xcode. Mitigation:
   build and test from a clean clone; keep the project minimal.
2. The `MenuBarExtra` label might not redraw every second. Mitigation: verify by running; if
   needed, drive the label from an explicit observable `now`.
3. Notifications from an ad-hoc signed build can behave differently from a signed one.
   Mitigation: notification logic is behind a protocol and tested without the system; real
   delivery is checked on a signed build.
4. Newer SDK than deployment target. Mitigation: the deployment target is 26.0 and only APIs
   available there are used.

## 9. Out of scope for 2a

Day setup UI (2b); timelines, lag display, comparison and session settings UI (2c); history
(2d); final app icon (a placeholder is used); launch at login; global keyboard shortcuts; any
network, analytics or telemetry.

## 10. Decisions made during planning and implementation

| # | Decision |
|---|---|
| P1 | `App/Ripeline.entitlements` lives in `App/` and is excluded from the target's resources by a synchronized-group membership exception. |
| P2 | Under XCTest the composition root builds an inert environment (in-memory store, no-op notifier and ticker, throwaway defaults). The unit tests are hosted in the app, so otherwise they would read the real day and use the real notification center. |
| P3 | Timer text is plain integer math (`32:10`, `1:02:05`, `+2:15`), identical in `en` and `uk`. The countdown rounds up, so `0:00` appears only at expiry; overtime rounds down. |
| P4 | The immediate summary notification is sent only when a relaunch finds that segments ended while the app was closed. On wake the system delivers the already scheduled request. To be confirmed on a signed build. |
| P5 | No app icon asset in 2a; it needs artwork. |
| P6 | Controller actions that are not allowed are ignored and logged, not reported. |
| P7 | The store is written only when the snapshot changed since the last save, which keeps `refresh()` idempotent. |
| P8 | A file with a newer `version` is renamed `*.unsupported`; a corrupt file `*.corrupt`. Nothing is overwritten or deleted. |
| P9 | A stored day is stale if it is finished, or its last planned segment ended before the start of today. |
| P10 | No counts are shown in 2a, so the catalog has no plural variations yet. |
| P11 | The auto-generated `Ripeline` scheme is used. |
| P12 | A second day that starts on the same date is stored as `YYYY-MM-DD-2.json`, `-3`, …, found by the first segment's id, so it never overwrites the first. Without this a finished morning day would be lost when the user starts another one. |
| P13 | The catalog completeness test compares the compiled `en` and `uk` string tables from the app bundle; the hosted test runs in the sandbox and cannot read the source tree. |
| P14 | `WakeObserver` tests are serialized: every observer hears every wake and clock notification. |
| P15 | A segment's notification request is never cancelled or replaced once its time has come (found in review: cancelling on entry to overtime, or replacing under one shared id on auto-advance, could swallow the notification at the moment it should fire). |
| P16 | `FileDayStore` remembers which file each day lives in, and "latest" is the day that started last among the newest two dates, not the file whose name sorts last, so a change of time zone between launches cannot revert progress. Setting a damaged file aside never overwrites or deletes an earlier one (`.corrupt`, `.corrupt-2`, …), and one unreadable entry is skipped instead of hiding older days. |
