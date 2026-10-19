# Testing

## Automated checks

```sh
swift test
```

The suite covers last-window gating, multiple windows, reopening/cancellation, off-Space identity retention, minimized/hidden and auxiliary windows, rules, invalid AX metadata, event bursts, process-specific event fencing and persisted settings. Interface checks cover settings-window reuse, launch/reopen behavior, menu visibility persistence, stable per-app bindings and light/dark rendering at regular and compact sizes.

Some integration checks read already-running Safari/Finder windows and subscriptions if the test host has Accessibility. They skip when that is unavailable. Two tests can send Quit and are **always skipped unless explicitly enabled**. The GitHub-hosted runner does not provide a usable interactive Safari/Finder AX session even when its trust check returns true. CI explicitly excludes the two read-only desktop checks; local `swift test` retains them. CI therefore runs 47 tests: 45 pass and the 2 Quit tests remain skipped. The initial CI run exposed this environment assumption; production window validation remains strict.

The local 1.4.0 run on macOS 27.0.1 / Xcode 27.1 passed **47 tests**, with **2 interactive tests skipped**, out of 49. The ordinary suite does not claim to prove real behavior of every app or every Space.

## Interactive tests (operator opt-in)

Use only apps/windows you are authorized to close, with disposable documents. Quit other automatic-quit utilities and other SmoothQuit instances first. Grant Accessibility to the test host yourself. These tests exercise the production `Monitor` and send normal Quit.

```sh
# Prepare ONLY empty/disposable TextEdit windows before starting.
SMOOTHQUIT_LIVE_TEXTEDIT=1 swift test --filter IntegrationTests/testLiveTextEditCloseAndQuit

# Operator opens the approved Mail main window or disposable Preview documents
# after the test prints LIVE READY. No messages should be opened or sent.
SMOOTHQUIT_LIVE_APP=com.apple.mail swift test --filter IntegrationTests/testLiveMailOrPreviewCloseAndQuit
SMOOTHQUIT_LIVE_APP=com.apple.Preview swift test --filter IntegrationTests/testLiveMailOrPreviewCloseAndQuit
SMOOTHQUIT_LIVE_APP=com.apple.iCal swift test --filter IntegrationTests/testLiveMailOrPreviewCloseAndQuit
```

SwiftPM can buffer XCTest output; running the built `.xctest` bundle with `xcrun xctest` gives the operator immediate READY messages. The TextEdit timeout is 45 seconds; Mail/Preview/Calendar allow 90 seconds.

## Recorded real-app results

These are **1.2 engine results from 2026-10-18**, not new end-to-end 1.3 app tests. Version 1.3 does not change `Monitor.swift` or `SmoothQuitCore/Policy.swift`.

| App | Scenario | Quit request | Process exit |
| --- | --- | ---: | ---: |
| Apple Mail | Cold-launch AX failures recovered; normal + auxiliary window destruction | 0.604 s | 1.058 s |
| Preview | First of two windows kept the app alive; last window + auxiliary closure | 0.605 s | 0.655 s |

Times start at the received window-destruction event; configured delay was 0.5 s. The production engine ran inside an authorized XCTest host. Two earlier Mail attempts failed before bounded startup recovery was corrected. Final packaged-app Quit was not claimed because its changed ad hoc identity needed a new Accessibility grant.

Earlier TextEdit success is historical, not a replacement for testing a new package. Safari and Finder have read-only AX/subscription coverage, not a successful Quit certification.

## Calendar investigation — 1.4.0

On 2026-10-19, two checks of the installed 1.3.1 app closed Calendar normally: Quit requests at 0.536 s and 0.527 s, process exits at 0.567 s and 0.558 s. The reported intermittent failure was not consistently reproducible.

An opt-in production-Monitor test then failed to observe a close after launch-time AX errors and a successful but empty AX list. During the next attempt, a visible WindowServer surface coexisted with an empty AX list; bounded discovery retries recovered one normal and one auxiliary window. That attempt reached its operator timeout before a close was performed. The final controlled test passed: Calendar received normal Quit at **0.601 s** and exited at **0.640 s**, with a configured 0.5 s delay. No calendar events were edited.

Version 1.4 reuses the existing bounded AX recovery schedule when AX reports zero windows but CG still reports a visible window. Discovery only seeds the identity ledger; it never arms Quit. There is no added delay in the confirmed-close countdown and no continuous polling. A window closed before it can be identified still cannot safely trigger Quit.

New automatic checks cover delayed discovery safety, English/Polish resource completeness and diagnostic placeholders, distinct menu states and Reduce Motion. The English UI was rendered in light and dark at both supported test sizes.

## Release and manual checks

The release script builds both architectures, checks the Mach-O deployment/SDK metadata, verifies the ad hoc signature and validates the DMG checksum. Inspect `Builds/<version>/Reports/`. Layout renders are test fixtures, not screenshots of private windows. They do not establish animation quality or permission behavior.

Packaged 1.3.1 UI smoke check on 2026-10-19: General and Applications were inspected in the running app. Enable off kept the process alive; menu visibility toggled and was restored; a temporary Bundle-ID rule exposed its per-app delay and was then removed. Closing settings and reopening the app with its menu icon hidden retained the same process. Explicit Quit terminated it. The new ad hoc app reported missing Accessibility, so this check did not claim a new target-app Quit test. Launch at login after relocation still needs checking from the installed copy.

For each packaged release, verify:

- Show in Menu Bar on/off; hidden-icon reopen returns to the same process.
- Closing settings keeps the process alive; explicit Quit exits it.
- Enable off cancels pending work while keeping the utility alive.
- Include/Exclude and selected-app edits; new app windows cancel countdown.
- New Accessibility grant after installing/replacing the exact app copy.
- One and multiple windows across Spaces, fullscreen, minimized and hidden states.
- A disposable unsaved document receives the target app's standard save handling.
- Launch at login from the installed path, including after relocation.

The complete live matrix across multiple displays, Spaces, fullscreen, unsaved documents, older macOS releases and Intel hardware has **not** been executed. Do not label those cases verified solely because the logical tests pass.
