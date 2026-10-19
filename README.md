<p align="center"><img src="docs/images/app-icon.png" width="128" alt="SmoothQuit orbit icon"></p>
<h1 align="center">SmoothQuit</h1>
<p align="center">Close the last window. Let the app leave quietly.</p>
<p align="center"><a href="https://github.com/fkrzeminski-code/SmoothQuit/releases">Download</a> · <a href="docs/README.pl.md">Polski</a> · <a href="docs/SAFETY.md">How it works</a> · <a href="docs/TESTING.md">Testing</a></p>

SmoothQuit is a small, native macOS menu bar utility that asks an app to quit after its last normal window closes. The window closes normally, with the app's own macOS animation. SmoothQuit waits for your chosen delay, checks again, and sends a standard Quit request.

**Preview software.** Releases are locally signed **ad hoc**, not Apple-notarized. macOS may block a downloaded build; a seamless install on another Mac is not guaranteed. You can inspect the source and build it yourself. No Apple Developer subscription is required to build locally.

## Download and install

1. Download `SmoothQuit.dmg` from [Releases](https://github.com/fkrzeminski-code/SmoothQuit/releases). Choose the newest preview; the universal app contains Apple Silicon and Intel code.
2. Open the DMG and drag **SmoothQuit** into **Applications**. Quit an older running copy before replacing it. Run from Applications, not the mounted DMG, if you want launch at login.
3. In **System Settings → Privacy & Security → Accessibility**, add and enable SmoothQuit. This is its only required permission. If macOS blocks a trusted download, use its normal **Open Anyway** flow if offered; do not disable Gatekeeper or SIP.
4. In **Aplikacje** (Applications), start with **Include** and add one app with an empty or disposable document. A fresh installation starts with an empty Include list, so it closes nothing until you select an app.
5. Turn on **Enable SmoothQuit**. The default delay is **0.5 seconds**.

The interface is currently primarily Polish, with English labels for Enable and Show in Menu Bar. [Polish instructions](docs/README.pl.md) map the settings directly.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/settings-dark.png">
  <img src="docs/images/settings-light.png" width="680" alt="SmoothQuit settings: automation, delay, pause and menu bar visibility">
</picture>

*Settings content rendered with test data on macOS 27; the live app also has a native three-pane preferences toolbar.*

## Features

- **Native window closing:** no intercepted clicks or keyboard shortcuts, no replacement close animation.
- **Adjustable delay:** 0.2–2 seconds, including overrides for individual apps.
- **Include / Exclude:** work only with selected apps, or exempt apps from automatic Quit. Per-app Always / Never rules take precedence.
- **Conservative checks:** existing normal, minimized, hidden, fullscreen, auxiliary and remembered off-Space windows prevent Quit. Ambiguous AX reads also prevent it.
- **Cancellation:** a new target-app window, disabling SmoothQuit, pausing or changing rules cancels pending work.
- **Menu bar optional:** hiding the icon leaves the service running. Open SmoothQuit from Finder or Spotlight to return to settings.
- **Separate Enable and Quit:** disabling automation keeps SmoothQuit running. Closing settings only closes the window. **Quit SmoothQuit** exits the utility itself.
- **Pause and launch at login:** native macOS controls, with no background helper to install.
- **Session diagnostics:** recent decisions and measured timings, held in memory only.

Finder is protected by default. SmoothQuit always protects its own process. A normal Quit lets the target app present its save dialog or refuse to quit; SmoothQuit never force-quits or repeatedly sends Quit.

## Privacy

No telemetry, analytics, ads, account, updater or network requests. No window titles, document paths or contents, screenshots, or keystrokes are recorded. Diagnostics contain bundle identifiers, timing and decision reasons; the last 200 entries live only in memory. Preferences are saved locally using UserDefaults. Neither Screen Recording nor Input Monitoring is required.

Accessibility is a powerful system permission. SmoothQuit uses public AX APIs to observe window state, and `NSRunningApplication.terminate()` to request normal termination. [Read the safety model and limitations](docs/SAFETY.md).

## Compatibility and limitations

- Minimum deployment target: **macOS 14**. The current build is compiled with **Xcode 27.1 / macOS 27 SDK** and visually checked on macOS 27. Older systems and physical Intel hardware have not received the same live test coverage.
- Some apps don't expose reliable Accessibility windows or destruction events. SmoothQuit intentionally leaves them running when it cannot establish a safe result.
- Public APIs cannot provide a complete, atomic snapshot of every Space followed by an atomic Quit. The identity ledger and final checks reduce that risk; they cannot make such a guarantee.
- After replacing an ad-hoc-signed build, you may need to remove its old Accessibility entry and add the new app. Keep one installed copy to avoid confusion with permissions and launch at login.
- The configured delay starts when SmoothQuit receives the destruction event. IPC and scheduling add some time; diagnostics distinguish the Quit request from the eventual process exit.

## Build from source

Use full Xcode with its command-line tools selected. The release script was verified with Xcode 27.1; it downloads no dependencies.

```sh
git clone https://github.com/fkrzeminski-code/SmoothQuit.git
cd SmoothQuit
swift test
./scripts/build.sh
```

Output: `Builds/Preview-1.3.0/SmoothQuit.app` and `SmoothQuit.dmg`, with build/test/signature reports and a source snapshot. The script does not install or launch the app. Build products are ignored by Git.

Open `Package.swift` in Xcode to work on the project. SwiftUI and AppKit provide the interface; AXObserver, NSWorkspace and CoreGraphics provide observation. There are no third-party runtime packages.

## Testing and contributing

[Testing notes](docs/TESTING.md) distinguish automated checks, real app tests, and untested scenarios. Interactive tests are opt-in and must only be run against authorized, disposable windows. Ordinary `swift test` never launches or quits a target app.

For bugs, include your macOS version, SmoothQuit version, target app and bundle ID, Include/Exclude rules, configured delay and a short reproduction. Share only the relevant diagnostic lines; omit personal document or message contents. Keep contributions small, native and conservative about closing applications.

## Credits and license

[SmartClose](https://github.com/mahirozdin/SmartClose), [Quitty](https://github.com/chentao1006/Quitty) and [last-window-quits](https://github.com/mikecann/last-window-quits) informed the comparison of approaches. [Vorssaint](https://github.com/vorssaint/vorssaint-utils) inspired visual consistency between an app and its menu bar icon. No source code or brand assets from those projects are included. SmoothQuit's orbit is original vector artwork.

[MIT License](LICENSE). SmoothQuit is an independent project and is not affiliated with Apple or the projects above.
