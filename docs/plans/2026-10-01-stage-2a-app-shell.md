# Stage 2a — App Shell and Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working menu bar app, `Ripeline.app`, that hosts `RipelineCore`: it ticks, survives sleep and relaunch, signals the end of a segment with a notification and sound, and shows its state in the menu bar and a popover.

**Architecture:** One `@MainActor @Observable SessionController` owns a `SessionEngine` and receives its collaborators through protocols: `DayStore` (per-day JSON files), `Notifier` (`UserNotifications`), `Ticker` (1 s loop), `WallClock`, `AppSettings` (`UserDefaults`). Pure helpers (`TimerText`, `MenuBarLabelModel`, `PopoverActions`, `SignalContent`) hold all formatting and decisions so they are unit-tested without UI. The Xcode project is hand-written with folder-synchronized groups; its structure was verified by a throwaway spike (see Appendix A).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI `MenuBarExtra`, Observation, `UserNotifications`, AppKit only in `WakeObserver` and Quit, Swift Testing, `xcodebuild`.

**Spec:** [`docs/specs/2026-10-01-stage-2a-app-shell-design.md`](../specs/2026-10-01-stage-2a-app-shell-design.md). Parent: [`SPEC.md`](../../SPEC.md).

## Global Constraints

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`, zero warnings from our code.
- `MACOSX_DEPLOYMENT_TARGET = 26.0`; only APIs available on macOS 26 (the installed SDK is newer).
- Public APIs only. App Sandbox on; **entitlements: only `com.apple.security.app-sandbox`**. No network, no file access outside the container.
- The app collects and sends no data. `os.Logger` output stays local.
- No personal data in the repo: team ID and bundle id only in `Config/Local.xcconfig` (gitignored). A fresh clone must build and test without it.
- All code, comments, docs in English. Every user-facing string comes from `Localizable.xcstrings` with `en` (base) and `uk`.
- `RipelineCore` is not modified by this plan.
- Commit identity is already configured; **no Claude attribution** in commits or PR text; the user is the sole author.
- Tests: Swift Testing (`import Testing`). No real sleeping, no real notification center, no real `Application Support` in unit tests.
- App test command (always through the wrapper, which hides the noisy log): `scripts/test-app.sh [TestSuiteName]`. Core: `swift test --package-path Packages/RipelineCore`.

## Decisions where the spec is silent or this plan refines it (please confirm)

| # | Decision | Why |
|---|----------|-----|
| P1 | `App/Ripeline.entitlements` lives in `App/` and is excluded from the target's resources through a synchronized-group membership exception (verified by the spike). | Keeps the layout the spec describes. |
| P2 | Under XCTest the composition root builds an **inert** environment (in-memory store, no-op notifier and ticker). | The tests are hosted inside the app: without this, running tests would read the developer's real day file and talk to the real notification center. |
| P3 | Timer text is formatted by plain integer math (`32:10`, `1:02:05`, `+2:15`), not by a locale formatter. | The format is identical in `en` and `uk`; no locale dependency to get wrong. The countdown rounds up, so it shows `0:00` only at expiry; overtime rounds down. |
| P4 | The immediate summary notification (`deliverNow`) is sent only when a **relaunch** finds that segments ended while the app was closed. On wake the system delivers the already-scheduled request. | Avoids duplicate notifications. To be confirmed on a signed build; if wake loses the request, a summary on wake is a small follow-up. |
| P5 | No app icon asset in 2a. | It needs real artwork. Out of scope for the app shell; tracked for release preparation. |
| P6 | Controller actions swallow `SessionError` (and log it). | The UI offers only allowed actions, so an error means a stale click; showing an alert would be noise. |
| P7 | The store is written only when the snapshot changed since the last save. | Keeps writes to the few state changes; makes `refresh()` idempotent. |
| P8 | A stored file whose `version` is newer than this build understands is renamed `*.unsupported`, never overwritten or deleted. A corrupt file is renamed `*.corrupt`. | Never destroys user data on downgrade or damage. |
| P9 | A stored day is **stale** (start fresh) if it is `finished`, or if its last planned segment ended before the start of today. A day crossing midnight that is still planned stays active. | Refines spec §5.4 so an unstarted plan for today restores, and an old overtime is not resurrected the next morning. |
| P10 | No count is shown anywhere in 2a, so the catalog has no plural variations yet. | The spec asks for plural variations "where a count is shown". |
| P11 | The auto-generated `Ripeline` scheme is used; no shared scheme file. | The spike showed `xcodebuild test -scheme Ripeline` works with it. |

## Review Focus

1. **Tests touching real user data.** Hosted tests start the real app. The inert environment (P2) must be proven by a test, and nothing in `AppTests` may read or write the real `Application Support` or call `UNUserNotificationCenter`. *Tests in Tasks 8 and 9.*
2. **Day boundaries.** A day crossing midnight, a plan that ended yesterday, a changed time zone or DST change: the key comes from the injected calendar, the day stays active while its plan is still ahead, and a stale day never overwrites its own file. *Tests in Tasks 3 and 6.*
3. **Damaged or newer store files.** Corrupt JSON, truncated file, `version: 2`, a valid-JSON snapshot that fails `SessionEngine(restoring:)`: the app starts idle, keeps the bad file under a new name, and falls back to the previous valid day. *Tests in Tasks 3 and 6.*
4. **Rapid or repeated actions.** Double-clicking Pause/Resume, `refresh()` called twice at the same instant, wake and ticker firing together: at most one pending notification, no extra saves, no negative time. *Tests in Task 7.*
5. **Notifications unavailable.** Permission denied or the center failing must not crash or nag; the menu bar still reflects the state. *Covered by the `Notifier` protocol boundary (Task 5) and a controller test with a failing notifier (Task 7).*

---

## File Structure

```
Ripeline.xcodeproj/project.pbxproj          (Appendix A)
Config/Shared.xcconfig                      shared build settings
Config/Local.example.xcconfig               (modified)
scripts/test-app.sh                         quiet xcodebuild wrapper
App/
  RipelineApp.swift                         @main, MenuBarExtra
  AppEnvironment.swift                      composition root (live / inert)
  Ripeline.entitlements
  Resources/Localizable.xcstrings
  Resources/PrivacyInfo.xcprivacy
  Resources/Assets.xcassets/Contents.json
  Presentation/TimerText.swift              countdown / overtime formatting
  Presentation/Phase.swift                  Phase + SF Symbol mapping
  Presentation/MenuBarLabelModel.swift      what the menu bar item shows
  Presentation/PopoverActions.swift         which buttons the popover shows
  Persistence/DayStore.swift                protocol, StoredDay, DayStoreError
  Persistence/FileDayStore.swift
  Settings/AppSettings.swift
  Runtime/Ticker.swift                      protocol + TaskTicker
  Runtime/Notifier.swift                    protocol, SignalKind, SignalContent
  Runtime/SystemNotifier.swift              UserNotifications adapter
  Runtime/SessionController.swift
  Runtime/WakeObserver.swift                the only AppKit-observing file
  Views/MenuBarLabel.swift
  Views/PopoverView.swift
