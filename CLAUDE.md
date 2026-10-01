# CLAUDE.md

Conventions for working in this repository. Read [SPEC.md](SPEC.md) first: it is the
source of truth for behavior. When a behavior decision is made or changed, record it in
the SPEC "Decisions log" in the same change.

## Project

Ripeline is a native macOS menu bar Pomodoro app. Swift 6 (strict concurrency),
SwiftUI, macOS 26+. Open source (MIT), intended for the Mac App Store.

## Repository structure

```
.
├── README.md, SPEC.md, CLAUDE.md, LICENSE
├── docs/plans/                  # implementation plans, one per stage
├── Config/
│   ├── Local.example.xcconfig   # committed template
│   └── Local.xcconfig           # gitignored: DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER
└── Packages/
    └── RipelineCore/            # domain logic, Swift package (stage 1)
        ├── Package.swift
        ├── Sources/RipelineCore/
        └── Tests/RipelineCoreTests/
```

The Xcode app project (menu bar UI, String Catalog, entitlements) arrives in stage 2.

## Commands

```sh
# Run all tests
swift test --package-path Packages/RipelineCore

# Run one suite or test
swift test --package-path Packages/RipelineCore --filter PlanGeneratorTests

# Build only
swift build --package-path Packages/RipelineCore
```

Tests must pass with zero warnings before a change is considered done.

## Hard rules

- **Public APIs only.** No private frameworks, SPI, or undocumented behavior.
- **App Sandbox.** Everything must work sandboxed. Add an entitlement only when a
  feature cannot work without it, and note why in the change.
- **No data collection.** No analytics, telemetry, crash reporters, or network calls.
- **No personal data in the repo.** Team ID and bundle identifier live only in
  `Config/Local.xcconfig`. Never commit names, emails, team IDs, or signing identities.
- **English** for all code, comments, docs, and commit messages.
- **Localization.** Every user-facing string in the app goes through the String
  Catalog (`en` + `uk`). No hardcoded user-facing strings. `RipelineCore` exposes no
  user-facing text at all: it returns values and enums, and the app formats and
  localizes them.

## RipelineCore rules

- Imports `Foundation` only. Never `SwiftUI`, `AppKit`, or `Combine`.
- Swift 6 language mode, strict concurrency. Public types are `Sendable`. Avoid
  `@unchecked Sendable` and `nonisolated(unsafe)`.
- Persistable models are `Codable`, `Sendable`, and `Equatable`.
- **Time is always derived from `Date`s** (`endsAt - now`), never by decrementing a
  counter. The current time comes from an injected clock, never from `Date()` or
  `Date.now` inside domain logic.
- The day plan is fixed once generated. Nothing recalculates it.
- Public API gets `///` doc comments.

## Testing

- Swift Testing only (`import Testing`, `@Test`, `#expect`, `#require`). No XCTest.
- Tests control time through a manual clock; no real waiting, no `sleep`.
- Build dates from a fixed calendar and time zone in tests so results do not depend on
  the machine's locale or time zone.
- Every behavior in SPEC.md has a test. A bug fix starts with a failing test.

## Git

- Default branch: `main`.
- Small, focused commits with imperative, descriptive messages.
