# Design and review — 1.4

SmoothQuit is a quiet background utility. Its settings should feel like Mac settings, with a small identity that remains recognizable in an 18-point menu bar slot.

## Identity

An open orbit and a dot at its closing gap suggest a gentle completion, with a loose Q silhouette. It is not a power symbol, a replica window control or a copy of another app's planet. `Brand.swift` defines the geometry once. The menu bar uses an AppKit template image; icon generation exports the same geometry into the app icon and SVG.

The app icon uses a native automatic gradient based on teal `#17A3A8`, with a white mark. Decorative brand colors do not encode operational state. UI controls use the user's native accent color, not a forced brand tint.

Version 1.3.1 ships a layered Icon Composer document (`Assets/AppIcon.icon`), created and checked in Apple’s tool after license acceptance. The system renders its glass, depth and appearance variants. `actool` compiles both `Assets.car` and the backward-compatible `.icns`; the SVG remains original vector artwork. The older standalone render script can regenerate the shared geometry as SVG.

## Native interface

- `NSTabViewController` supplies three noncustomizable preferences-toolbar panes and retained selection. The window title names the current pane. Standard window controls and Command-comma remain intact.
- SwiftUI grouped `Form` sections supply native margins, surfaces, dividers, switches and sliders. The large repeated brand header and custom list border were removed. Enable appears at the top of General; the app menu also exposes enable/disable.
- The UI uses system body/callout/headline text and monospaced digits only for timing. Semantic primary/secondary text, window/control backgrounds and system separators adapt to appearance and contrast. No fixed hex substitutes for system UI colors.
- Regular and compact layouts preserve the same three panes and use scrolling for longer settings. A persistent, quiet footer retains explicit Quit. Per-app rules remain behind selection; manual bundle-ID entry remains disclosed on demand.
- Menu artwork completes one centered 360° turn (0.6 s) when monitoring changes state. A dot marks active monitoring; pause bars mark inactive monitoring, including disabled, paused or missing Accessibility. Reduce Motion skips the transition. There is no repeating animation or idle timer. No decorative blur. Native controls supply feedback and respect system accessibility settings. Glass belongs to the system toolbar and interactive controls, not a stack of decorative content cards.
- The release build explicitly records the selected SDK rather than the deployment target as its linked SDK. This opts into current native rendering while keeping macOS 14 as the deployment target.

## HIG review

Reviewed with Ponytail Full, apple-hig-review and the transferable typography/feedback principles from apple-design-web. References read from Apple's HIG: accessibility, layout, typography, color, designing for macOS, settings, app icons, menu bar, toolbars and materials.

- `settings.md › Desktop (macOS)`: “use a noncustomizable toolbar” — keep the existing AppKit preferences controller instead of adding an unnecessary navigation layer.
- `color.md › System colors`: “Avoid hard-coding system color values” — semantic platform colors are used for UI. Brand hex values apply only to artwork.
- `materials.md › Liquid Glass`: “Don’t use Liquid Glass in the content layer” — grouped forms retain system surfaces; no simulated glass overlays.
- `app-icons.md › Design`: simple, consistent identity across contexts — the same original orbit geometry supplies menu and app artwork.