AppTests/
  Support/TestClock.swift, MemoryDayStore.swift, SpyNotifier.swift, ManualTicker.swift, Fixtures.swift
  SmokeTests.swift, LocalizationCatalogTests.swift, TimerTextTests.swift,
  PresentationTests.swift, FileDayStoreTests.swift, AppSettingsTests.swift,
  TickerTests.swift, NotifierTests.swift, SessionControllerRestoreTests.swift,
  SessionControllerActionTests.swift, SessionControllerBookkeepingTests.swift,
  WakeObserverTests.swift, AppEnvironmentTests.swift, PopoverActionsTests.swift
```

Test fixtures: `t(h, m, s)` is 2026-01-15 at that time, UTC, as in `RipelineCoreTests`; the preset is 50/10/45. `TestClock` is a `WallClock` backed by a `Mutex<Date>` with `set(_:)` and `advance(minutes:)`.

---

### Task 1: Project skeleton and configuration

**Files:**
- Create: `Ripeline.xcodeproj/project.pbxproj` (Appendix A, verbatim), `Config/Shared.xcconfig`, `App/RipelineApp.swift`, `App/Ripeline.entitlements`, `App/Resources/PrivacyInfo.xcprivacy`, `App/Resources/Localizable.xcstrings`, `App/Resources/Assets.xcassets/Contents.json`, `AppTests/SmokeTests.swift`, `scripts/test-app.sh`
- Modify: `Config/Local.example.xcconfig`, `CLAUDE.md`, `README.md`

**Interfaces — Produces:** a buildable app target `Ripeline` (module `Ripeline`) and a hosted test target `RipelineTests` (`@testable import Ripeline`, `import RipelineCore`).

`Config/Shared.xcconfig`:
```
MACOSX_DEPLOYMENT_TARGET = 26.0
SWIFT_VERSION = 6.0
SWIFT_STRICT_CONCURRENCY = complete
SWIFT_EMIT_LOC_STRINGS = YES
LOCALIZATION_PREFERS_STRING_CATALOGS = YES
ALWAYS_SEARCH_USER_PATHS = NO
ENABLE_APP_SANDBOX = YES
ENABLE_HARDENED_RUNTIME = YES
PRODUCT_BUNDLE_IDENTIFIER = com.example.Ripeline
CODE_SIGN_STYLE = Automatic
CODE_SIGN_IDENTITY = -
#include? "Local.xcconfig"
```
`Local.example.xcconfig` gains: `CODE_SIGN_IDENTITY = Apple Development` (commented: "set this together with DEVELOPMENT_TEAM").

`scripts/test-app.sh` runs `xcodebuild test -project Ripeline.xcodeproj -scheme Ripeline -destination 'platform=macOS' [-only-testing:RipelineTests/<arg>]` into a log in `$TMPDIR`, then prints only: the `** TEST SUCCEEDED/FAILED **` line, every `error:` and `warning:` line that is not Xcode-environment noise (`CoreDevice`, `CoreSimulator`, `appintentsmetadataprocessor`), and failing test names. Exit code is `xcodebuild`'s.

`App/RipelineApp.swift` for this task is the spike's hello `MenuBarExtra`. `PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, empty `NSPrivacyTrackingDomains` and `NSPrivacyCollectedDataTypes`, `NSPrivacyAccessedAPITypes` with `NSPrivacyAccessedAPICategoryUserDefaults` / reason `CA92.1`. `Localizable.xcstrings`: `sourceLanguage` `en`, one key `app.name` = "Ripeline" in `en` and `uk`.

- [ ] **Step 1: Failing test.** `AppTests/SmokeTests.swift`:
  ```swift
  import Testing
  import RipelineCore
  @testable import Ripeline

  struct SmokeTests {
      @Test func coreIsLinked() { #expect(SessionSettings().pausesCountAsRest) }
      @Test func appRunsInsideTheSandbox() {
          #expect(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
      }
  }
  ```
- [ ] **Step 2:** Run `scripts/test-app.sh` before the project exists → fails ("no such project").
- [ ] **Step 3:** Create all files above. Make the script executable.
- [ ] **Step 4:** Run `scripts/test-app.sh` → `** TEST SUCCEEDED **`, 2 tests, no warnings. If `APP_SANDBOX_CONTAINER_ID` is absent for a hosted test run, replace the second test with a check of the app's code-signing entitlement through `SecTaskCopyValueForEntitlement` and record a Ruling in the ledger.
- [ ] **Step 5:** Clean-clone check: `git clone . $TMPDIR/clone && cd $TMPDIR/clone && scripts/test-app.sh` → green without `Local.xcconfig`.
- [ ] **Step 6:** Update `CLAUDE.md` (repo structure with `App/`, `AppTests/`, `scripts/`, `docs/specs`; the app test command) and `README.md` (Building section for the app). Commit `Add Xcode project skeleton for the menu bar app`.

