import XCTest
import AppKit
import SwiftUI
import CoreServices
import QuartzCore
import SmoothQuitCore
@testable import SmoothQuit

final class InterfaceTests: XCTestCase {
    @MainActor private var trackingMenu: NSMenu?
    @MainActor private var trackingTitles = Set<String>()
    @MainActor private var trackingFinished = false
    @MainActor @objc private func sampleTrackingMenu() {
        for item in trackingMenu?.items ?? [] {
            if item.title.hasPrefix(L("Resumes in %@", "")) { trackingTitles.insert(item.title) }
            if item.title == L("Pause finished") { trackingFinished = true }
        }
    }
    @MainActor @objc private func closeTrackingMenu() { trackingMenu?.cancelTracking() }
    func testBrandUsesTemplateImageForSystemMenuBarAppearance() throws {
        let image = Brand.image()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertNotNil(image.tiffRepresentation)
        XCTAssertFalse(Brand.orbit.boundingBoxOfPath.isEmpty)
    }
    @MainActor func testStatusIconShowsStateAndRespectsReducedMotion() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.trusted = true
        XCTAssertFalse(model.isMonitoring) // Empty Include list.
        model.add(id: "com.apple.iCal")
        XCTAssertTrue(model.isMonitoring)
        model.preferences.enabled = false
        XCTAssertFalse(model.isMonitoring)
        model.preferences.enabled = true
        model.preferences.pauseUntil = Date().addingTimeInterval(60)
        XCTAssertFalse(model.isMonitoring)
        model.preferences.pauseUntil = nil
        model.trusted = false
        XCTAssertFalse(model.isMonitoring)
        let icon = StatusIconView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        icon.update(state: .active, animated: true)
        let enabled = try XCTUnwrap(icon.image?.tiffRepresentation)
        icon.update(state: .disabled, animated: true, reduceMotion: true)
        XCTAssertNotEqual(enabled, icon.image?.tiffRepresentation)
        XCTAssertTrue(icon.image?.isTemplate == true)
        XCTAssertNil(icon.layer?.animation(forKey: "stateChange"))
        XCTAssertNil(icon.hitTest(.zero)) // The native status button still receives clicks.
        icon.update(state: .active, animated: true, reduceMotion: false)
        let turn = try XCTUnwrap(icon.layer?.animation(forKey: "stateChange") as? CABasicAnimation)
        XCTAssertEqual(turn.fromValue as? Double, 0)
        XCTAssertEqual(try XCTUnwrap(turn.toValue as? Double), 2 * .pi, accuracy: 0.0001)
        XCTAssertEqual(icon.layer?.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(icon.layer?.position, CGPoint(x: icon.frame.midX, y: icon.frame.midY))
        let startedAt = turn.beginTime
        icon.update(state: .disabled, animated: true, reduceMotion: false)
        let continuing = try XCTUnwrap(icon.layer?.animation(forKey: "stateChange") as? CABasicAnimation)
        XCTAssertEqual(continuing.toValue as? Double, turn.toValue as? Double)
        XCTAssertEqual(continuing.beginTime, startedAt)
        XCTAssertEqual(icon.state, .disabled) // Immediate state feedback without reversing the turn.
        icon.update(state: .active, animated: true, reduceMotion: true)
        XCTAssertNil(icon.layer?.animation(forKey: "stateChange"))
    }
    /// Opt-in compositor check: uses a real native menu bar item, no AX or other apps.
    @MainActor func testLiveMenuIconCompletesTurnsWithoutMovingOrReversing() throws {
        guard ProcessInfo.processInfo.environment["SMOOTHQUIT_LIVE_ICON"] == "1" else {
            throw XCTSkip("Requires an unlocked interactive desktop for real compositor measurements")
        }
        _ = NSApplication.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        let button = try XCTUnwrap(item.button)
        let icon = StatusIconView(frame: NSRect(x: (button.bounds.width-18)/2, y: (button.bounds.height-18)/2, width: 18, height: 18))
        button.addSubview(icon)
        icon.update(state: .disabled, animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        for (active, rapid) in [(true, false), (false, false), (true, true)] {
            icon.update(state: active ? .active : .disabled, animated: true, reduceMotion: false)
            CATransaction.flush()
            let start = CACurrentMediaTime()
            let expected = CGPoint(x: icon.frame.midX, y: icon.frame.midY)
            var previous = 0.0, travel = 0.0, maxDrift = 0.0
            var samples = 0, changed = false
            while CACurrentMediaTime()-start < 0.85 {
                if rapid, !changed, CACurrentMediaTime()-start > 0.15 {
                    icon.update(state: active ? .disabled : .active, animated: true, reduceMotion: false)
                    icon.update(state: active ? .active : .disabled, animated: true, reduceMotion: false)
                    changed = true
                }
                if let layer = icon.layer?.presentation() {
                    let transform = CATransform3DGetAffineTransform(layer.transform)
                    let angle = atan2(transform.b, transform.a)
                    var delta = angle-previous
                    if delta < -.pi { delta += 2 * .pi }
                    if delta > .pi { delta -= 2 * .pi }
                    XCTAssertGreaterThanOrEqual((active ? 1 : -1) * delta, -0.01, "Rotation reversed")
                    travel += delta; previous = angle; samples += 1
                    let offset = CGPoint(x: layer.bounds.width*(0.5-layer.anchorPoint.x), y: layer.bounds.height*(0.5-layer.anchorPoint.y)).applying(transform)
                    maxDrift = max(maxDrift, hypot(layer.position.x+offset.x-expected.x, layer.position.y+offset.y-expected.y))
                }
                RunLoop.main.run(until: Date().addingTimeInterval(1.0/120))
            }
            XCTAssertGreaterThan(samples, 20)
            XCTAssertEqual(travel, (active ? 1 : -1) * 2 * .pi, accuracy: 0.02)
            XCTAssertLessThan(maxDrift, 0.05, "The icon must rotate around its center")
            XCTAssertNil(icon.layer?.animation(forKey: "stateChange"))
            print("Live menu turn: active=\(active), rapid=\(rapid), radians=\(travel), centerDrift=\(maxDrift), samples=\(samples)")
        }
    }
    @MainActor func testDistinctStatesAndPauseExpiryWithoutRestartingMonitor() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.trusted = true
        XCTAssertEqual(model.monitoringState, .needsApps)
        model.add(id: "com.apple.TextEdit")
        XCTAssertEqual(model.monitoringState, .active)
        XCTAssertNotEqual(model.preferences.rules[0].name, "com.apple.TextEdit")
        let deadline = Date().addingTimeInterval(61)
        model.preferences.pauseUntil = deadline
        XCTAssertEqual(model.monitoringState, .paused)
        XCTAssertEqual(model.pauseRemaining(at: deadline.addingTimeInterval(-61)), L("Resumes in %@", "1:01"))
        XCTAssertNil(model.pauseRemaining(at: deadline))
        model.setEnabled(false)
        XCTAssertEqual(model.monitoringState, .disabled)
        XCTAssertNil(model.preferences.pauseUntil)
        XCTAssertNil(model.pauseRemaining())
        model.setEnabled(true)
        model.trusted = false
        XCTAssertEqual(model.monitoringState, .needsAccess)
        model.trusted = true
        var animated: [Bool] = []
        model.onChange = { animated.append($0) }
        model.preferences.pauseUntil = Date().addingTimeInterval(0.04)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        XCTAssertEqual(model.monitoringState, .active)
        XCTAssertGreaterThanOrEqual(animated.count, 2) // Saved pause, then expiry notification.
        XCTAssertTrue(animated.allSatisfy { !$0 })
        let images = MonitoringState.allCases.compactMap { Brand.image(state: $0).tiffRepresentation }
        XCTAssertEqual(Set(images).count, MonitoringState.allCases.count)
    }
    @MainActor func testMenuCountdownUpdatesWhileOpenAndStopsAfterClose() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.pause(minutes: 5)
        let delegate = AppDelegate(model: model)
        let menu = NSMenu()
        delegate.menuWillOpen(menu)
        let countdown = try XCTUnwrap(menu.items.first { $0.title == model.pauseRemaining() })
        let first = countdown.title
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertNotEqual(countdown.title, first)
        delegate.menuDidClose(menu)
        let closed = countdown.title
        RunLoop.main.run(until: Date().addingTimeInterval(1.1))
        XCTAssertEqual(countdown.title, closed)
        model.setEnabled(false)
        delegate.menuWillOpen(menu)
        XCTAssertTrue(menu.items.contains { $0.title == L("Disabled until you enable it") })
        XCTAssertFalse(menu.items.contains { $0.title.hasPrefix(L("Resumes in %@", "")) })
        delegate.menuDidClose(menu)
    }
    @MainActor func testAutomaticRefreshDoesNotInterruptAnIntentionalTurn() throws {
        let icon = StatusIconView(frame: NSRect(x: 3, y: 3, width: 18, height: 18))
        icon.update(state: .disabled, animated: false)
        icon.update(state: .active, animated: true, reduceMotion: false)
        XCTAssertNotNil(icon.layer?.animation(forKey: "stateChange"))
        icon.update(state: .active, animated: false, reduceMotion: false)
        XCTAssertNotNil(icon.layer?.animation(forKey: "stateChange"))
        icon.update(state: .paused, animated: false, reduceMotion: false)
        XCTAssertNil(icon.layer?.animation(forKey: "stateChange"))
        icon.update(state: .needsAccess, animated: false)
        XCTAssertNil(icon.layer?.animation(forKey: "stateChange"))
    }
    @MainActor func testRulesExplainEffectiveBehaviorAndSupportUndoRedo() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.add(id: "com.apple.TextEdit")
        model.preferences.rules[0].delay = 1.25
        let original = model.preferences.rules[0]
        XCTAssertEqual(model.ruleOutcome(original.id), L("Will quit after the last window closes"))
        model.preferences.mode = .exclude
        XCTAssertEqual(model.ruleOutcome(original.id), L("Kept running"))
        model.preferences.rules[0].behavior = .allow
        model.setEnabled(false)
        XCTAssertEqual(model.ruleOutcome(original.id), L("Will quit after the last window closes"))
        let undo = UndoManager()
        undo.beginUndoGrouping()
        model.removeRule(original.id, undoManager: undo)
        undo.endUndoGrouping()
        XCTAssertTrue(model.preferences.rules.isEmpty)
        undo.undo()
        XCTAssertEqual(model.preferences.rules[0].delay, 1.25)
        XCTAssertEqual(model.preferences.rules[0].behavior, .allow)
        undo.redo()
        XCTAssertTrue(model.preferences.rules.isEmpty)
        XCTAssertEqual(model.ruleOutcome("com.apple.finder"), L("Kept running"))
        model.add(id: "pl.smoothquit.app")
        XCTAssertTrue(model.preferences.rules.isEmpty)
        XCTAssertNotNil(model.error)
    }
    func testActivityDistinguishesQuitRequestFromExit() {
        let request = Diagnostic(bundleID: "com.apple.TextEdit", message: "raw AX details", requested: true, elapsed: 0.54)
        let exit = Diagnostic(bundleID: "com.apple.TextEdit", message: "raw exit", completed: true, elapsed: 0.6)
        XCTAssertNotEqual(request.activityMessage, exit.activityMessage)
        XCTAssertEqual(request.activityMessage, L("Quit requested — waiting for the app to exit"))
        let blocked = Diagnostic(bundleID: "com.apple.TextEdit", message: "raw AX error", summary: "Kept running")
        XCTAssertEqual(blocked.activityMessage, "Kept running")
    }
    @MainActor func testLivePauseMenuUpdatesDuringNativeTrackingAndExpires() throws {
        guard ProcessInfo.processInfo.environment["SMOOTHQUIT_LIVE_ICON"] == "1" else {
            throw XCTSkip("Requires an unlocked interactive desktop for native menu tracking")
        }
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.trusted = true; model.preferences.mode = .exclude
        model.preferences.pauseUntil = Date().addingTimeInterval(2.3)
        let delegate = AppDelegate(model: model)
        let menu = NSMenu(); menu.delegate = delegate; trackingMenu = menu
        trackingTitles = []; trackingFinished = false
        let sampler = Timer(timeInterval: 0.15, target: self, selector: #selector(sampleTrackingMenu), userInfo: nil, repeats: true)
        let close = Timer(timeInterval: 3.5, target: self, selector: #selector(closeTrackingMenu), userInfo: nil, repeats: false)
        RunLoop.main.add(sampler, forMode: .common); RunLoop.main.add(close, forMode: .common)
        defer { sampler.invalidate(); close.invalidate(); delegate.menuDidClose(menu); trackingMenu = nil }
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        NSApp.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let opened = Date()
        menu.popUp(positioning: nil, at: NSPoint(x: screen.midX, y: screen.midY), in: nil)
        guard Date().timeIntervalSince(opened) >= 3 else {
            throw XCTSkip("Native menu was dismissed before the expiry check; an uninterrupted desktop is required")
        }
        XCTAssertGreaterThanOrEqual(trackingTitles.count, 2, "Countdown must tick inside native menu tracking")
        XCTAssertTrue(trackingFinished)
        XCTAssertEqual(model.monitoringState, .active)
        XCTAssertTrue(menu.items.contains { $0.title == model.status })
        print("Native tracking countdown: \(trackingTitles.sorted()), expired=\(trackingFinished)")
    }
    @MainActor func testLiveSettingsCloseHidesUtilityAndReopens() throws {
        guard ProcessInfo.processInfo.environment["SMOOTHQUIT_LIVE_ICON"] == "1" else {
            throw XCTSkip("Requires an unlocked desktop for native activation and close behavior")
        }
        _ = NSApplication.shared
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let delegate = AppDelegate(model: model)
        NSApp.setActivationPolicy(.accessory)
        delegate.showSettings()
        let window = try XCTUnwrap(delegate.window)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let wasActive = NSApp.isActive
        XCTAssertTrue(window.delegate === delegate)
        window.performClose(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(NSApp.isActive)
        // Changing to accessory can clear isHidden; no visible window and no
        // foreground ownership are the actual background-mode contract.
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        delegate.showSettings()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(window.isVisible); XCTAssertFalse(NSApp.isHidden)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        print("Settings close: activeBefore=\(wasActive); hidden after close; same window reopened. macOS may decline XCTest activation without a user event.")
        window.performClose(nil)
        window.contentViewController = nil
    }
    func testEnglishAndPolishResourcesAndDiagnosticFormats() throws {
        let bundle = Localization.bundle
        let en = try XCTUnwrap(Bundle(path: try XCTUnwrap(bundle.path(forResource: "en", ofType: "lproj"))))
        let pl = try XCTUnwrap(Bundle(path: try XCTUnwrap(bundle.path(forResource: "pl", ofType: "lproj"))))
        XCTAssertEqual(en.localizedString(forKey: "General", value: nil, table: nil), "General")
        XCTAssertEqual(pl.localizedString(forKey: "General", value: nil, table: nil), "Ogólne")
        let key = "Monitoring active: %d normal, %d auxiliary windows"
        XCTAssertEqual(String(format: pl.localizedString(forKey: key, value: nil, table: nil), 2, 1),
                       "Obserwacja aktywna: 2 normalnych, 1 pomocniczych okien")
        let english = try XCTUnwrap(NSDictionary(contentsOf: try XCTUnwrap(en.url(forResource: "Localizable", withExtension: "strings"))))
        let polish = try XCTUnwrap(NSDictionary(contentsOf: try XCTUnwrap(pl.url(forResource: "Localizable", withExtension: "strings"))))
        XCTAssertEqual(Set(english.allKeys.compactMap { $0 as? String }), Set(polish.allKeys.compactMap { $0 as? String }))
        let placeholders = try NSRegularExpression(pattern: "%[0-9$.]*[df@]")
        for case let key as String in english.allKeys {
            let translated = try XCTUnwrap(polish[key] as? String)
            func formats(_ value: String) -> [String] {
                placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { String(value[Range($0.range, in: value)!]) }
            }
            XCTAssertEqual(formats(key), formats(translated), key)
        }
    }
    @MainActor func testMenuBarPreferencePreservesExistingAutomationAndPersists() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = Preferences()
        legacy.delay = 1.25; legacy.rules = [AppRule(id: "com.apple.TextEdit", name: "TextEdit")]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "preferences.v1")
        let model = AppModel(defaults: defaults)
        XCTAssertTrue(model.showInMenuBar)
        model.showInMenuBar = false
        XCTAssertEqual(model.preferences, legacy)
        let reloaded = AppModel(defaults: defaults)
        XCTAssertFalse(reloaded.showInMenuBar)
        XCTAssertEqual(reloaded.preferences, legacy)
        reloaded.preferences.enabled = false
        XCTAssertFalse(reloaded.showInMenuBar)
        reloaded.showInMenuBar = true
        XCTAssertFalse(reloaded.preferences.enabled)
    }
    @MainActor func testClosingSettingsKeepsModelAndReusesSameWindow() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.showInMenuBar = false
        let delegate = AppDelegate(model: model)
        let window = delegate.makeSettingsWindow()
        window.performClose(nil)
        XCTAssertFalse(window.isVisible)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
        XCTAssertTrue(model.preferences.enabled)
        XCTAssertFalse(model.showInMenuBar)
        XCTAssertTrue(delegate.makeSettingsWindow() === window)
        window.contentViewController = nil
    }
    func testManualLaunchShowsSettingsButLoginDoesNot() {
        XCTAssertTrue(AppDelegate.shouldShowSettings(onLaunch: nil))
        let event = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication,
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                          transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertTrue(AppDelegate.shouldShowSettings(onLaunch: event))
        event.setParam(NSAppleEventDescriptor(enumCode: keyAELaunchedAsLogInItem), forKeyword: keyAEPropData)
        XCTAssertFalse(AppDelegate.shouldShowSettings(onLaunch: event))
    }
    @MainActor func testNativeSettingsTabsRestoreSelection() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(2, forKey: "selectedPane")
        let tabs = SettingsTabs(model: AppModel(defaults: defaults), defaults: defaults)
        XCTAssertEqual(tabs.tabStyle, .toolbar)
        XCTAssertEqual(tabs.selectedTabViewItemIndex, 2)
        _ = tabs.view
        tabs.selectedTabViewItemIndex = 1
        XCTAssertEqual(defaults.integer(forKey: "selectedPane"), 1)
        XCTAssertEqual(tabs.tabViewItems.count, 3)
    }
    @MainActor func testSelectedRuleBindingSurvivesRemovalAndIndexChange() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.add(id: "com.apple.TextEdit")
        model.add(id: "com.apple.Safari")
        let first = model.binding(for: model.preferences.rules[0])
        let last = model.binding(for: model.preferences.rules[1])
        model.preferences.rules.removeFirst()
        last.wrappedValue.delay = 1.5
        XCTAssertEqual(model.preferences.rules[0].delay, 1.5)
        first.wrappedValue.behavior = .never
        XCTAssertEqual(model.preferences.rules[0].behavior, .mode)
        model.preferences.rules.removeAll()
        XCTAssertNil(first.wrappedValue.delay)
        last.wrappedValue.delay = 2
        XCTAssertTrue(model.preferences.rules.isEmpty)
    }
    @MainActor func testPreferencesPersistWithoutStartingMonitor() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.add(id: "com.apple.TextEdit", name: "TextEdit")
        model.preferences.delay = 1.25
        let reloaded = AppModel(defaults: defaults)
        XCTAssertEqual(reloaded.preferences, model.preferences)
        defaults.set(Data("broken".utf8), forKey: "preferences.v1")
        let repaired = AppModel(defaults: defaults)
        XCTAssertEqual(repaired.preferences, Preferences())
        XCTAssertNotNil(repaired.error)
    }
    @MainActor func testSettingsRenderLightAndDarkWithoutLaunchingApp() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.add(id: "com.apple.TextEdit", name: "TextEdit")
        model.add(id: "com.apple.Safari", name: "Safari")
        model.diagnostics = [Diagnostic(bundleID: "com.apple.TextEdit", message: L("Process exited after a normal Quit request"), completed: true, elapsed: 0.563)]
        model.trusted = true // Deterministic fixture, not a permission grant.
        model.loginEnabled = false
        let output = ProcessInfo.processInfo.environment["SMOOTHQUIT_SNAPSHOT_DIR"]
        for size in [NSSize(width: 680, height: 700), NSSize(width: 640, height: 540)] {
        for dark in [false, true] {
            for pane in 0...2 {
                defaults.set(pane, forKey: "selectedPane")
                let view = SettingsView(model: model, pane: pane).defaultAppStorage(defaults).environment(\.colorScheme, dark ? .dark : .light)
                let hosting = NSHostingView(rootView: view)
                hosting.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                hosting.frame = NSRect(origin: .zero, size: size)
                let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = hosting
                // Offscreen: never orderFront, activate, start Monitor, or launch SmoothQuit.app.
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                XCTAssertGreaterThan(hosting.fittingSize.width, 0)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                XCTAssertGreaterThan(png.count, 5000)
                if let output {
                    try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                    try png.write(to: URL(fileURLWithPath: output).appendingPathComponent("settings-\(pane)-\(dark ? "dark" : "light")-\(Int(size.width)).png"))
                }
                window.contentView = nil
            }
        }
        }
    }
}
