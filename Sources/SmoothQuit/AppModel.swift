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
    let isBackground: Bool
    init(id: String, name: String, url: URL) {
        self.id = id; self.name = name; self.url = url
        let bundle = Bundle(url: url)
        isBackground = (bundle?.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true) ||
            (bundle?.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true)
    }
    static func displayName(at url: URL) -> String {
        let bundle = Bundle(url: url)
        return [bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
                bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String]
            .compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            ?? url.deletingPathExtension().lastPathComponent
    }
}

enum MonitoringState: CaseIterable { case active, disabled, paused, needsAccess, needsApps }

final class AppModel: ObservableObject {
    @Published var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences.v1") }
            if isStarted { monitor.update(preferences) }
            schedulePauseExpiry()
            onChange?(oldValue.enabled != preferences.enabled)
        }
    }
    // Presentation preference: never reset AX observers or pending window decisions.
    @Published var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: "showInMenuBar"); onChange?(false) }
    }
    @Published var trusted = AXIsProcessTrusted()
    @Published var diagnostics: [Diagnostic] = []
    @Published var installed: [InstalledApp] = []
    @Published var loadingApps = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    @Published var error: String?
    var onChange: ((Bool) -> Void)?
    private let monitor = Monitor()
    private let defaults: UserDefaults
    private var isStarted = false
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]
    private var pauseExpiry: Timer?
    var monitoringState: MonitoringState {
        if !preferences.enabled { return .disabled }
        if preferences.isPaused { return .paused }
        if !trusted { return .needsAccess }
        if preferences.mode == .include && preferences.rules.isEmpty { return .needsApps }
        return .active
    }
    var isMonitoring: Bool { monitoringState == .active }
    var status: String {
        switch monitoringState {
        case .disabled: return L("Disabled until you enable it")
        case .paused: return L("Paused until %@", preferences.pauseUntil!.formatted(date: .omitted, time: .shortened))
        case .needsAccess: return L("Accessibility required")
        case .needsApps: return L("Choose apps to test")
        case .active: return L("Monitoring active")
        }
    }
    func pauseRemaining(at now: Date = Date()) -> String? {
        guard preferences.enabled, let until = preferences.pauseUntil, until > now else { return nil }
        let seconds = Int(min(ceil(until.timeIntervalSince(now)), 359999))
        return L("Resumes in %@", String(format: "%d:%02d", seconds / 60, seconds % 60))
    }
    private func schedulePauseExpiry() {
        pauseExpiry?.invalidate(); pauseExpiry = nil
        guard let until = preferences.pauseUntil, until > Date() else { return }
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            self?.objectWillChange.send(); self?.onChange?(false)
        }
        pauseExpiry = timer
        RunLoop.main.add(timer, forMode: .common)
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
            self?.trusted = value; self?.onChange?(false)
        }
        schedulePauseExpiry()
    }
    deinit { pauseExpiry?.invalidate() }
    func start() {
        guard !isStarted else { return }; isStarted = true
        monitor.start(preferences: preferences)
    }
    func checkPermission() {
        let granted = AXIsProcessTrusted()
        if granted != trusted { trusted = granted; if isStarted { monitor.refresh() } }
        onChange?(false)
    }
    func refresh() {
        trusted = AXIsProcessTrusted()
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
        if isStarted { monitor.refresh() }; onChange?(false)
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
    func setEnabled(_ enabled: Bool) {
        var value = preferences
        value.enabled = enabled
        value.pauseUntil = nil
        preferences = value
    }
    func add(id: String, name: String? = nil) {
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Preferences.validBundleID(cleaned) else { error = L("Enter a valid Bundle ID, e.g. com.apple.TextEdit."); return }
        guard !preferences.rules.contains(where: { $0.id == cleaned }) else { return }
        guard cleaned != "pl.smoothquit.app", cleaned != Bundle.main.bundleIdentifier else {
            error = L("SmoothQuit always protects itself."); return
        }
        preferences.rules.append(AppRule(id: cleaned, name: name ?? self.name(for: cleaned)))
    }
    func name(for id: String) -> String {
        if let cached = nameCache[id] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        let name = url.map(InstalledApp.displayName(at:)) ?? preferences.rules.first(where: { $0.id == id })?.name ?? id
        nameCache[id] = name
        return name
    }
    func ruleOutcome(_ id: String) -> String {
        // Evaluate the saved rule independently of the temporary global pause/off state.
        var value = preferences; value.enabled = true; value.pauseUntil = nil
        return value.reasonExcluded(id) == nil ? L("Will quit after the last window closes") : L("Kept running")
    }
    func removeRule(_ id: String, undoManager: UndoManager?) {
        guard let index = preferences.rules.firstIndex(where: { $0.id == id }) else { return }
        let rule = preferences.rules.remove(at: index)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] target in
            guard !target.preferences.rules.contains(where: { $0.id == id }) else { return }
            target.preferences.rules.insert(rule, at: min(index, target.preferences.rules.count))
            undoManager?.registerUndo(withTarget: target) { [weak undoManager] in $0.removeRule(id, undoManager: undoManager) }
        }
        undoManager?.setActionName(L("Remove Rule"))
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
                found[id] = InstalledApp(id: id, name: InstalledApp.displayName(at: url), url: url)
            }
            let sorted = found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { self?.installed = sorted; self?.loadingApps = false }
        }
    }
}