### Task 2: Presentation helpers and localization guard

**Files:**
- Create: `App/Presentation/TimerText.swift`, `Phase.swift`, `MenuBarLabelModel.swift`; `AppTests/TimerTextTests.swift`, `PresentationTests.swift`, `LocalizationCatalogTests.swift`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces — Produces:**
```swift
enum TimerText {
    /// Rounds up. 0.4 → "0:01", 1930 → "32:10", 3599.5 → "1:00:00", 3725 → "1:02:05". Negative clamps to 0.
    static func countdown(_ seconds: TimeInterval) -> String
    /// Rounds down, with a leading "+". 135.9 → "+2:15", 3725 → "+1:02:05".
    static func overtime(_ seconds: TimeInterval) -> String
}

enum Phase: Equatable, Sendable {
    case idle, working, onBreak
    case paused(onBreak: Bool)
    case overtime(onBreak: Bool)
    case finished
    var symbolName: String { get }        // SF Symbol, see table
    var labelKey: LocalizedStringResource { get }
}

struct MenuBarLabelModel: Equatable {
    let symbolName: String
    let text: String?                     // nil when the time is hidden or not applicable
    init(phase: Phase, remaining: TimeInterval?, overtimeElapsed: TimeInterval?, showTime: Bool)
}
```
Symbol table: idle `timer`, working `timer`, onBreak `cup.and.saucer.fill`, paused `pause.circle.fill`, overtime `exclamationmark.circle.fill`, finished `checkmark.circle.fill`.
`MenuBarLabelModel` text: working/onBreak/paused → countdown(remaining); overtime → overtime(overtimeElapsed); idle/finished → nil; `showTime == false` → nil always.

- [ ] **Step 1: Failing tests.**
  - `TimerTextTests`: `countdown`: 0→"0:00", 0.4→"0:01", 59→"0:59", 59.2→"1:00", 1930→"32:10", 3599.5→"1:00:00", 3600→"1:00:00", 3725→"1:02:05", -5→"0:00", 36000→"10:00:00". `overtime`: 0→"+0:00", 135.9→"+2:15", 3725→"+1:02:05".
  - `PresentationTests`: every `Phase` case has a non-empty symbol; the table above; `MenuBarLabelModel` for each phase with `showTime` true/false (working 1930 → "32:10"; paused 600 → "10:00"; overtime 135 → "+2:15"; idle/finished → nil text).
  - `LocalizationCatalogTests` reads `App/Resources/Localizable.xcstrings` through `#filePath` (`../App/Resources/…`), parses JSON, and asserts: `sourceLanguage == "en"`; every key has `localizations.en` and `localizations.uk` each with a non-empty `stringUnit.value` and state `translated`; `uk` differs from `en` for every key except `app.name`; no key is marked stale.
- [ ] **Step 2:** `scripts/test-app.sh` → fails to compile.
- [ ] **Step 3:** Implement. Add catalog keys with `en`/`uk`: `phase.idle` "No day started"/"День не розпочато"; `phase.working` "Work"/"Робота"; `phase.break` "Break"/"Перерва"; `phase.paused` "Paused"/"На паузі"; `phase.overtime` "Over plan"/"Понад план"; `phase.finished` "Day finished"/"День завершено". `labelKey` returns `LocalizedStringResource` for these keys.
- [ ] **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `Add timer text, phase and menu bar label model`.

### Task 3: FileDayStore

**Files:**
- Create: `App/Persistence/DayStore.swift`, `App/Persistence/FileDayStore.swift`, `AppTests/Support/MemoryDayStore.swift`, `AppTests/FileDayStoreTests.swift`

**Interfaces — Produces:**
```swift
struct StoredDay: Equatable, Sendable { let key: String; let snapshot: SessionSnapshot }   // key "YYYY-MM-DD"

enum DayStoreError: Error, Equatable { case emptyPlan }

@MainActor protocol DayStore {
    /// The most recent day that can be read. Damaged or newer-version files are set aside, then the next older day is tried.
    func loadLatest() throws -> StoredDay?
    /// Writes the snapshot under the key of its plan's first segment (local calendar date). Atomic.
    func save(_ snapshot: SessionSnapshot) throws
    /// Renames the day's file to `<key>.json.corrupt` so it is kept but no longer loaded.
    func quarantine(_ day: StoredDay) throws
}

@MainActor final class FileDayStore: DayStore {
    init(directory: URL, calendar: Calendar = .current, fileManager: FileManager = .default)
    static func defaultDirectory() throws -> URL     // Application Support/Ripeline/days
}
```
File content: `{ "version": 1, "snapshot": … }`, encoder `.prettyPrinted + .sortedKeys`, default (exact `Double`) date encoding.
`MemoryDayStore` (test double): dictionary by key, records `saved: [SessionSnapshot]`, `quarantined: [StoredDay]`, can be told to throw on load/save.

- [ ] **Step 1: Failing tests** (temp directory per test, deleted afterwards; a fixed UTC calendar unless stated):

