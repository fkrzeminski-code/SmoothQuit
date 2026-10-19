import AppKit
import SwiftUI
import CoreServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    let model: AppModel
    init(model: AppModel = AppModel()) { self.model = model; super.init() }
    private var statusItem: NSStatusItem!
    private let statusIcon = StatusIconView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    private(set) var window: NSWindow?
    private var becameActive: NSObjectProtocol?

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
        makeMainMenu()
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
        model.onChange = { [weak self] in self?.updateStatusItem() }
        updateStatusItem()
        model.start()
        becameActive = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.model.checkPermission()
        }
        if Self.shouldShowSettings(onLaunch: NSAppleEventManager.shared().currentAppleEvent) { showSettings() }
    }
    static func shouldShowSettings(onLaunch event: NSAppleEventDescriptor?) -> Bool {
        !(event?.eventID == kAEOpenApplication &&
          event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    private func updateStatusItem() {
        statusItem?.isVisible = model.showInMenuBar
        statusItem?.button?.toolTip = "SmoothQuit — \(model.status)"
        statusItem?.button?.setAccessibilityLabel("SmoothQuit — \(model.status)")
        statusIcon.update(active: model.isMonitoring, animated: statusItem?.isVisible == true)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = menu.addItem(withTitle: model.status, action: nil, keyEquivalent: ""); status.isEnabled = false
        menu.addItem(.separator())
        add(menu, model.preferences.enabled ? L("Disable SmoothQuit") : L("Enable SmoothQuit"), #selector(toggleEnabled))
        if model.preferences.isPaused { add(menu, L("Resume"), #selector(resume)) }
        else {
            let pause = NSMenuItem(title: L("Pause"), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for minutes in [5, 15, 30, 60] {
                let item = NSMenuItem(title: L("%d minutes", minutes), action: #selector(pause(_:)), keyEquivalent: "")
                item.target = self; item.tag = minutes; submenu.addItem(item)
            }
            pause.submenu = submenu; menu.addItem(pause)
        }
        menu.addItem(.separator())
        add(menu, L("Settings…"), #selector(showSettings), key: ",")
        add(menu, L("Quit SmoothQuit"), #selector(quit), key: "q")
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    private func makeMainMenu() {
        let bar = NSMenu(); let root = NSMenuItem(); let appMenu = NSMenu(title: "SmoothQuit")
        root.submenu = appMenu; bar.addItem(root)
        add(appMenu, L("About SmoothQuit"), #selector(about))
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
        newWindow.contentMinSize = NSSize(width: 640, height: 540)
        newWindow.isReleasedWhenClosed = false
        newWindow.tabbingMode = .disallowed
        newWindow.collectionBehavior = [.fullScreenNone]
        newWindow.standardWindowButton(.zoomButton)?.isEnabled = false
        newWindow.toolbarStyle = .preference
        newWindow.setFrameAutosaveName("SmoothQuitSettings")
        newWindow.center(); window = newWindow
        tabs.updateWindowTitle()
        return newWindow
    }
    @objc func showSettings() {
        let window = makeSettingsWindow()
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
        // Reopening settings must not reset an otherwise healthy monitor.
        model.checkPermission()
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleEnabled) {
            item.title = model.preferences.enabled ? L("Disable SmoothQuit") : L("Enable SmoothQuit")
        } else if item.action == #selector(toggleMenuBar) {
            item.state = model.showInMenuBar ? .on : .off
        }
        return true
    }
    @objc private func showPane(_ sender: NSMenuItem) {
        showSettings()
        (window?.contentViewController as? SettingsTabs)?.selectedTabViewItemIndex = sender.tag
    }
    @objc private func toggleMenuBar() { model.showInMenuBar.toggle() }
    @objc private func toggleEnabled() { model.preferences.enabled.toggle() }
    @objc private func resume() { model.pause(minutes: nil) }
    @objc private func pause(_ sender: NSMenuItem) { model.pause(minutes: sender.tag) }
    @objc private func about() { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
