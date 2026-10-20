import AppKit
import SwiftUI
import CoreServices
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation, UNUserNotificationCenterDelegate {
    let model: AppModel
    init(model: AppModel = AppModel()) { self.model = model; super.init() }
    private var statusItem: NSStatusItem!
    private let statusIcon = StatusIconView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    private(set) var window: NSWindow?
    private var becameActive: NSObjectProtocol?
    private var accessibilityOptions: NSObjectProtocol?
    private var menuTimer: Timer?
    private weak var countdownItem: NSMenuItem?
    private var lastExternalApp: NSRunningApplication?
    private var activatedApp: NSObjectProtocol?
    private(set) var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LaunchServices normally reuses this process (Spotlight/Finder/open).
        // Also redirect an explicitly launched copy before it starts another monitor.
        let current = NSRunningApplication.current
        if let id = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: {
               $0.processIdentifier != current.processIdentifier &&
               ($0.launchDate ?? .distantPast) < (current.launchDate ?? Date())
           }), let url = existing.bundleURL {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.accessory)
        rememberExternalApp(NSWorkspace.shared.frontmostApplication)
        activatedApp = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            self?.rememberExternalApp(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
        }
        makeMainMenu()
        model.onAbout = { [weak self] in self?.about() }
        let notifications = UNUserNotificationCenter.current()
        notifications.delegate = self
        model.updates.onResult = { [weak self] phase, automatically in
            if automatically, case .available(let release) = phase { self?.notifyUpdate(release) }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            statusIcon.frame.origin = NSPoint(x: (button.bounds.width - 18) / 2, y: (button.bounds.height - 18) / 2)
            statusIcon.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            button.addSubview(statusIcon)
        }
        statusItem.button?.toolTip = "SmoothQuit"
        statusItem.menu = NSMenu(); statusItem.menu?.delegate = self
        // Never use .terminationOnRemoval: hiding the item is purely visual.
        statusItem.behavior = []
        model.onChange = { [weak self] animated in self?.updateStatusItem(animated: animated) }
        updateStatusItem()
        model.start()
        becameActive = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.checkPermission()
        }
        accessibilityOptions = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateStatusItem()
        }
        if Self.shouldShowSettings(onLaunch: NSAppleEventManager.shared().currentAppleEvent) { showSettings() }
        model.updates.check(automatically: true)
    }
    static func shouldShowSettings(onLaunch event: NSAppleEventDescriptor?) -> Bool {
        !(event?.eventID == kAEOpenApplication &&
          event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func updateStatusItem(animated: Bool = false) {
        statusItem?.isVisible = model.showInMenuBar
        statusItem?.button?.toolTip = "SmoothQuit — \(model.status)"
        statusItem?.button?.setAccessibilityLabel("SmoothQuit — \(model.status)")
        statusIcon.update(state: model.monitoringState, animated: animated && statusItem?.isVisible == true)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menuTimer?.invalidate(); menuTimer = nil
        menu.removeAllItems()
        let status = menu.addItem(withTitle: model.status, action: nil, keyEquivalent: ""); status.isEnabled = false
        if let remaining = model.pauseRemaining() {
            let item = menu.addItem(withTitle: remaining, action: nil, keyEquivalent: "")
            item.isEnabled = false; countdownItem = item
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self, weak menu] _ in
                guard let self else { return }
                self.countdownItem?.title = self.model.pauseRemaining() ?? L("Pause finished")
                if self.model.pauseRemaining() == nil {
                    status.title = self.model.status
                    menu?.items.first(where: { $0.action == #selector(self.resume) })?.isEnabled = false
                    self.menuTimer?.invalidate(); self.menuTimer = nil
                }
            }
            menuTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        if model.monitoringState == .needsAccess {
            add(menu, L("Grant access…"), #selector(openAccessibility))
        } else if model.monitoringState == .needsApps {
            add(menu, L("Choose Apps…"), #selector(chooseApps))
        }
        menu.addItem(.separator())
        add(menu, model.preferences.enabled ? L("Disable SmoothQuit") : L("Enable SmoothQuit"), #selector(toggleEnabled))
        if model.preferences.enabled && model.preferences.isPaused { add(menu, L("Resume"), #selector(resume)) }
        else if model.preferences.enabled {
            let pause = NSMenuItem(title: L("Pause"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for minutes in [5, 15, 30, 60] {
                let item = NSMenuItem(title: L("%d minutes", minutes), action: #selector(pause(_:)), keyEquivalent: "")
                item.target = self; item.tag = minutes; submenu.addItem(item)
            }
            pause.submenu = submenu; menu.addItem(pause)
        }
        menu.addItem(.separator())
        if let app = lastExternalApp, !app.isTerminated, let id = app.bundleIdentifier {
            let item = NSMenuItem(title: L("Keep %@ Running", app.localizedName ?? id), action: #selector(keepLastAppRunning), keyEquivalent: "")
            item.target = self; item.representedObject = app
            item.isEnabled = model.preferences.rules.first(where: { $0.id == id })?.behavior != .never
            menu.addItem(item)
        }
        if let release = model.updates.availableRelease {
            add(menu, L("Update Available: %@…", release.version), #selector(checkUpdates))
        }
        add(menu, L("Settings…"), #selector(showSettings), key: ",")
        add(menu, L("About SmoothQuit"), #selector(about))
        add(menu, L("Check for Updates…"), #selector(checkUpdates))
        add(menu, L("Quit SmoothQuit"), #selector(quit), key: "q")
    }
    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate(); menuTimer = nil; countdownItem = nil
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    private func makeMainMenu() {
        let bar = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu(title: "SmoothQuit")
        root.submenu = appMenu; bar.addItem(root)
        add(appMenu, L("About SmoothQuit"), #selector(about))
        add(appMenu, L("Check for Updates…"), #selector(checkUpdates))
        appMenu.addItem(.separator())
        add(appMenu, L("Settings…"), #selector(showSettings), key: ",")
        add(appMenu, L("Enable SmoothQuit"), #selector(toggleEnabled))
        add(appMenu, L("Show in Menu Bar"), #selector(toggleMenuBar))
        appMenu.addItem(.separator())
        let hide = appMenu.addItem(withTitle: L("Hide SmoothQuit"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(.separator()); add(appMenu, L("Quit SmoothQuit"), #selector(quit), key: "q")
        let editRoot = NSMenuItem(); let edit = NSMenu(title: L("Edit")); editRoot.submenu = edit; bar.addItem(editRoot)
        for (title, action, key) in [(L("Undo"), Selector(("undo:")), "z"), (L("Cut"), #selector(NSText.cut(_:)), "x"), (L("Copy"), #selector(NSText.copy(_:)), "c"), (L("Paste"), #selector(NSText.paste(_:)), "v"), (L("Select All"), #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
            if key == "z" {
                let redo = edit.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "z")
                redo.keyEquivalentModifierMask = [.command, .shift]
                edit.addItem(.separator())
            }
        }
        let viewRoot = NSMenuItem(); let viewMenu = NSMenu(title: L("View"))
        viewRoot.submenu = viewMenu; bar.addItem(viewRoot)
        for (index, title) in [L("General"), L("Applications"), L("Activity")].enumerated() {
            let item = viewMenu.addItem(withTitle: title, action: #selector(showPane(_:)), keyEquivalent: String(index + 1))
            item.target = self; item.tag = index
        }
        let windowRoot = NSMenuItem(); let windows = NSMenu(title: L("Window")); windowRoot.submenu = windows; bar.addItem(windowRoot)
        windows.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = windows; NSApp.mainMenu = bar
    }
    func makeSettingsWindow() -> NSWindow {
        if let window { return window }
        let tabs = SettingsTabs(model: model)
        let newWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        newWindow.contentViewController = tabs
        newWindow.delegate = self
        newWindow.contentMinSize = NSSize(width: 640, height: 540)
        newWindow.isReleasedWhenClosed = false
        newWindow.tabbingMode = .disallowed
        newWindow.collectionBehavior = [.fullScreenNone]
        newWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        newWindow.toolbarStyle = .preference
        if !newWindow.setFrameUsingName("SmoothQuitSettings") { newWindow.center() }
        newWindow.setFrameAutosaveName("SmoothQuitSettings")
        window = newWindow
        tabs.updateWindowTitle()
        return newWindow
    }
    @objc func showSettings() {
        let window = makeSettingsWindow()
        NSApp.unhideWithoutActivation()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Reopening settings must not reset an otherwise healthy monitor.
        model.checkPermission()
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        if let aboutWindow, closing.attachedSheet === aboutWindow { closing.endSheet(aboutWindow) }
        // AppKit restores the previous foreground app and its menu. Monitoring continues.
        if closing.isVisible { NSApp.hide(nil) }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleEnabled) {
            item.title = model.preferences.enabled ? L("Disable SmoothQuit") : L("Enable SmoothQuit")
        } else if item.action == #selector(toggleMenuBar) {
            item.state = model.showInMenuBar ? .on : .off
        } else if item.action == #selector(checkUpdates) {
            return !model.updates.isChecking
        } else if item.action == #selector(keepLastAppRunning), let app = item.representedObject as? NSRunningApplication {
            return !app.isTerminated && model.preferences.rules.first(where: { $0.id == app.bundleIdentifier })?.behavior != .never
        }
        return true
    }
    @objc private func showPane(_ sender: NSMenuItem) {
        showSettings()
        (window?.contentViewController as? SettingsTabs)?.selectedTabViewItemIndex = sender.tag
    }
    @objc private func toggleMenuBar() { model.showInMenuBar.toggle() }
    @objc private func toggleEnabled() { model.setEnabled(!model.preferences.enabled) }
    @objc private func openAccessibility() { model.requestAccessibility() }
    @objc private func chooseApps() {
        showSettings(); (window?.contentViewController as? SettingsTabs)?.selectedTabViewItemIndex = 1
    }
    @objc private func resume() { model.pause(minutes: nil) }
    @objc private func pause(_ sender: NSMenuItem) { model.pause(minutes: sender.tag) }
    private func rememberExternalApp(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.bundleIdentifier != "pl.smoothquit.app" else { return }
        lastExternalApp = app
    }
    @objc private func keepLastAppRunning(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication, !app.isTerminated, let id = app.bundleIdentifier else { return }
        model.keepRunning(id, name: app.localizedName ?? id)
    }
    @objc func about() {
        showSettings()
        guard let window, window.attachedSheet == nil else { return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 410), styleMask: [.titled], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentViewController = NSHostingController(rootView: AboutView(updates: model.updates) { [weak window, weak panel] in
            if let panel { window?.endSheet(panel) }
        })
        aboutWindow = panel
        window.beginSheet(panel)
    }
    @objc private func checkUpdates() { about(); model.updates.check() }
    private func notifyUpdate(_ release: ReleaseInfo) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { [weak self] granted, error in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.model.updates.automaticallyChecks else { return }
                guard granted, error == nil else {
                    self.model.updates.notificationHint = L("Notifications are off. Available updates are still shown here and in the menu.")
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = L("SmoothQuit update available")
                content.body = L("Version %@ is available. Click to view the release.", release.version)
                content.userInfo = ["releaseURL": release.html_url]
                center.add(UNNotificationRequest(identifier: "smoothquit-update", content: content, trigger: nil)) { [weak self] error in
                    if error != nil {
                        DispatchQueue.main.async { self?.model.updates.notificationHint = L("Could not deliver a notification. The update remains available here.") }
                    }
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let value = response.notification.request.content.userInfo["releaseURL"] as? String,
           let url = ReleaseInfo.releaseURL(value) {
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