| Test | Behavior |
|------|----------|
| round trip | save a snapshot, `loadLatest` returns `StoredDay(key: "2026-01-15", snapshot: same)` exactly (full `Date` precision, e.g. a start at 09:03:27.123) |
| file name and envelope | file `2026-01-15.json` exists; JSON has `"version" : 1` and a `snapshot` object |
| overwrite | saving twice leaves one file, containing the latest snapshot; no temp files left |
| creates directory | saving into a not-yet-existing directory creates it |
| latest of several | days 01-13, 01-15, 01-14 saved → `loadLatest` returns 01-15 |
| empty or missing directory | `loadLatest` → `nil` |
| empty plan | `save(.empty)` throws `.emptyPlan` and writes nothing |
| key follows the calendar | the same snapshot (plan starts 23:30 UTC) gets key 2026-01-15 with a UTC calendar and 2026-01-16 with a +03:00 calendar |
| corrupt file (Review Focus 3) | latest file is `{not json`: it is renamed `2026-01-15.json.corrupt`, and `loadLatest` returns the previous valid day (or `nil`) |
| truncated file | a valid file cut in half is handled like corrupt |
| newer version | `{"version": 2, …}` is renamed `*.unsupported`, content untouched, falls back to the older day |
| quarantine | `quarantine(day)` renames to `.corrupt`; the next `loadLatest` skips it |
| unreadable extra files | files that are not `YYYY-MM-DD.json` (e.g. `notes.txt`, `.DS_Store`) are ignored |

- [ ] **Step 2:** `scripts/test-app.sh FileDayStoreTests` → fails to compile.
- [ ] **Step 3:** Implement. Day files are listed, filtered by the `^\d{4}-\d{2}-\d{2}\.json$` pattern and sorted descending by name.
- [ ] **Step 4:** Run → PASS. Full suite → PASS.
- [ ] **Step 5:** Commit `Add file-based per-day store`.

### Task 4: AppSettings

**Files:**
- Create: `App/Settings/AppSettings.swift`, `AppTests/AppSettingsTests.swift`

**Interfaces — Produces:**
```swift
@MainActor @Observable final class AppSettings {
    init(defaults: UserDefaults = .standard)
    var showTimeInMenuBar: Bool          // default true
    var session: SessionSettings         // default SessionSettings()
}
```
Keys: `showTimeInMenuBar` (Bool), `sessionSettings` (JSON-encoded `SessionSettings` `Data`).

- [ ] **Step 1: Failing tests** (each test uses `UserDefaults(suiteName: UUID().uuidString)` and removes the domain afterwards): defaults are `true` and `SessionSettings()`; setting `showTimeInMenuBar = false` survives a new `AppSettings` on the same suite; `session` with `autoAdvanceWorkToBreak = true` survives; undecodable `sessionSettings` data → defaults, no crash; changing a value triggers Observation (use `withObservationTracking` and check the change handler fires once).
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement with `didSet` persisting. If `@Observable` rejects `didSet` on the stored properties, use `@ObservationIgnored` backing storage with explicit `access`/`withMutation` and record a Ruling.
- [ ] **Step 4:** Run → PASS. **Step 5:** Commit `Add app settings`.

### Task 5: Ticker and Notifier

**Files:**
- Create: `App/Runtime/Ticker.swift`, `App/Runtime/Notifier.swift`, `App/Runtime/SystemNotifier.swift`, `AppTests/Support/ManualTicker.swift`, `AppTests/Support/SpyNotifier.swift`, `AppTests/TickerTests.swift`, `AppTests/NotifierTests.swift`
- Modify: `App/Resources/Localizable.xcstrings`

**Interfaces — Produces:**
```swift
@MainActor protocol Ticker: AnyObject {
    var isRunning: Bool { get }
    func start(_ handler: @escaping @MainActor () -> Void)   // idempotent: a second start keeps one loop
    func stop()
}
@MainActor final class TaskTicker: Ticker {
    init(interval: Duration = .seconds(1),
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
}

enum SignalKind: Equatable, Sendable { case workEnded, breakEnded, dayFinished }

struct SignalContent: Equatable {
    let title: String
    let body: String
    init(kind: SignalKind, bundle: Bundle = .main)       // looks the strings up in `bundle`
}

@MainActor protocol Notifier: AnyObject {
    func requestAuthorization() async
    func schedule(_ kind: SignalKind, in interval: TimeInterval)   // replaces any pending request; interval floored at 1 s
    func cancelPending()
    func deliverNow(_ kind: SignalKind)
}
```
`SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate` uses one fixed request identifier (`ripeline.segment-end`), a `UNTimeIntervalNotificationTrigger`, `UNNotificationSound.default`, and a delegate `willPresent` returning `[.banner, .sound]`. Failures go to `os.Logger` and are otherwise ignored (Review Focus 5). It is a thin adapter and is not unit-tested; correctness of what it is told is tested through the controller.
Test doubles: `ManualTicker` (records `isRunning`, `start`/`stop` counts, has `fire()` that calls the handler if running); `SpyNotifier` records an ordered log of calls (`.authorize`, `.schedule(kind, interval)`, `.cancel`, `.deliver(kind)`), can be set to "fail" (no-op) to model denied permission.
Catalog keys (en / uk): `notification.workEnded.title` "Work block finished" / "Робочий блок завершено"; `.body` "Time for a break." / "Час на перерву."; `notification.breakEnded.title` "Break is over" / "Перерва закінчилась"; `.body` "Back to work." / "Час повертатися до роботи."; `notification.dayFinished.title` "Day finished" / "День завершено"; `.body` "Nice work!" / "Гарна робота!"

- [ ] **Step 1: Failing tests.**
  - `TickerTests` with a gated sleep (an `AsyncStream`-backed gate the test releases one beat at a time, so no real time passes): after `start`, the handler has not run; one beat → 1 call; two beats → 2; `stop()` → further beats do nothing and `isRunning == false`; `start` twice → still one call per beat; `start` after `stop` works again.
  - `NotifierTests` (`SignalContent`): for each `SignalKind` and each of `en`, `uk` (load `Bundle.main.path(forResource:"uk", ofType:"lproj")` as a bundle) title and body are non-empty, are not the raw key, and `en != uk`; the three kinds have different titles.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; full suite → PASS (the catalog test now also covers the new keys).
- [ ] **Step 5:** Commit `Add ticker and notifier abstractions`.

### Task 6: SessionController — restore, state and actions

