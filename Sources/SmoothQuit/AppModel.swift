import AppKit
import ApplicationServices
import Combine
import SwiftUI
import ServiceManagement
import SmoothQuitCore

struct InstalledApp: Identifiable {
    let id: String
    let name: String
    let url: URL
}

final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences.v1") }
            if isStarted { monitor.update(preferences) }
            onChange?()
        }
    }
    // Presentation preference: never reset AX observers or pending window decisions.
    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar"); onChange?() }
    }
    @Published var trusted = AXIsProcessTrusted()
    @Published var diagnostics: [Diagnostic] = []
    @Published var installed: [InstalledApp] = []
    @Published var loadingApps = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @Published var error: String?
    var onChange: (() -> Void)?
    private let monitor = Monitor()
    private let defaults: UserDefaults
    private var isStarted = false
    private var iconCache: [String: NSImage] = [:]
    var isMonitoring: Bool {
        preferences.enabled && !preferences.isPaused && trusted &&
            (preferences.mode == .exclude || !preferences.rules.isEmpty)
    }
    var status: String {
        if !preferences.enabled { return L("Automatic Quit disabled") }
        if preferences.isPaused { return L("Automatic Quit paused") }
        if !trusted { return L("Accessibility required") }
        if preferences.mode == .include && preferences.rules.isEmpty { return L("Choose apps to test") }
        return L("Monitoring active")
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        if let data = defaults.data(forKey: "preferences.v1") {
            if let stored = try? JSONDecoder().decode(Preferences.self, from: data) {
                var safe = stored; safe.delay = Preferences.boundedDelay(safe.delay)
                safe.rules = safe.rules.filter { Preferences.validBundleID($0.id) }
                preferences = safe
            } else {
                preferences = Preferences()
                error = L("Settings could not be read. Restored safe Include mode with an empty list.")
            }
        } else { preferences = Preferences() }
        monitor.onDiagnostic = { [weak self] entry in
            guard let self else { return }
            self.diagnostics.insert(entry, at: 0)
            if self.diagnostics.count > 200 { self.diagnostics.removeLast(self.diagnostics.count - 200) }
        }
        monitor.onPermission = { [weak self] value in
            self?.trusted = value; self?.onChange?()
        }
    }
    func start() {
        guard !isStarted else { return }; isStarted = true
        monitor.start(preferences: preferences)
    }
    func checkPermission() {
        let granted = AXIsProcessTrusted()
        if granted != trusted { trusted = granted; if isStarted { monitor.refresh() } }
        onChange?()
    }
    func refresh() {
        trusted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        if isStarted { monitor.refresh() }; onChange?()
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { self.error = L("Could not change launch at login: %@", error.localizedDescription) }
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func pause(minutes: Int?) {
        preferences.pauseUntil = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
    }
    func add(id: String, name: String? = nil) {
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Preferences.validBundleID(cleaned) else { error = L("Enter a valid Bundle ID, e.g. com.apple.TextEdit."); return }
        guard !preferences.rules.contains(where: { $0.id == cleaned }) else { return }
        preferences.rules.append(AppRule(id: cleaned, name: name ?? cleaned))
    }
    // SwiftUI may read an old binding during removal. Resolve identity on every access,
    // never retain an array index that can disappear or refer to another application.
    func binding(for rule: AppRule) -> Binding<AppRule> {
        Binding(get: { self.preferences.rules.first { $0.id == rule.id } ?? rule }, set: { value in
            guard let index = self.preferences.rules.firstIndex(where: { $0.id == rule.id }) else { return }
            self.preferences.rules[index] = value
        })
    }
    func icon(for id: String) -> NSImage {
        if let cached = iconCache[id] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
        iconCache[id] = icon
        return icon
    }
    func loadInstalledApps() {
        guard !loadingApps else { return }
        loadingApps = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var found: [String: InstalledApp] = [:]
            let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
            var urls: [URL] = []
            for root in roots {
                guard let enumerator = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let url as URL in enumerator {
                    if enumerator.level > 4 { enumerator.skipDescendants(); continue }
                    if url.pathExtension == "app" { urls.append(url); enumerator.skipDescendants() }
                }
            }
            urls += NSWorkspace.shared.runningApplications.compactMap(\.bundleURL)
            if let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") { urls.append(finder) }
            for url in urls {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != "pl.smoothquit.app" else { continue }
                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? url.deletingPathExtension().lastPathComponent
                found[id] = InstalledApp(id: id, name: name, url: url)
            }
            let sorted = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self?.installed = sorted; self?.loadingApps = false }
        }
    }
}
