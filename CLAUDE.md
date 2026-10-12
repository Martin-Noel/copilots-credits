# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

macOS menu-bar app (SwiftPM, Swift 6 tools / Swift 5 language mode, macOS 13+) that shows GitHub Copilot "AI credits" consumption, including for company-provided Business/Enterprise seats. It relies on the **undocumented** endpoint `GET https://api.github.com/copilot_internal/user`. Everything in the repo (code comments, README, spec, test names, scripts) is in **English**; only the UI is bilingual.

## Commands

```bash
./test.sh                      # run all tests (preferred; output also tee'd to test.log)
./test.sh --filter UsageParser # single suite/test — args forwarded to `swift test`
swift test                     # what CI runs (works with full Xcode)

./build.sh                     # build/Copilot Credits.app (release, ad hoc signed)
./build.sh install             # + copy to /Applications, kill old instance and launch
./build.sh dmg                 # + build/CopilotCredits.dmg
UNIVERSAL=1 VERSION=0.2.0 BUILD_NUMBER=42 ./build.sh dmg   # same as CI

./scripts/make-tutorial.sh     # docs/tutorial.gif + build/tutorial/tutorial.mp4 (needs ffmpeg; `fr` arg for French UI)
```

`test.sh` exists because with Command Line Tools only (no full Xcode), SwiftPM may fail with `no such module 'Testing'` / missing macros; the script locates `libTestingMacros.dylib` and passes `-plugin-path`. If you hit that error with plain `swift test`, use `./test.sh`.

Tests use **Swift Testing** (`@Test`, `@Suite`, `#expect`), not XCTest.

## Architecture

Two targets, split by testability:

- **`CopilotCreditsCore`** (library, links `sqlite3`) — pure logic, no network/UI: `UsageParser` (JSON → `UsageSnapshot`), `UsageSnapshot` computed values (pace, linear projection, daily budget), `AlertPolicy` (which threshold to notify), device-flow response interpretation, `CopilotCLIAccount` (picks the Copilot CLI keychain entry), `HistoryStore` (SQLite at `~/Library/Application Support/CopilotCredits/history.sqlite`). Only this module is tested.
- **`CopilotCredits`** (executable) — thin I/O + UI shell. `UsageStore` (`@MainActor ObservableObject`) is the central state machine: `loggedOut → awaitingDevice → ready`, polls every 10 min + on wake + on demand, writes each snapshot to history, fires threshold notifications (once per threshold per cycle, tracked in `UserDefaults` keyed by reset date). `Views.swift` is the SwiftUI panel + Swift Charts graph; `CopilotCreditsApp.swift` is the `MenuBarExtra` entry point.

Key domain facts (non-obvious):
- AI credits are read **only** from `quota_snapshots.premium_interactions` (legacy name). Used = `entitlement − quota_remaining` (+ `overage_count`); use `quota_remaining` because it keeps decimals, `credits_used` is rounded.
- Auth is OAuth device flow with the **official Copilot plugin client ID** (`DeviceFlow.clientID`) — `copilot_internal` rejects tokens from any other OAuth app. Don't change it.
- Token sources, in order: app keychain item (`fr.martinnoel.copilot-credits` / `github-oauth-token`), then env `GH_COPILOT_TOKEN`. Fallback import from the Copilot CLI keychain (service `copilot-cli`, account `https://github.com:<login>`) for orgs that block OAuth.
- UI is bilingual FR/EN. Every user-facing string in the app target goes through `tr("français", "English")` (`Localization.swift`); numbers/dates are formatted with `L10n.locale` / `L10n.percent` / `L10n.credits`, not the bare `.formatted()` (which ignores the in-app language choice). The choice (`system`/`fr`/`en`, default system → French if the preferred macOS language is French, else English) lives in `UserDefaults` key `appLanguage`; `UsageStore.language` setter fires `objectWillChange` so the panel re-renders live. Core error `errorDescription`s are English only; the app translates them in `L10n.message(for:)`.
- App only talks to `github.com` / `api.github.com`; no telemetry — keep it that way.
- All HTTP goes through `CopilotAPI.session` (ephemeral, no disk cache/cookies). Never use `URLSession.shared`: it cached the OAuth token response in clear under `~/Library/Caches/<bundle id>/Cache.db`.

## Tutorial GIF

`Sources/CopilotCredits/Tutorial.swift` (`#if DEBUG` only) renders the README GIF from the real views with fake data: `CopilotCreditsApp.init` intercepts `--render-tutorial <dir>`, and `UsageStore.init(tutorialPhase:…)` builds a fake state with no Keychain/network. Frames are drawn in an offscreen-but-ordered-in window with `NSApplication.isActive` swizzled to true — otherwise AppKit draws buttons/progress bars greyed out. Click targets are hardcoded points; if the panel layout changes, re-check frames. Regenerate the GIF after any visible UI change.

## Spec-first testing workflow

Tests in `Tests/CopilotCreditsCoreTests/` were written **from `Tests/SPEC.md` alone**, by someone who hadn't seen the implementation. To change behavior of the Core module: **update `SPEC.md` first, then the test, then the code.** Don't adapt tests to match the implementation. (SPEC.md references an `INTERFACES.swift` that is not in the repo; the public signatures live in `Sources/CopilotCreditsCore/`.)

## CI / release

`.github/workflows/build.yml` runs `swift test` then `UNIVERSAL=1 build.sh dmg` on macOS; no DMG if tests fail. Version comes solely from the git tag: pushing `vX.Y.Z` creates a GitHub Release with `CopilotCredits.dmg` (filename kept constant so `/releases/latest/download/CopilotCredits.dmg` always works). The app is ad hoc signed, not notarized.