**Files:**
- Create: `App/Runtime/SessionController.swift`, `AppTests/Support/TestClock.swift`, `AppTests/Support/Fixtures.swift`, `AppTests/SessionControllerRestoreTests.swift`, `AppTests/SessionControllerActionTests.swift`

**Interfaces — Consumes:** Tasks 2–5. **Produces:**
```swift
@MainActor @Observable final class SessionController {
    init(clock: any WallClock, store: any DayStore, notifier: any Notifier,
         ticker: any Ticker, settings: AppSettings, calendar: Calendar = .current)

    private(set) var now: Date
    var phase: Phase { get }
    var currentSegment: PlannedSegment? { get }      // running, paused or overtime segment
    var remaining: TimeInterval? { get }
    var overtimeElapsed: TimeInterval? { get }
    var progress: Double? { get }                    // 0...1 through the current segment; nil if none
    var scheduleStatus: ScheduleStatus? { get }
    func isAllowed(_ action: SessionAction) -> Bool

    func restore()                                   // call once at launch
    func startQuickDay() async                       // temporary default plan, see below
    func start(); func pause(); func resume()
    func extend(minutes: Int); func skip(); func advance(); func endDay()
    func refresh()                                   // tick + bookkeeping; idempotent
}
```
Quick-start plan: `DayPlanRequest(mode: .netFocus(start: clock.now, focusMinutes: 240), longBreak: .none, remainderStrategy: .leaveFree, preset: 50/10/45)` → generated, then `engine.startDay(plan:settings: settings.session)`, then `start()`. Allowed when idle-without-plan or finished. It requests notification authorization (`await notifier.requestAuthorization()`) before starting.
`phase` mapping: idle/no segment → `.idle`; finished → `.finished`; running → `.working` / `.onBreak` by the segment kind; paused/overtime carry `onBreak`.
Restore rule (P9): fresh idle if the stored day is `finished`, or its last segment ends before the start of today in the injected calendar. Otherwise `SessionEngine(restoring:)` then `tick()`. Failure of `restoring` → `store.quarantine(day)` then fresh idle; a throwing `loadLatest` → fresh idle.
Saving (P7): after every action, save only if `engine.snapshot` differs from the last saved one; never save an empty plan; a throwing `save` is logged and ignored.
Actions that are not allowed do nothing but log (P6).

- [ ] **Step 1: Failing tests, restore** (`TestClock`, `MemoryDayStore`, `SpyNotifier`, `ManualTicker`):

| Test | Behavior |
|------|----------|
| empty store | `phase == .idle`, no segment, nothing saved |
| running day | stored `running(0, endsAt 09:50)`, clock 09:20 → `phase == .working`, `remaining == 30 min` |
| elapsed while closed | same snapshot, clock 09:55, no auto-advance → `phase == .overtime(onBreak: false)`, `overtimeElapsed == 5 min` |
| finished day | stored finished → fresh idle; the store is **not** modified or quarantined |
| plan ended yesterday | stored overtime on a plan that ended 23:00 the previous day, clock next day 07:00 → fresh idle |
| crosses midnight | plan 22:00–02:00, state running, clock 00:30 → stays active (Review Focus 2) |
| unstarted plan for today | idle with plan today → restored with the plan |
| invalid snapshot | snapshot that fails `restoring` → `quarantine` called once, fresh idle |
| store throws | `loadLatest` throws → fresh idle, no crash |
| time zone | with a +03:00 calendar a plan at 22:00 UTC on 01-14 is "today" when the clock is 01-15 00:30 local |

- [ ] **Step 2: Failing tests, actions:**

| Test | Behavior |
|------|----------|
| quick start | `startQuickDay` → `phase == .working`, plan is 5 work blocks (50,50,50,50,40) with 10-min breaks, first segment ends at start + 50 min, saved exactly once, `requestAuthorization` called once |
| quick start when running | does nothing (not allowed), no extra save |
| pause / resume | pause at 09:20 → `.paused(onBreak:false)`, `remaining == 30 min` and unchanged as the clock moves; resume restores the countdown; each saves once |
| extend | `extend(minutes: 5)` while running adds 5 min to `remaining` |
| skip | skip at 09:20 → current segment is the break, previous `.skipped` in the stored snapshot |
| advance in overtime | after the clock passes the end (no auto-advance), `advance()` starts the next segment |
| end day | → `phase == .finished`; a following `startQuickDay` starts a new day |
| disallowed | `pause()` while idle: no change, no save, no throw |
| failing store | `save` throws: the action still takes effect |
| progress | at 09:25 into a 50-min segment `progress == 0.5` |
| lag | `scheduleStatus` mirrors `SessionEngine.scheduleStatus()` |
| rapid actions (Review Focus 4) | `pause(); pause(); resume(); resume()` at one instant: one pause and one resume applied, no negative time, saves only on actual changes |

- [ ] **Step 3:** Run → FAIL. **Step 4:** Implement (`now` is set from the clock after every action and in `refresh()`). **Step 5:** Run → PASS; full suite → PASS.
- [ ] **Step 6:** Commit `Add session controller with restore and actions`.

### Task 7: SessionController — notification, ticker and wake bookkeeping

**Files:**
- Modify: `App/Runtime/SessionController.swift`
- Create: `AppTests/SessionControllerBookkeepingTests.swift`

**Interfaces — Consumes:** Task 6. **Produces:** no new public API; `refresh()` and every action now also reconcile the notifier and the ticker.

