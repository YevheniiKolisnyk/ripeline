# Ripeline

A native macOS menu bar app for the Pomodoro technique.

At the start of the day you pick a preset (for example 50 min work / 10 min break /
45 min long break) and describe your day. Ripeline generates a fixed plan of work and
break segments, walks you through it, and records what actually happened. Two timelines
on a shared time axis show the plan and the reality side by side.

> **Status:** early development. Stage 1 (domain logic in the `RipelineCore` package) is
> implemented and tested. There is no app UI yet.

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

To build the app (once the Xcode project exists), copy the local configuration template
and fill in your own team ID and bundle identifier:

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

`Config/Local.xcconfig` is gitignored.

## Documentation

- [SPEC.md](SPEC.md) — product and domain specification
- [CLAUDE.md](CLAUDE.md) — project conventions for contributors and coding agents

## License

[MIT](LICENSE)
