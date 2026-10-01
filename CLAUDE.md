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
├── Ripeline.xcodeproj/          # hand-written; folder-synchronized groups (new files are picked up)
├── App/                         # menu bar app target
│   ├── Resources/               # Localizable.xcstrings (en + uk), PrivacyInfo.xcprivacy, Assets
│   └── Ripeline.entitlements    # only com.apple.security.app-sandbox
├── AppTests/                    # app unit tests (Swift Testing), hosted in the app
├── Config/
│   ├── Shared.xcconfig          # committed: shared build settings
│   ├── Local.example.xcconfig   # committed template
│   └── Local.xcconfig           # gitignored: DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER
├── scripts/test-app.sh          # quiet xcodebuild test wrapper
├── docs/specs/, docs/plans/     # design specs and implementation plans, one per sub-project
└── Packages/
    └── RipelineCore/            # domain logic, Swift package (stage 1)
        ├── Package.swift
        ├── Sources/RipelineCore/
        └── Tests/RipelineCoreTests/
```

The app (stage 2) is built in sub-projects 2a (shell and runtime), 2b (day setup), 2c (day
screen) and 2d (history); see `docs/specs/`.

## Commands

```sh
# Run all tests
swift test --package-path Packages/RipelineCore

# Run one suite or test
swift test --package-path Packages/RipelineCore --filter PlanGeneratorTests

# Build only
swift build --package-path Packages/RipelineCore

# App unit tests (all, or one suite). Prints only errors, warnings and the result.
scripts/test-app.sh
scripts/test-app.sh SessionControllerTests
```

A fresh clone builds and tests without `Config/Local.xcconfig` (ad-hoc signing, placeholder
bundle id). Tests are hosted inside the app, so the app builds an inert environment under
XCTest and must never touch real user data or the notification center from a test.

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