Rules, applied after every action and in `refresh()`:
- **Notifier.** State `running(i, endsAt)` → `schedule(kind, in: endsAt − now)` with `kind = .dayFinished` if segment `i` is the last, else `.workEnded` for work and `.breakEnded` for breaks. Any other state (idle, paused, overtime, finished) → `cancelPending()`. Calls are made only when the desired request changed from the last one issued (compare kind and the target time), so `refresh()` is idempotent.
- **Ticker.** Running or overtime → ticker running (its handler calls `refresh()`); every other state → stopped. Starting an already running ticker or stopping a stopped one is avoided.
- **Restore summary (P4).** In `restore()`, if the engine's tick crossed one or more segment ends, call `deliverNow` **once** with the kind of the most recently ended segment (finished → `.dayFinished`; overtime of segment i → the kind of i; running segment j after a crossing → the kind of j−1). If nothing was crossed, none. Then apply the notifier rule above for the new state. `refresh()` and wake never call `deliverNow`.
- **Authorization.** `requestAuthorization()` is awaited from `startQuickDay` only, at most once per controller lifetime.

- [ ] **Step 1: Failing tests** (`SpyNotifier`, `ManualTicker`; the plan is work 50, break 10, work 50, break 10, work 50 from 09:00):

| Scenario | Expected notifier log / ticker |
|----------|-------------------------------|
| start at 09:00 | `schedule(.workEnded, in: 3000)`; ticker running |
| pause at 09:20 | `cancel`; ticker stopped |
| resume at 09:25 | `schedule(.workEnded, in: 1800)`; ticker running |
| extend +5 | `schedule(.workEnded, in: previous + 300)` |
| skip at 09:20 into the break | `schedule(.breakEnded, in: 600)` |
| last segment running | `schedule(.dayFinished, in: …)` |
| end day | `cancel`; ticker stopped |
| ordinary expiry (no auto) at 09:50 via `refresh()` | `cancel` (system request already fired); ticker keeps running (overtime); **no** `deliverNow` |
| advance from overtime | `schedule(.breakEnded, in: 600)` |
| auto-advance expiry | `schedule` for the new segment, no `deliverNow` |
| `refresh()` twice at the same instant | no additional notifier calls, no additional saves |
| ticker fires | `ManualTicker.fire()` triggers `refresh()` (observable through `now`) |
| relaunch crossing one end (restore at 09:55, overtime of work) | one `deliverNow(.workEnded)`, then `cancel` |
| relaunch crossing several ends with auto-advance (restore at 11:15, running 5th segment) | exactly one `deliverNow(.breakEnded)`, then `schedule(.workEnded…)` for the running segment |
| relaunch past the end of the day with auto-advance | one `deliverNow(.dayFinished)` |
| relaunch with nothing crossed | no `deliverNow` |
| authorization | two `startQuickDay` calls over one controller's life → one `.authorize` |
| notifications unavailable (Review Focus 5) | a `SpyNotifier` that ignores everything: all state transitions still work |

- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; full suite → PASS.
- [ ] **Step 5:** Commit `Add notification, ticker and restore-summary bookkeeping`.

### Task 8: WakeObserver and composition root

**Files:**
- Create: `App/Runtime/WakeObserver.swift`, `App/AppEnvironment.swift`, `AppTests/WakeObserverTests.swift`, `AppTests/AppEnvironmentTests.swift`
- Modify: `App/RipelineApp.swift`

**Interfaces — Produces:**
```swift
@MainActor final class WakeObserver {
    init(onWake: @escaping @MainActor () -> Void)    // observes NSWorkspace.didWakeNotification
                                                    // and NSNotification.Name.NSSystemClockDidChange
    func invalidate()                               // removes observers; also done in deinit
}

@MainActor final class AppEnvironment {
    let settings: AppSettings
    let controller: SessionController
    let isInert: Bool
    static func make(processEnvironment: [String: String] = ProcessInfo.processInfo.environment) -> AppEnvironment
}
```
`make` returns the **inert** environment when `XCTestConfigurationFilePath` is present in `processEnvironment` (P2): `MemoryDayStore`-like in-memory store, no-op notifier, inert ticker, a throwaway `UserDefaults` suite. Otherwise: `FileDayStore(directory: defaultDirectory())` (if the directory cannot be created, fall back to an in-memory store and log), `SystemNotifier`, `TaskTicker`, `UserDefaults.standard`, a `WakeObserver` wired to `controller.refresh()`, and `controller.restore()` called once.
`RipelineApp` holds the environment in `@State`, declares `MenuBarExtra { PopoverView(…) } label: { MenuBarLabel(…) }` with `.menuBarExtraStyle(.window)`. Until Task 9 the views are placeholders that render `controller.phase` and the time through `MenuBarLabelModel`.

- [ ] **Step 1: Failing tests.**
  - `WakeObserverTests`: posting `NSWorkspace.didWakeNotification` on `NSWorkspace.shared.notificationCenter` calls `onWake` once; posting `NSNotification.Name.NSSystemClockDidChange` on `NotificationCenter.default` calls it once; after `invalidate()` neither calls it; releasing the observer stops callbacks.
  - `AppEnvironmentTests` (Review Focus 1): `make(processEnvironment: ["XCTestConfigurationFilePath": "x"]).isInert == true`; the inert controller never reads or writes the real day directory (assert the real `defaultDirectory()` contents are unchanged around a `startQuickDay`); `make(processEnvironment: [:]).isInert == false` is **not** constructed in tests (it would touch real services); instead test the pure decision function `AppEnvironment.isRunningTests(_:)` with both inputs.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; full suite → PASS.
- [ ] **Step 5:** Build and launch the app once manually (`xcodebuild build`, then `open` the product) and confirm a menu bar item appears and the process is alive; quit it. Record in the ledger.
- [ ] **Step 6:** Commit `Add wake observer and composition root`.

### Task 9: Menu bar label and popover

**Files:**
- Create: `App/Presentation/PopoverActions.swift`, `App/Views/MenuBarLabel.swift`, `App/Views/PopoverView.swift`, `AppTests/PopoverActionsTests.swift`
- Modify: `App/RipelineApp.swift`, `App/Resources/Localizable.xcstrings`

