# Window observation and safety

SmoothQuit favors leaving an app running over guessing that its windows are gone.

## Decision flow

1. `NSWorkspace` discovers eligible regular applications. Include/Exclude, per-app rules, pause, enable and self/system protection filter them.
2. `AXObserver` tracks creation and destruction. Reads run on one serial worker queue, away from the main UI thread. Every returned window identity enters a ledger before metadata is queried. The ledger removes an entry only after destruction of that exact element, never merely because it disappeared from a snapshot.
3. Destruction of a known normal window arms a token and monotonic deadline. An auxiliary window cannot arm a Quit. Its confirmed destruction may preserve an already armed deadline.
4. A new target-app window cancels pending Quit. Target structural events invalidate target decisions; Space changes, sleep/wake, settings updates and disabling invalidate globally. Ordinary focus changes and unrelated apps do not cancel a valid countdown.
5. At the deadline, AX must report no windows, the identity ledger must be empty, and CoreGraphics must not report a visible layer-zero window. Process identity, eligibility, Accessibility trust, queue lateness and read duration are checked again. A final AX read and event-revision check precede `NSRunningApplication.terminate()`.
6. The request is sent once. The app can show its standard save dialog, refuse termination, or take time to exit. The history distinguishes request and later observed exit.

The default delay is 0.5 seconds, configurable from 0.2 to 2 seconds. It begins at the received destruction event, not the mouse click. A late queue or slow verification cancels instead of adding an unreported multi-second close delay.

## Transient AX failures

Initialization/read failures classified as `cannotComplete` allow at most four recovery attempts, after 150, 350, 1000 and 2000 ms. Each attempt is logged. Finished-launching KVO provides another event-driven opportunity, but does not prove AX is ready. This is bounded recovery of observation, not polling and not an extra delay on final Quit verification. Unsupported or ambiguous states fail closed.

## Spaces and window types

There is no public API for an atomic, complete semantic snapshot of every Space followed by an atomic Quit. AX data depends on the other app's implementation. CoreGraphics surfaces are not equivalent to document windows; offscreen backing surfaces can remain after closure. Therefore on-screen CG information is only an additional veto, never the sole proof that nothing remains.

The identity ledger protects known off-Space windows even if a later AX snapshot omits them. Existing minimized, hidden, fullscreen, dialog and auxiliary windows veto Quit. Space switching, minimizing and hiding never arm it. Missing destruction events or persistent panels can leave an application running by design. The tiny interval between the last read and termination request cannot be eliminated with public APIs.

Finder is excluded by default, including in Exclude mode. Only an explicit per-app Always rule opts it in; persistent Finder auxiliary windows may still prevent termination. SmoothQuit always excludes its own PID and bundle identifier.

## Permissions and data

Only Accessibility is required. No screen recording, input monitoring, Apple Events automation entitlement, private CGS API, event tap, force quit or process signal is used. The app does not read window titles or document contents. Diagnostics contain a bundle ID, decision reason and timing, capped at 200 in-memory entries. Preferences use UserDefaults; installed-app discovery reads app bundle metadata. No runtime network calls or external dependencies.

Ad hoc signing is for local testing and does not give the release Developer ID trust or notarization. Replacing a build can invalidate Accessibility authorization. Prefer one installed copy in Applications and re-register launch at login there when relocating an installation.
