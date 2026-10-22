# Testing

## Current review — 1.6.3 (2026-10-22)

See the [1.6.3 review](REVIEW-1.6.3.md) for fixed findings, design decisions, live timings, failed attempts and coverage limits. The ordinary suite contains 72 tests: 64 passed and 8 opt-in cases skipped on the review Mac. Native icon/menu/lifecycle checks and production-monitor tests ran separately; CI omits two desktop-dependent read-only checks.

The new TextEdit fixture exercises three independent, authorized scenarios. Prepare only an empty TextEdit document, temporarily disable any installed automatic-quit utility, and follow the `CANCEL READY` instruction. Never run these against personal documents.

```sh
SMOOTHQUIT_LIVE_CANCEL=multiple swift test --filter IntegrationTests/testLiveWindowVetoOrDisableDuringCountdown
SMOOTHQUIT_LIVE_CANCEL=disable swift test --filter IntegrationTests/testLiveWindowVetoOrDisableDuringCountdown
SMOOTHQUIT_LIVE_CANCEL=reopen swift test --filter IntegrationTests/testLiveWindowVetoOrDisableDuringCountdown
```

The first creates and closes a second empty window. The second disables the actual Monitor when it arms a countdown. The third uses a 2 s delay so the operator can close and immediately reopen a blank window. Each asserts that no Quit request occurs. These tests never launch apps or operate another app's controls themselves.

## Automated checks

```sh
swift test
```

The suite covers last-window gating, multiple windows, reopening/cancellation, off-Space identity retention, minimized/hidden and auxiliary windows, rules, invalid AX metadata, event bursts, process-specific event fencing and persisted settings. Interface checks cover settings-window reuse, launch/reopen behavior, menu visibility persistence, stable per-app bindings and light/dark rendering at regular and compact sizes.

Some integration checks read already-running Safari/Finder windows and subscriptions if the test host has Accessibility. They skip when that is unavailable. Tests that start the production Monitor or can send Quit are **always skipped unless explicitly enabled**. The GitHub-hosted runner does not provide a usable interactive Safari/Finder AX session even when its trust check returns true. CI explicitly excludes the two read-only desktop checks; local `swift test` retains them. Interactive Quit, menu tracking and compositor tests remain opt-in. The initial CI run exposed this environment assumption; production window validation remains strict.

The local 1.4.1 run on macOS 27.0.1 / Xcode 27.1 passed **47 tests**, with **3 interactive tests skipped**, out of 50. The ordinary suite does not claim to prove real behavior of every app or every Space.

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

An opt-in production-Monitor test then failed to observe a close after launch-time AX errors and a successful but empty AX list. During the next attempt, a visible WindowServer surface coexisted with an empty AX list; bounded discovery retries recovered one normal and one auxiliary window. That attempt reached its operator timeout before a close was performed. The final controlled test passed: Calendar received normal Quit at **0.601 s** and exited at **0.640 s**, with a configured 0.5 s delay. No calendar events were edited. After granting Accessibility to the final packaged 1.4.0 app, its own monitor also passed: normal Quit requested at **0.535 s**, process exited at **0.563 s**. The app ran from the release folder; the existing Applications copy was not replaced. Enable off/on and the English settings/menu labels were checked in the running app.

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

## Menu animation regression — 1.4.1

The previous check only verified animation presence and missed the visual defect. The old component was measured in a real native menu bar: its center moved by **3.4371 pt**, with an offset-and-return movement rather than a full turn.

The corrected production component was then tested in a native menu item and a magnified preview. Normal enable and disable completed **+360° / −360°**, with **0.0000 pt measured center drift**. Rapid state changes preserved a single continuous turn. The visual preview was also inspected at 5× slower playback; release timing is 0.6 s.

The opt-in regression test samples the actual Core Animation presentation layer, checks direction, full travel, center stability and completion. It passed for both directions and rapid changes (86–87 samples per case). It needs an unlocked Mac desktop, adds only its own temporary status item, and does not access other apps or require Accessibility:

```sh
SMOOTHQUIT_LIVE_ICON=1 swift test --filter InterfaceTests/testLiveMenuIconCompletesTurnsWithoutMovingOrReversing
```

The regular test verifies Reduce Motion, no initial animation, state artwork and rapid-change coalescing. No window-observation or Quit engine code changed in 1.4.1; Calendar results above belong to 1.4.0.


## Native settings and state feedback — 1.5.0

