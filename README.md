# Ripeline

A native macOS menu bar app for the Pomodoro technique.

At the start of the day you pick a preset (for example 50 min work / 10 min break /
45 min long break) and describe your day. Ripeline generates a fixed plan of work and
break segments, walks you through it, and records what actually happened. Two timelines
on a shared time axis show the plan and the reality side by side.

> **Status:** early development. The domain logic (`RipelineCore`) and the app shell are
> implemented: a menu bar item and popover that run a day, keep it across relaunch and sleep, and
> notify when a segment ends, and a window where you choose a preset, the end of the day or your
> focus time, a long break and what to do with leftover time, and see the plan before you start.
> The same window shows how the day goes: planned and actual timelines on one axis, how far ahead
> or behind you are, a plan-versus-actual summary and a table of segments. A History tab lists the days
> you have recorded and shows any of them with the same timelines and summary; a day can be deleted.
> For a task you do not want to plan, "Quick start" in the popover starts a block of 25, 50 or 90 minutes at
> once; you can add five minutes or another block, and press "Done" when finished.
> Every work block is also a tomato that grows while you work (more when you work past the plan); pick it
> when the block is over and it drops into a crate in the History tab.

## Privacy

Ripeline collects no data and sends nothing anywhere. It has no analytics, no telemetry
and no network access. Everything stays on your Mac.

## Requirements

- macOS 26 or later
- Xcode 26 or later (Swift 6.2+)

## Building and testing

The domain logic lives in a local Swift package and is tested with Swift Testing:

```sh
swift test --package-path Packages/RipelineCore
```

The app has its own tests, run through a small wrapper around `xcodebuild`:

```sh
scripts/test-app.sh
```

To sign the app with your own team, copy the local configuration template and fill in your
team ID and bundle identifier (a fresh clone builds without it, using ad-hoc signing):

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

`Config/Local.xcconfig` is gitignored.

## Running the app

Ripeline lives in the menu bar and has no Dock icon: after it starts, look for a dashed circle at the
top right of the screen.

**From Xcode** (Xcode 26 or later): open `Ripeline.xcodeproj`, choose the `Ripeline` scheme and a
`My Mac` destination, and press ⌘R. A fresh clone runs without any setup (it is signed ad hoc); to sign
with your own team, fill in `Config/Local.xcconfig` first (see above).

**From the command line:**

```sh
xcodebuild build -project Ripeline.xcodeproj -scheme Ripeline -destination 'platform=macOS' -derivedDataPath build
open build/Build/Products/Debug/Ripeline.app
```

To try it quickly: click the icon, choose "Plan day…", pick a preset (or "Custom" with 1-minute work
and break) and "Net focus" of 15 minutes, press "Start day". The timer runs in the menu bar and the
popover; after a minute a segment ends and a notification arrives (allow notifications when asked; an
ad-hoc signed build may not be allowed to show them). Or skip the planning: pick a block length under "Quick start" and press "Start". The "Day overview…" link in the popover opens
the day screen with the planned and actual timelines. When a block is over, click its wiggling tomato
to pick it; open History to see the crate fill up. Quit from the popover ("Quit Ripeline"), or stop
the run in Xcode.

## Documentation

- [SPEC.md](SPEC.md) — product and domain specification
- [CLAUDE.md](CLAUDE.md) — project conventions for contributors and coding agents

## License

[MIT](LICENSE)