**Interfaces — Produces:**
```swift
enum PopoverAction: Equatable, Sendable { case startDay, pause, resume, extend, skip, next, endDay }

enum PopoverActions {
    /// Buttons to show, in order, for the current phase, restricted to what the engine allows.
    static func visible(phase: Phase, isAllowed: (SessionAction) -> Bool) -> [PopoverAction]
}
```
Rules: idle and finished → `[.startDay]` (allowed when `startDay` is allowed); working/onBreak → `[.pause, .extend, .skip, .endDay]`; paused → `[.resume, .extend, .skip, .endDay]`; overtime → `[.next, .extend, .endDay]` (skip is hidden because it equals advance); each entry only if the matching `SessionAction` is allowed (`next` ↔ `.advance`, `startDay` ↔ `.startDay`).
Views: `MenuBarLabel` shows `Image(systemName:)` and, if `MenuBarLabelModel.text` is non-nil, `Text(text).monospacedDigit()`. `PopoverView`: header (`phase.labelKey` and, with a segment, the large timer from `TimerText`, plus a `ProgressView(value:)`), a button row built from `PopoverActions` with `.buttonStyle(.glass)` inside a `GlassEffectContainer`, a footer with a `Toggle` bound to `settings.showTimeInMenuBar` and a Quit button (`NSApplication.shared.terminate(nil)`). The timer text has an accessibility label (`a11y.timer`) and does not announce every second. Catalog keys (en / uk): `ui.startDay` "Start day" / "Почати день"; `ui.pause` "Pause" / "Пауза"; `ui.resume` "Resume" / "Продовжити"; `ui.extend` "+5 min" / "+5 хв"; `ui.skip` "Skip" / "Пропустити"; `ui.next` "Next" / "Далі"; `ui.endDay` "End day" / "Завершити день"; `ui.showTime` "Show time in menu bar" / "Показувати час у рядку меню"; `ui.quit` "Quit Ripeline" / "Вийти з Ripeline"; `a11y.timer` "Time left" / "Залишилось часу".

- [ ] **Step 1: Failing tests** (`PopoverActionsTests`): the table above for every phase with everything allowed; with only `{pause}` allowed while working → `[.pause]`; idle with `startDay` disallowed → `[]`; overtime hides skip; order is stable.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement the model and the views; add the catalog keys. **Step 4:** Run → PASS; full suite → PASS (the catalog test enforces `uk` for every new key).
- [ ] **Step 5:** Launch the app, open the popover, take a screenshot in `en` and `uk` (`-AppleLanguages '(uk)'`), and check: the menu bar item changes with the phase, the toggle hides and shows the time, buttons follow the phase. Record in the ledger.
- [ ] **Step 6:** Commit `Add menu bar label and popover`.

### Task 10: Documentation and end-to-end verification

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `docs/specs/2026-10-01-stage-2a-app-shell-design.md` (append "Decisions made during planning" with P1–P11), `SPEC.md` (stage table: 2a done, 2b–2d)

- [ ] **Step 1:** Update the docs listed above.
- [ ] **Step 2:** Run the whole verification and read the output: `swift test --package-path Packages/RipelineCore`, `scripts/test-app.sh`, a clean-clone `scripts/test-app.sh` (no `Local.xcconfig`), `xcodebuild build` warnings count = 0.
- [ ] **Step 3:** Run the app and check, by hand, with these steps recorded in the ledger: start a day; quit and relaunch (state restored, time continues); toggle show-time; let a short segment end (temporarily extend/skip as needed) and watch for the overtime icon.
- [ ] **Step 4:** Write a short **manual verification checklist for the developer's signed build** into the PR description: real notification delivery with sound, the permission prompt appearing once, behavior after sleeping through a segment end (P4), Liquid Glass appearance.
- [ ] **Step 5:** Commit `Document stage 2a`.

---

## Spec coverage check

| Spec section | Task |
|---|---|
| §1 success criteria 1, 4, 5 | 1, 2, 9, 10 |
| §1 criterion 2 (restore, sleep) | 6, 7, 8 |
| §1 criterion 3 (notification) | 5, 7 |
| §4 project and build | 1 |
| §5.1 SessionController | 6, 7 |
| §5.2 Ticker | 5, 7 |
| §5.3 DayStore | 3 |
| §5.4 launch and new day | 6 (refined by P9) |
| §5.5 Notifier | 5, 7 (refined by P4) |
| §5.6 WakeObserver | 8 |
| §5.7 AppSettings | 4 |
| §5.8 errors | 3, 5, 6, 7 |
| §6 UI | 2, 8, 9 |
| §7 testing and verification | every task; 8–10 for run-based checks |

---

## Appendix A — `Ripeline.xcodeproj/project.pbxproj` (verified by spike)

This exact file built, signed (sandbox entitlement present, `LSUIElement = true`, minimum OS 26.0) and ran a hosted Swift Testing test with `xcodebuild test` on a clone without `Local.xcconfig`. Use it verbatim in Task 1.

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		A10000000000000000000001 /* RipelineCore in Frameworks */ = {isa = PBXBuildFile; productRef = A10000000000000000000020 /* RipelineCore */; };
		A10000000000000000000002 /* RipelineCore in Frameworks */ = {isa = PBXBuildFile; productRef = A10000000000000000000021 /* RipelineCore */; };