References: [Settings](https://developer.apple.com/design/human-interface-guidelines/settings), [Color](https://developer.apple.com/design/human-interface-guidelines/color), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons).

## Verification boundaries

Native rendering checked on macOS 27, plus test-host light/dark layout renders. Controls have accessible labels; the menu image is a template so the system supplies its light/dark coloring. This is not a full VoiceOver, keyboard-only or measured contrast certification. Offscreen renders can show inactive control styling and don't reproduce every compositor effect. See TESTING.md for engine and runtime coverage.

Ponytail review: no new dependencies, one bounded window-discovery recovery fix, one shared brand geometry and a few native view changes. Release products, private local diagnostic history and development caches stay outside Git. Source and public documentation contain no machine-specific absolute paths.

## Language and motion review

English is the development language; English and Polish use native `.lproj` resources shared by SwiftUI, AppKit and diagnostics. macOS supplies the app-specific language choice. The menu remains a native `NSStatusBarButton`; a noninteractive image subview animates its artwork without intercepting clicks. Its backing layer explicitly uses the image center as its pivot. Rapid changes update the state immediately and share the current turn instead of reversing it. HIG `motion.md › Best practices` calls for purposeful, brief feedback and optional motion; `accessibility.md › Vision` requires state beyond color alone. Pause bars and an accessible status label preserve meaning without animation or color.

### 1.4.1 motion correction

The 1.4.0 test checked only that an animation existed. A real compositor measurement exposed a corner pivot and a short offset-to-zero movement: the center drifted 3.4371 points. Version 1.4.1 starts at the current resting orientation and completes a full turn around its center. Live measurements covered enable, disable and rapid changes: ±360° travel, zero measured center drift, no reversal. A new opt-in compositor regression test checks the presentation layer on a real native status button, beyond animation configuration alone.


## 1.5 state and interaction refinement

Keep the three native preference panes and the original orbit identity. Use system typography, semantic colors and standard AppKit/SwiftUI controls; avoid a custom glass dashboard. General gives priority to Enable, status, delay and pause. Confirmed permission is compact; missing permission gets an actionable message. Advanced window options remain available through disclosure. Quit SmoothQuit remains explicit in the footer and menus.

The menu orbit has five state markers: solid dot (active), hollow dot (disabled), pause bars (paused), exclamation (Accessibility required), plus (choose apps). Text and accessibility labels explain the same states. The centered 0.6-second turn is reserved for intentional Enable/Disable changes. Other state updates are immediate; Reduce Motion suppresses rotation. Short 0.18-second form layout changes respect Reduce Motion.

Applications uses a flexible native list rather than nested scrolling. A sheet contains per-app rules. Search and empty states guide the next action; Bundle IDs remain in details. Recent Activity shows names, icons and outcomes, with raw diagnostics one switch away. New events are loaded explicitly while the pane is being read. Local diagnostics never contain window titles or document contents.

Pause displays a remaining-time value in the open native menu and Settings. The menu timer is invalidated on close; a single scheduled expiry updates presentation without restarting the monitoring engine. Disable is indefinite and clears a prior pause, so a later Enable has an unambiguous effect.

Ponytail Full review: reused the existing AppModel, preferences, native menu and AX engine. No new runtime package, background polling service, design framework or settings persistence layer was introduced. Removed the permanent autosave message and nested rules-list scrolling. Timer ownership is bounded to an open paused menu plus one scheduled pause-expiry notification. Review also preserved the existing Quit-history filter, stopped automatic refreshes from interrupting a turn, and added a fallback for app bundles whose display-name fields are empty.


## 1.6 version, updates and foreground ownership

The footer displays the version from the running bundle. About is a native sheet attached to Settings, so it does not create an independent foreground workflow. Closing Settings hides the utility UI through AppKit; reopening unhides the same window and requests activation using the modern API. macOS owns focus and the active application menu; there are no focus timers, global event interception or forced activation loops.

Updates use an ephemeral URLSession, once per launch or on explicit request, with a persisted opt-out for launch checks. Only newer stable versions with validated GitHub release links are offered. Network, rate-limit and invalid-metadata errors are not reported as up-to-date results. Local notification authorization is requested in context, after a newer release is found; denied notifications leave the available version visible in the UI. There is no auto-installer or recurring network timer.

A per-Quit UUID associates a request with its process exit without conflating separate launches of one bundle. Raw diagnostics remain unchanged. Inspection executes on the existing serial AX worker, with the same read budget, without touching observers, the identity ledger or pending deadlines. The quick exception adds a Never rule without changing selection mode or a custom delay. Diagnostic reports are explicit clipboard actions, limited to 20 displayed events plus version, macOS and saved rules.

Ponytail Full review: kept update checks separate from automation preferences, so network/UI actions never restart AX monitoring. Reused the native session, menu, sheet and notification APIs; no updater framework or installer was added. Retained strict version/link validation and bounded report size. Removed activation assumptions from the interactive fixture: macOS user intent controls focus, and the utility uses native hide/unhide rather than a focus-enforcement loop.
