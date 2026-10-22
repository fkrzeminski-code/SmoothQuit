# SmoothQuit 1.6.3 review

Reviewed on 2026-10-22 using Ponytail Full and apple-hig-review. This is a bounded source, test and native UI audit, not a guarantee that every app or macOS configuration is bug-free.

## Findings fixed

| Finding | Change | Verification |
| --- | --- | --- |
| A successful AXWindows read could be lost if the subsequent main/focused-window read threw. A later snapshot could omit an identity the monitor had already encountered. | Seed each discovered identity immediately in both regular and final verification reads. Keep throwing on incomplete data; keep exact-destruction removal. | Regression injects failure at both supplemental attributes and checks that an omitted window continues to veto Quit. |
| Include mode displayed active monitoring when every listed app was protected or marked Never quit. | Derive status from the same effective rule policy used by the engine. | Tests cover protected Finder, Never rules, explicit allow and Exclude mode. |
| Search could leave a selected rule hidden while Edit/Remove remained available. | Clear selection when its identity leaves the filtered list; resolve all actions against visible rules. | Packaged app: select TextEdit, filter for Safari, confirm Edit and Remove disabled. |
| Adding an existing Bundle ID produced no explanation; adding self could show an error behind the sheet. | Inline explanation and disabled Add for duplicates and self. | Both cases verified in the packaged native sheet. |
| Launch-at-login approval state could remain stale after returning from System Settings. | Refresh native service status on activation/reopen, without resetting healthy AX observers. | Shared call path reviewed; actual login/reboot/approval flow not exercised. |
| Stored duplicate rule IDs and out-of-range custom delays could confuse list identity and sliders. | Keep the first effective rule and clamp persisted delay values. | Persistence regression verifies identity, precedence and both delay bounds. |

## Design review

**Good.** The design's purpose is to make a background utility's behavior understandable with a small number of native controls. The original open orbit is the signature; the rest stays quiet. Keep the three preference panes, standard sheets, real app icons, semantic colors, system typography and native menu. This review did not add decorative glass, another navigation layer or a new animation.

- `settings.md > Desktop (macOS)`: “use a noncustomizable toolbar” — retained the native preference toolbar, pane titles and standard window controls. [Apple Settings guidance](https://developer.apple.com/design/human-interface-guidelines/settings).
- `layout.md > Visual hierarchy`: “Use progressive disclosure” — Advanced and individual app rules remain disclosed on demand. The duplicate-ID explanation appears at the point of entry. [Apple Layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout).
- `motion.md > Providing feedback`: “Aim for brevity and precision” — the existing 0.6 s turn only acknowledges intentional Enable/Disable; automatic state refresh remains still. [Apple Motion guidance](https://developer.apple.com/design/human-interface-guidelines/motion).
- `color.md > System colors`: “Avoid hard-coding system color values” — native semantic foregrounds and surfaces remain in use. No new fixed UI palette. [Apple Color guidance](https://developer.apple.com/design/human-interface-guidelines/color).

The reviewed package displayed correct version/build information, a coherent rule sheet with and without custom delay, and clear duplicate/self feedback. Escape dismissed the rule sheet. Hiding the status item and closing Settings left the same process running; opening the installed copy through Finder reopened the review copy's Settings without leaving a second instance. Temporary rules and menu visibility changes were restored.

Light/dark, regular/compact renders are synthetic fixtures. Live UI inspection was in the user's dark appearance. This is not a measured contrast or complete VoiceOver/keyboard-only certification, nor an Increase Contrast / Reduce Transparency system-setting test. Native semantic controls are retained, and reduced-motion behavior has a deterministic regression check.

## Verification

- Ordinary suite: **72 tests, 64 passed, 8 interactive cases skipped, no failures**. Opt-in scenarios run separately are listed below.
- Native compositor: **+360° and −360°**, rapid state changes, **0.0 pt measured center drift**; 86 samples per turn. Native menu countdown and Settings close/reopen tests passed separately.
- Production Monitor: two-window veto, Disable during a pending countdown, and a newly opened window cancelling a 2 s countdown all passed with disposable TextEdit windows.
- Read-only AX checks passed for running Finder, Safari and Preview; these are not new full Quit tests for those apps.

| Controlled app test | Quit request after AX close | Observed process exit after AX close |
| --- | --- | --- |
| TextEdit, empty document | 0.585 s | 0.611 s |
| Calendar, main window | 0.570 s | 0.601 s |
| WhatsApp, main window | 0.593 s | 6.275 s |
| Excel, new empty Book1 | 0.597 s | 0.753 s |

The configured delay was 0.5 s. WhatsApp's extra shutdown time occurred after the normal Quit request; SmoothQuit did not wait six seconds before sending it and did not force termination. No conversations or existing workbooks were opened or changed.

The production Monitor tests ran in the authorized XCTest host. The candidate `.app` was separately exercised for its UI, lifecycle and real GitHub update check; it did not have a new Accessibility grant. Do not interpret this as a target-app Quit test from the final signed bundle.

### Failed and inconclusive attempts

An initial two-window fixture expected two AX identities before observation began, but TextEdit exposed only its main window. The subsequent combined scenario correctly vetoed Quit for a remembered window, then timed out because UI automation could not return to the remaining window. The fixture was split into independent scenarios and all three completed. One earlier TextEdit run received an exit receipt and the process disappeared, but asserted against a stale NSRunningApplication object. The test now re-queries the PID and the repeat passed. Apple's documentation describes time-varying properties updating with the main run loop: [NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication).

A temporary unbundled UI fixture could not be addressed by the computer-control tool. It was stopped and removed; packaged UI testing replaced it. None of these attempts is counted as a passing test.

## Ponytail review and remaining limits

All callers of window discovery were traced: initial discovery, event refresh, verification, final pre-Quit verification and read-only inspection. One discovery callback and the shared seed helper fix the loss at its source; inspection remains read-only. No dependencies, per-app heuristics, polling, private API, interception or forced termination were added. Existing event fences, process checks, budgets and configured delay remain intact. UI fixes reuse the existing model, native controls and persistence.

Public Accessibility implementations can omit windows or notifications. The ledger protects identities actually observed; it cannot prove the existence of a window never exposed by any public source. Actual Spaces switching, multiple displays, fullscreen, unsaved-document cancellation, older macOS and physical Intel hardware were not newly tested. Very early closes before observation is ready can still leave an app running. Ad hoc signing can still require Accessibility to be re-added after replacement. See [Safety](SAFETY.md) and [Testing](TESTING.md).