/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
		A10000000000000000000030 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A10000000000000000000100 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = A10000000000000000000040;
			remoteInfo = Ripeline;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		A10000000000000000000050 /* Ripeline.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Ripeline.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A10000000000000000000051 /* RipelineTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = RipelineTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
		A10000000000000000000052 /* Shared.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Shared.xcconfig; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		A10000000000000000000060 /* Exceptions for "App" folder in "Ripeline" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Ripeline.entitlements,
			);
			target = A10000000000000000000040 /* Ripeline */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		A10000000000000000000070 /* App */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
				A10000000000000000000060 /* Exceptions for "App" folder in "Ripeline" target */,
			);
			path = App;
			sourceTree = "<group>";
		};
		A10000000000000000000071 /* AppTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = AppTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		A10000000000000000000080 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10000000000000000000001 /* RipelineCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000000000000000000081 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				A10000000000000000000002 /* RipelineCore in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		A10000000000000000000090 = {
			isa = PBXGroup;
			children = (
				A10000000000000000000070 /* App */,
				A10000000000000000000071 /* AppTests */,
				A10000000000000000000091 /* Config */,
				A10000000000000000000092 /* Products */,
			);
			sourceTree = "<group>";
		};
		A10000000000000000000091 /* Config */ = {
			isa = PBXGroup;
			children = (
				A10000000000000000000052 /* Shared.xcconfig */,
			);
			path = Config;
			sourceTree = "<group>";
		};
		A10000000000000000000092 /* Products */ = {
			isa = PBXGroup;
			children = (
				A10000000000000000000050 /* Ripeline.app */,
				A10000000000000000000051 /* RipelineTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		A10000000000000000000040 /* Ripeline */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000000000000000000110 /* Build configuration list for PBXNativeTarget "Ripeline" */;
			buildPhases = (
				A10000000000000000000082 /* Sources */,
				A10000000000000000000080 /* Frameworks */,
				A10000000000000000000083 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				A10000000000000000000070 /* App */,
			);
			name = Ripeline;
			packageProductDependencies = (
				A10000000000000000000020 /* RipelineCore */,
			);
			productName = Ripeline;
			productReference = A10000000000000000000050 /* Ripeline.app */;
			productType = "com.apple.product-type.application";
		};
		A10000000000000000000041 /* RipelineTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A10000000000000000000111 /* Build configuration list for PBXNativeTarget "RipelineTests" */;
			buildPhases = (
				A10000000000000000000084 /* Sources */,
				A10000000000000000000081 /* Frameworks */,
				A10000000000000000000085 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				A10000000000000000000031 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				A10000000000000000000071 /* AppTests */,
			);
			name = RipelineTests;
			packageProductDependencies = (
				A10000000000000000000021 /* RipelineCore */,
			);
			productName = RipelineTests;
			productReference = A10000000000000000000051 /* RipelineTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		A10000000000000000000100 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
				TargetAttributes = {
					A10000000000000000000040 = {
						CreatedOnToolsVersion = 27.0;
					};
					A10000000000000000000041 = {
						CreatedOnToolsVersion = 27.0;
						TestTargetID = A10000000000000000000040;
					};
				};
			};
			buildConfigurationList = A10000000000000000000112 /* Build configuration list for PBXProject "Ripeline" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				uk,
				Base,
			);
			mainGroup = A10000000000000000000090;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				A10000000000000000000022 /* XCLocalSwiftPackageReference "Packages/RipelineCore" */,
			);
			productRefGroup = A10000000000000000000092 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				A10000000000000000000040 /* Ripeline */,
				A10000000000000000000041 /* RipelineTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		A10000000000000000000083 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000000000000000000085 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		A10000000000000000000082 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A10000000000000000000084 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		A10000000000000000000031 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = A10000000000000000000040 /* Ripeline */;
			targetProxy = A10000000000000000000030 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		A10000000000000000000120 /* Debug */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = A10000000000000000000052 /* Shared.xcconfig */;
			buildSettings = {
				SDKROOT = macosx;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
			};
			name = Debug;
		};
		A10000000000000000000121 /* Release */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = A10000000000000000000052 /* Shared.xcconfig */;
			buildSettings = {
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
			};
			name = Release;
		};
		A10000000000000000000122 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_NAME = "$(TARGET_NAME)";
				GENERATE_INFOPLIST_FILE = YES;
				CODE_SIGN_ENTITLEMENTS = App/Ripeline.entitlements;
				INFOPLIST_KEY_LSUIElement = YES;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
				CURRENT_PROJECT_VERSION = 1;
				MARKETING_VERSION = 0.1.0;
				ENABLE_PREVIEWS = YES;
			};
			name = Debug;
		};
		A10000000000000000000123 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_NAME = "$(TARGET_NAME)";
				GENERATE_INFOPLIST_FILE = YES;
				CODE_SIGN_ENTITLEMENTS = App/Ripeline.entitlements;
				INFOPLIST_KEY_LSUIElement = YES;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
				CURRENT_PROJECT_VERSION = 1;
				MARKETING_VERSION = 0.1.0;
			};
			name = Release;
		};
		A10000000000000000000124 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_NAME = "$(TARGET_NAME)";
				GENERATE_INFOPLIST_FILE = YES;
				BUNDLE_LOADER = "$(TEST_HOST)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ripeline.app/Contents/MacOS/Ripeline";
			};
			name = Debug;
		};
		A10000000000000000000125 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_NAME = "$(TARGET_NAME)";
				GENERATE_INFOPLIST_FILE = YES;
				BUNDLE_LOADER = "$(TEST_HOST)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Ripeline.app/Contents/MacOS/Ripeline";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		A10000000000000000000110 /* Build configuration list for PBXNativeTarget "Ripeline" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10000000000000000000122 /* Debug */,
				A10000000000000000000123 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10000000000000000000111 /* Build configuration list for PBXNativeTarget "RipelineTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10000000000000000000124 /* Debug */,
				A10000000000000000000125 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A10000000000000000000112 /* Build configuration list for PBXProject "Ripeline" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A10000000000000000000120 /* Debug */,
				A10000000000000000000121 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		A10000000000000000000022 /* XCLocalSwiftPackageReference "Packages/RipelineCore" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/RipelineCore;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		A10000000000000000000020 /* RipelineCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = RipelineCore;
		};
		A10000000000000000000021 /* RipelineCore */ = {
			isa = XCSwiftPackageProductDependency;
			productName = RipelineCore;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = A10000000000000000000100 /* Project object */;
}
```
