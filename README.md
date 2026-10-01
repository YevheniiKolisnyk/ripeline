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
> or behind you are, a plan-versus-actual summary and a table of segments. History of past days
> is next.

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

## Documentation

- [SPEC.md](SPEC.md) — product and domain specification
- [CLAUDE.md](CLAUDE.md) — project conventions for contributors and coding agents

## License

[MIT](LICENSE)