The window detection, safety fences, configured closing delay and normal Quit mechanism are unchanged. Changes in Monitor are limited to presenting decision summaries and avoiding a duplicate blocked-decision log.

The suite now contains 56 tests. New checks cover distinct monitoring states, finite versus indefinite suspension, exact remaining-time formatting, automatic UI updates on pause expiry, a countdown that updates only while its menu is open, automatic refreshes that do not interrupt an intentional turn, rule outcomes, rule removal with Undo/Redo and the distinction between a Quit request and process exit. English and Polish resource keys and format arguments are checked together.

The opt-in UI tests use only their own temporary native status item/menu; they do not start the production monitor or quit another app:

```sh
SMOOTHQUIT_LIVE_ICON=1 swift test --filter 'InterfaceTests/testLive'
```

The compositor test measures full turns in both directions, rapid changes and center stability. The menu tracking test keeps an actual NSMenu open, observes multiple remaining-time values and checks expiry while AppKit is running its tracking loop.

UI smoke checks covered the packaged app's three panes, pause/resume, indefinite Disable, app search and selection, a disposable TextEdit rule, per-app delay formatting and rule removal. TextEdit itself was not launched. The temporary rule was removed and the original settings were restored. The packaged app required a new Accessibility grant, so this release does not claim a new target-app Quit test. The installed Applications copy was not replaced. Light/dark regular and compact renders remain fixtures, not proof of a complete VoiceOver or multi-display audit.

Final local validation on 2026-10-20: **52 passed, 4 interactive tests skipped, 0 failures out of 56** in the ordinary suite. The two opt-in native UI tests passed separately: +360° / −360° and rapid turns with **0.0 pt center drift**, and the open menu displayed **0:03 → 0:02 → 0:01**, then the finished state. One earlier tracking attempt dismissed the menu after 1.36 seconds before expiry; the fixture now activates its own test application before tracking, and the focused reruns passed. The compiler emitted its x86_64/SDK 27 deprecation warning; the verified final binary retains a macOS 14 minimum deployment target for both architectures.


## Version, updates and menu ownership — 1.6.0

The update checker is tested with a URLProtocol fixture: no ordinary test calls GitHub or requests notification permission. Tests cover numeric version comparison (including 1.10 versus 1.9), equal/older releases, draft/prerelease and malformed metadata, mismatched or external release URLs, HTTP/rate-limit failures, manual checks with launch checks disabled, duplicate in-flight checks and suppressing automatic result delivery after opt-out. Additional tests cover per-attempt activity correlation, quick Never rules preserving mode/custom delays and bounded diagnostic reports.

Real production-Monitor tests on 2026-10-20, configured delay 0.5 seconds:

| App | Scenario | Result |
| --- | --- | --- |
| Calendar | Cold launch recovered from transient AX subscription errors; last normal window closed | Quit at 0.584 s; exit at 0.623 s |
| Mail | Main window closed, without selecting or sending messages | Quit at 0.590 s; exit at 1.127 s |
| Preview | Opened and closed only a generated disposable PDF while another document remained | Quit vetoed at 0.528 s; existing document and process preserved |

The first Preview test attempt failed its setup assertion because AX returned an empty list, then timed out. No Quit was sent. A separate read-only probe later saw the windows, and the repeated production test observed two normal windows, then one, and passed. The fixture now skips before monitoring if it cannot establish the required existing window. This documents an intermittent AX visibility limitation; the engine never treats an empty initial list as a close event.

The live native UI checks retain full-turn/pivot and menu-tracking coverage. The settings-window fixture also verifies that closing hides the utility, relinquishes active state and reopening shows the same window without stopping its model. macOS can decline programmatic activation for an unbundled XCTest process: the first fixture incorrectly assumed activation was guaranteed, and a filtered invocation initially omitted NSApplication bootstrap. Those fixture assumptions were corrected; the passing close/reopen check recorded activeBefore=false. It is not evidence that a CLI process can forcibly activate itself. Packaged UI checks remain necessary for human-driven menu ownership.

The packaged app showed version 1.6.0 (build 9), About/project/license links, and completed a real manual GitHub check with “No newer release is available.” A first launch check hit a connection error, displayed it without claiming to be current, and a later check succeeded. No newer public release existed during testing, so an actual system update banner/authorization prompt was not exercised; newer-version routing uses deterministic tests, and macOS notification delivery remains subject to user permission and Focus.

The new package still needs its own Accessibility grant after ad hoc signing. Target-app results above are from the authorized XCTest host running production Monitor, not a claimed end-to-end Quit from the final .app. Full Spaces/multi-display/fullscreen and login/reboot coverage is still incomplete.

The final ordinary suite contains **65 tests: 59 passed, 6 interactive tests skipped, 0 failures**. The six skipped cases are the three native UI tests, the TextEdit Quit test, the selectable Mail/Preview/Calendar Quit test and the Preview keep-existing-window fixture. Interactive checks above were run separately. None of the ordinary tests launches target apps, calls GitHub or requests notification access.

A final combined native UI rerun again measured complete icon turns and passed hide/reopen, but its popup was dismissed before the expiry observation. The tracking fixture now marks such an interrupted run inconclusive instead of treating a premature dismissal as a timer failure; a menu held for its full observation interval must still satisfy the countdown/expiry assertions. Earlier uninterrupted 1.6 tracking execution passed with 0:03 → 0:02 → 0:01 and completion.

## 1.6.1 — interaction patch (2026-10-20)

The ordinary suite passed: 65 tests, 6 interactive tests skipped, zero failures. The opt-in Settings lifecycle test passed separately and now asserts regular activation while Settings is open, accessory activation after close, and regular activation after reopening the same window. Its first run exposed an invalid fixture assumption: changing activation policy can clear `isHidden`; the test now checks the actual contract (window absent, application inactive, accessory policy). XCTest activation was declined by macOS, so that test does not establish foreground menu ownership.

In the packaged app, CUA opened the real SmoothQuit application menu with About, Check for Updates, Settings and Quit; Advanced expanded and collapsed through its accessible label, revealing the two existing window toggles. The red close button left process 49462 running. Coordinate input returned `noWindowsAvailable`, so clicking the blank portion of the header was not verified with a physical pointer; the label's full-width rectangular hit region was reviewed in source. The temporary build required Accessibility again; no target-app Quit tests were claimed for this patch. Existing window-monitor logic was unchanged.

Ponytail Full review: root cause fixed in the shared Settings presentation/close path, no foreground polling or focus hooks, native DisclosureGroup retained, no dependencies added.

## 1.6.2 — Calendar, WhatsApp and Excel investigation (2026-10-22)

The installed 1.6.1 had Accessibility, enabled automation and a 0.5 s delay. Its retained diagnostics showed confirmed normal-window closes followed by a window/ledger veto for Calendar, WhatsApp and Excel; Excel also returned AX cannotComplete (-25204). The read-only inspector reported an empty current list plus a remembered Calendar window. This is evidence of disagreement between discovery sources, not proof that an omitted window can safely be discarded.

A title-free opt-in AX inventory reproduced WhatsApp's AXWindows succeeding with zero entries while AXMainWindow and AXFocusedWindow each returned an AXStandardWindow. The fix adds those public references, observes the creation payload before AXWindows catches up, and preserves the strict destruction ledger. Two regression tests cover empty-list supplementation, duplicate identity removal, retention of a different Space's window, malformed payloads and AX failures that must not be hidden. The ordinary suite has 68 tests: 61 passed, 7 interactive tests skipped.

Real production-monitor tests, operated through CUA with the installed monitor disabled temporarily:

| App | Quit requested after close | Confirmed exit after close | Result |
| --- | --- | --- | --- |
| Calendar | 0.570 s | 0.600 s | Passed |
| WhatsApp | 0.578 s | 1.664 s | Passed |
| Excel, newly created blank Book1 | 0.567 s | 0.715 s | Passed |

No existing workbooks were opened or closed, and no WhatsApp conversations were opened or sent. Only the main Calendar window was closed. KVO termination confirmation was added after WhatsApp's process exited but the original workspace-based completion expectation timed out; the final WhatsApp test then passed in full. The Excel run preceded this completion-observation addition; its discovery and normal-Quit code matched the final behavior. The installed app's Enable setting was restored after the tests.

Earlier attempts are not counted as passes: the initial Calendar setup timed out; cold WhatsApp was closed before AX attachment recovered and timed out; another WhatsApp attempt exposed the empty AXWindows list; subsequent attempts requested Quit but timed out waiting for the missing exit notification. These failures led to the fixes above. Very fast closing before any usable AX observation is established remains a conservative no-Quit case. Actual switching across Spaces and preservation of unsaved Excel documents were not tested in this session. Existing simulated multi-Space and cancellation checks passed. Runtime testing used the production Monitor in XCTest, not a newly permissioned packaged .app. The final bundle is built and signature-verified without replacing /Applications.
