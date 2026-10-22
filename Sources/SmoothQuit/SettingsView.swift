import SwiftUI
import ServiceManagement
import SmoothQuitCore

// ponytail: AppKit supplies a real preferences toolbar and selected-tab behavior.
final class SettingsTabs: NSTabViewController {
    private let defaults: UserDefaults
    private var restoring = true
    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let restored = defaults.integer(forKey: "selectedPane")
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [] // Native controls supply feedback; no extra motion to disable.
        for (index, pane) in [(L("General"), "slider.horizontal.3"), (L("Applications"), "square.grid.2x2"), (L("Activity"), "clock.arrow.circlepath")].enumerated() {
            let host = NSHostingController(rootView: SettingsView(model: model, pane: index))
            host.title = pane.0
            let item = NSTabViewItem(viewController: host)
            item.identifier = "pane-\(index)"; item.label = pane.0
            item.image = NSImage(systemSymbolName: pane.1, accessibilityDescription: pane.0)
            addTabViewItem(item)
        }
        selectedTabViewItemIndex = (0...2).contains(restored) ? restored : 0
        restoring = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if !restoring { defaults.set(selectedTabViewItemIndex, forKey: "selectedPane") }
        updateWindowTitle()
    }
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.toolbar?.allowsUserCustomization = false
        view.window?.toolbar?.displayMode = .iconAndLabel
        updateWindowTitle()
    }
    func updateWindowTitle() {
        guard isViewLoaded, tabViewItems.indices.contains(selectedTabViewItemIndex) else { return }
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var advanced = false
    var pane = 0
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch pane {
                case 1: RulesView(model: model)
                case 2: ActivityView(model: model)
                default: general
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Button(AppVersion.display) { model.onAbout?() }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                    .help(L("About SmoothQuit"))
                Spacer()
                Button(L("Quit SmoothQuit")) { NSApp.terminate(nil) }
                    .help(L("Quits SmoothQuit and stops observing apps."))
            }.padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(minWidth: 640, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("SmoothQuit", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var general: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.preferences.enabled }, set: model.setEnabled)) {
                    HStack(spacing: 12) {
                        Image(nsImage: Brand.image(size: 36, state: model.monitoringState))
                            .foregroundStyle(.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Enable SmoothQuit")).fontWeight(.medium)
                            Text(model.status).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .transaction { $0.animation = nil }
                        }
                    }
                }.toggleStyle(.switch)
                    .accessibilityLabel(L("Enable SmoothQuit"))
                    .help(L("Disabling cancels pending Quit requests. SmoothQuit keeps running."))
            }
            if !model.trusted { permissions }
            if model.monitoringState == .needsApps {
                Section {
                    HStack {
                        Text(L("No apps are allowed to quit. Add an app or change a Never quit rule."))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(L("Choose Apps…")) { chooseApps() }
                    }
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center) {
                        Text(L("Quit delay"))
                        Spacer()
                        (Text(model.preferences.delay, format: .number.precision(.fractionLength(2))) + Text(" s"))
                            .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $model.preferences.delay, in: 0.2...2, step: 0.05) {
                        Text(L("Quit delay"))
                    } minimumValueLabel: { Text(L("0.2 s")) } maximumValueLabel: { Text("2 s") }
                    .labelsHidden().accessibilityLabel(L("Quit delay"))
                    Text(L("A new window cancels the countdown. Window animations stay native."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            } header: { Text(L("Closing apps")) }
            Section {
                HStack {
                    Label(L("Pause automatic Quit"), systemImage: "pause.circle")
                    Spacer()
                    if model.preferences.enabled, model.preferences.isPaused, let until = model.preferences.pauseUntil {
                        Text(until, style: .timer).monospacedDigit().foregroundStyle(.secondary)
                            .accessibilityLabel(L("Time remaining"))
                            .accessibilityValue(Text(until, style: .timer))
                        Button(L("Resume now")) { model.pause(minutes: nil) }
                    } else {
                        Menu(L("Pause…")) {
                            ForEach([5, 15, 30, 60], id: \.self) { minutes in
                                Button(L("%d minutes", minutes)) { model.pause(minutes: minutes) }
                            }
                        }.fixedSize()
                    }
                }.disabled(!model.preferences.enabled)
            } header: { Text(L("Automation")) }
            Section {
                Toggle(isOn: $model.showInMenuBar) {
                    Label(L("Show in Menu Bar"), systemImage: "menubar.rectangle")
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(L("Show in Menu Bar"))
                    .accessibilityHint(L("Hiding the icon keeps SmoothQuit running. Return to settings through Spotlight or Finder."))
                    .help(L("Hiding the icon keeps SmoothQuit running."))
                Toggle(isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)) {
                    Label(L("Launch at login"), systemImage: "arrow.right.to.line")
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(L("Launch at login"))
                    .accessibilityHint(L("SmoothQuit starts in the background when you log in to your Mac."))
                if model.loginNeedsApproval {
                    Button(L("Approve login item in System Settings…")) { SMAppService.openSystemSettingsLoginItems() }
                }
            } header: { Text(L("Visibility and startup")) }
            Section {
                UpdateSettingsView(updates: model.updates)
            } header: { Text(L("Updates")) }
            Section {
                DisclosureGroup(isExpanded: $advanced) {
                    Toggle(L("Monitor hidden apps"), isOn: $model.preferences.monitorHidden)
                    Toggle(L("Monitor apps with minimized windows"), isOn: $model.preferences.monitorMinimized)
                    Text(L("Any existing window, including one on another Space, always prevents Quit. Turning these options off also suspends monitoring in that state."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Button { advanced.toggle() } label: {
                        HStack { Text(L("Advanced")); Spacer(minLength: 0) }
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("advancedDisclosureLabel")
                    .accessibilityValue(advanced ? L("Expanded") : L("Collapsed"))
                }
                if model.trusted {
                    Label(L("Accessibility granted"), systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }
        }.formStyle(.grouped)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: model.monitoringState)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: advanced)
    }
    private func chooseApps() {
        guard let tabs = NSApp.keyWindow?.contentViewController as? SettingsTabs else { return }
        tabs.selectedTabViewItemIndex = 1
    }
    private var permissions: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                preferenceLabel(L("Accessibility required"), symbol: "lock.shield",
                                caption: L("Allows SmoothQuit to check whether apps have open windows."))
                Spacer(minLength: 0)
                Button(L("Grant access…")) { model.requestAccessibility() }.buttonStyle(.borderedProminent).fixedSize()
            }.padding(.vertical, 3)
        } header: { Text(L("Permissions")) }
    }
    // Native labels keep captions attached to the setting they explain.
    private func preferenceLabel(_ title: String, symbol: String, caption: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(caption).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

struct RulesView: View {
    @ObservedObject var model: AppModel
    @Environment(\.undoManager) private var undoManager
    @State private var selection: String?
    @State private var query = ""
    @State private var showPicker = false
    @State private var showBundleID = false
    @State private var editingRule: AppRule?
    @State private var bundleID = ""
    private var rules: [AppRule] {
        model.preferences.rules.filter {
            query.isEmpty || model.name(for: $0.id).localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }.sorted { model.name(for: $0.id).localizedStandardCompare(model.name(for: $1.id)) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L("Automatically quit"), selection: $model.preferences.mode) {
                Text(L("Only selected apps (Include)")).tag(SelectionMode.include)
                Text(L("All apps except exceptions (Exclude)")).tag(SelectionMode.exclude)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(model.preferences.mode == .include ? L("Start safely: add one app and test how it behaves.") : L("Other regular apps may quit automatically in this mode. Add exceptions to the list."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField(L("Search apps"), text: $query).textFieldStyle(.roundedBorder)
            List(selection: $selection) {
                ForEach(rules) { rule in
                    HStack(spacing: 10) {
                        Image(nsImage: model.icon(for: rule.id)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.name(for: rule.id)).fontWeight(.medium)
                            Text(model.ruleOutcome(rule.id)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let delay = rule.delay {
                            Text(delay, format: .number.precision(.fractionLength(2))) + Text(" s")
                        }
                    }.padding(.vertical, 4).tag(rule.id)
                        .help(rule.id)
                        .contextMenu {
                            Button(L("Edit Rule…")) { editingRule = rule }
                            Button(L("Remove")) { remove(rule.id) }
                        }
                        .onTapGesture(count: 2) { editingRule = rule }
                }
            }.listStyle(.inset).overlay {
                if rules.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "app.badge").font(.largeTitle).accessibilityHidden(true)
                        Text(query.isEmpty ? (model.preferences.mode == .include ? L("Add your first app") : L("No exceptions")) : L("No Apps Found")).font(.headline)
                        Text(query.isEmpty ? (model.preferences.mode == .include ? L("An empty Include list never quits any apps.") : L("Automatic Quit applies to all eligible apps.")) : L("Try another name or Bundle ID."))
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if query.isEmpty { Button(L("Add app…")) { showPicker = true } }
                    }.padding()
                }
            }
            .onDeleteCommand { if let rule = selectedRule { remove(rule.id) } }
            HStack {
                Button(L("Remove"), systemImage: "minus") { if let rule = selectedRule { remove(rule.id) } }
                    .disabled(selectedRule == nil)
                Button(L("Edit Rule…")) { editingRule = selectedRule }
                    .disabled(selectedRule == nil)
                Spacer()
                Menu {
                    Button(L("Add app…")) { showPicker = true }
                    Button(L("Add by Bundle ID")) { showBundleID = true }
                } label: { Label(L("Add…"), systemImage: "plus") }
                .fixedSize()
            }
        }.padding(20)
        .onChange(of: rules.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        .sheet(isPresented: $showPicker) { AppPicker(model: model) }
        .sheet(item: $editingRule) { rule in RuleEditor(model: model, rule: rule) }
        .sheet(isPresented: $showBundleID) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Add by Bundle ID")).font(.headline)
                TextField(L("Bundle ID, e.g. com.apple.TextEdit"), text: $bundleID).textFieldStyle(.roundedBorder)
                if let hint = bundleIDHint {
                    Text(hint).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button(L("Cancel")) { showBundleID = false }.keyboardShortcut(.cancelAction)
                    Button(L("Add ID")) {
                        let count = model.preferences.rules.count
                        model.add(id: bundleID)
                        if model.preferences.rules.count > count { bundleID = ""; showBundleID = false }
                    }.keyboardShortcut(.defaultAction)
                        .disabled(!Preferences.validBundleID(bundleID.trimmingCharacters(in: .whitespacesAndNewlines)) || bundleIDHint != nil)
                }
            }.padding(24).frame(width: 420)
        }
    }
    private func remove(_ id: String) {
        model.removeRule(id, undoManager: undoManager)
        if selection == id { selection = nil }
    }
    private var selectedRule: AppRule? { rules.first { $0.id == selection } }
    private var bundleIDHint: String? {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id == "pl.smoothquit.app" || id == Bundle.main.bundleIdentifier { return L("SmoothQuit always protects itself.") }
        if model.preferences.rules.contains(where: { $0.id == id }) { return L("Already added. Select this app in the list to edit its rule.") }
        return nil
    }
}

struct RuleEditor: View {
    @ObservedObject var model: AppModel
    let rule: AppRule
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let binding = model.binding(for: rule)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: model.icon(for: rule.id)).resizable().frame(width: 40, height: 40).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name(for: rule.id)).font(.headline)
                    Text(rule.id).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
            }.padding(20)
            Form {
                Section {
                    Picker(L("Automatic Quit"), selection: binding.behavior) {
                        Text(L("Follow mode")).tag(RuleBehavior.mode)
                        Text(L("Always allow")).tag(RuleBehavior.allow)
                        Text(L("Never quit")).tag(RuleBehavior.never)
                    }
                    Text(model.ruleOutcome(rule.id)).font(.callout).foregroundStyle(.secondary)
                    Toggle(L("Custom delay"), isOn: Binding(get: { binding.wrappedValue.delay != nil }, set: {
                        binding.wrappedValue.delay = $0 ? model.preferences.delay : nil
                    }))
                    if let delay = binding.wrappedValue.delay {
                        HStack {
                            Slider(value: Binding(get: { binding.wrappedValue.delay ?? 0.5 }, set: { binding.wrappedValue.delay = $0 }), in: 0.2...2, step: 0.05) { Text(L("App-specific delay")) }
                            (Text(delay, format: .number.precision(.fractionLength(2))) + Text(" s")).monospacedDigit().frame(width: 60)
                        }
                    }
                    if rule.id == "com.apple.finder" {
                        Text(L("Finder is protected by default. Only an explicit Always allow rule enables automatic Quit.")).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }.formStyle(.grouped)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: binding.wrappedValue.delay != nil)
            HStack {
                Button(L("Reset Rule")) { binding.wrappedValue = AppRule(id: rule.id, name: rule.name) }
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 500, height: 360).onExitCommand { dismiss() }
    }
}

struct AppPicker: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = Set<String>()
    @State private var showBackground = false
    private var apps: [InstalledApp] {
        model.installed.filter { (showBackground || !$0.isBackground) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Installed apps")).font(.title2.bold())
            TextField(L("Search by name or Bundle ID"), text: $query).textFieldStyle(.roundedBorder)
            Toggle(L("Show background and helper apps"), isOn: $showBackground).font(.callout)
            if model.loadingApps { ProgressView(L("Loading apps…")) }
            List(apps, selection: $selected) { app in
                HStack {
                    Image(nsImage: model.icon(for: app.id)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    Text(app.name)
                }.tag(app.id).help(app.id)
            }.overlay {
                if !model.loadingApps && apps.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title).accessibilityHidden(true)
                        Text(L("No Apps Found")).font(.headline)
                        Text(L("Try another search or choose an .app file.")).foregroundStyle(.secondary)
                        Button(L("Clear Search")) { query = "" }.disabled(query.isEmpty)
                    }
                }
            }
            HStack {
                Button(L("Choose .app file…")) { chooseFile() }
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Add selected")) {
                    for app in apps where selected.contains(app.id) { model.add(id: app.id, name: app.name) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(!apps.contains { selected.contains($0.id) })
            }
        }.padding(24).frame(width: 580, height: 480).onAppear { model.loadInstalledApps() }
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                if let id = Bundle(url: url)?.bundleIdentifier { model.add(id: id, name: url.deletingPathExtension().lastPathComponent) }
            }
            dismiss()
        }
    }
}

struct ActivityView: View {
    @ObservedObject var model: AppModel
    @State private var activityMode = 0
    @State private var query = ""
    @State private var snapshot: [Diagnostic] = []
    @State private var showInspection = false
    private var rawDiagnostics: Bool { activityMode == 2 }
    private var entries: [Diagnostic] {
        (rawDiagnostics ? snapshot : Diagnostic.activityEntries(snapshot, historyOnly: activityMode == 1)).filter {
            query.isEmpty || model.name(for: $0.bundleID).localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query)
        }
    }
    private var newCount: Int {
        guard let newest = snapshot.first?.id else { return model.diagnostics.count }
        return model.diagnostics.prefix { $0.id != newest }.count
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(L("View"), selection: $activityMode) {
                    Text(L("Recent Activity")).tag(0)
                    Text(L("Quit history")).tag(1)
                    Text(L("Diagnostics")).tag(2)
                }.frame(width: 240)
                Spacer()
                if rawDiagnostics { Button(L("Restart Monitoring")) { model.refresh() } }
                Button(L("Clear")) { model.diagnostics.removeAll(); snapshot = [] }.disabled(model.diagnostics.isEmpty)
            }
            TextField(L("Filter by app"), text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Button(L("Why Is This App Still Running?")) { showInspection = true }
                Spacer()
                Button(L("Copy Diagnostic Report")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.diagnosticReport(entries: entries), forType: .string)
                }.help(L("Includes version, macOS, rules and up to 20 displayed events. Nothing is sent automatically."))
            }
            if newCount > 0 {
                Button(L("Show %d New Events", newCount)) { snapshot = model.diagnostics }
                    .help(L("Updates wait here so the list does not move while you read."))
            }
            List(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(nsImage: model.icon(for: entry.bundleID)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.name(for: entry.bundleID)).fontWeight(.medium)
                            Spacer()
                            Text(entry.date, style: .time).font(.callout).foregroundStyle(.secondary)
                        }
                        Text(rawDiagnostics ? entry.message : entry.activityMessage).textSelection(.enabled)
                        if rawDiagnostics {
                            Text(entry.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        if let elapsed = entry.elapsed {
                            Text(L("Measured time: %.3f s", elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if !rawDiagnostics, entry.completed, let quitID = entry.quitID,
                           let request = snapshot.first(where: { $0.requested && $0.quitID == quitID }) {
                            DisclosureGroup(L("Quit Details")) {
                                Text(request.message).font(.callout).textSelection(.enabled)
                                if let elapsed = request.elapsed { Text(L("Quit requested after %.3f s", elapsed)).font(.callout.monospacedDigit()) }
                                Text(entry.message).font(.callout).textSelection(.enabled)
                            }
                        }
                    }
                }.padding(.vertical, 5)
                    .contextMenu {
                        Button(L("Copy Details")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("\(entry.bundleID)\n\(entry.date.formatted())\n\(entry.message)\n\(entry.elapsed.map { String(format: "%.3f s", $0) } ?? "")", forType: .string)
                        }
                    }
            }.overlay {
                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath").font(.title).accessibilityHidden(true)
                        Text(query.isEmpty ? L("No activity yet") : L("No Apps Found")).font(.headline)
                        Text(query.isEmpty ? L("Quit requests, completed quits and cancelled decisions appear here.") : L("Try another name or Bundle ID."))
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding().allowsHitTesting(false)
                }
            }
            Text(L("Session only. A Quit request is not a confirmed exit. No window titles or document contents are recorded."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(20)
            .sheet(isPresented: $showInspection) { InspectionView(model: model) }
            .onAppear { snapshot = model.diagnostics }
            .onChange(of: model.diagnostics.first?.id) { _, _ in
                if snapshot.isEmpty { snapshot = model.diagnostics }
            }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject var updates: UpdateChecker
    var showAutomaticToggle = true
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showAutomaticToggle {
                Toggle(L("Check for updates at launch"), isOn: $updates.automaticallyChecks)
            }
            HStack {
                Button(L("Check for Updates…")) { updates.check() }.disabled(updates.isChecking)
                if updates.isChecking { ProgressView().controlSize(.small) }
                if updates.availableRelease != nil { Button(L("View Release…")) { updates.openRelease() } }
            }
            Text(updates.phase.message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let hint = updates.notificationHint {
                Text(hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct AboutView: View {
    @ObservedObject var updates: UpdateChecker
    let close: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72).accessibilityHidden(true)
                    Text("SmoothQuit").font(.title2.bold())
                    Text(L("Version %@ (Build %@)", AppVersion.number, AppVersion.build)).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(L("Close the last window. Let the app leave quietly."))
                        .multilineTextAlignment(.center)
                    HStack {
                        Link("GitHub", destination: AppVersion.repository)
                        Text("·").foregroundStyle(.secondary)
                        Link(L("MIT License"), destination: AppVersion.repository.appendingPathComponent("blob/main/LICENSE"))
                    }
                    Divider().padding(.vertical, 4)
                    UpdateSettingsView(updates: updates, showAutomaticToggle: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(24)
            }
            HStack {
                Spacer()
                Button(L("Done"), action: close).keyboardShortcut(.defaultAction)
            }.padding(16)
        }.frame(width: 460, height: 440).background(Color(nsColor: .windowBackgroundColor))
            .onExitCommand(perform: close)
    }
}

struct InspectionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [NSRunningApplication] = []
    @State private var selection: pid_t = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Why Is This App Still Running?")).font(.headline)
            Picker(L("Application"), selection: $selection) {
                Text(L("Choose an app")).tag(pid_t(0))
                ForEach(apps, id: \.processIdentifier) { app in
                    Text((app.localizedName ?? app.bundleIdentifier ?? "—") + (apps.filter { $0.bundleIdentifier == app.bundleIdentifier }.count > 1 ? " (\(app.processIdentifier))" : ""))
                        .tag(app.processIdentifier)
                }
            }.disabled(model.isInspecting)
            Text(model.inspection.isEmpty ? L("Choose a running app to read its current state. This never sends Quit.") : model.inspection)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if model.isInspecting { ProgressView().controlSize(.small) }
            Spacer(minLength: 0)
            HStack {
                Button(L("Check Again")) { model.inspect(selection) }.disabled(selection == 0 || model.isInspecting)
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500, height: 280)
            .onAppear {
                model.inspection = ""
                apps = NSWorkspace.shared.runningApplications.filter {
                    $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != "pl.smoothquit.app"
                }.sorted { ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending }
            }
            .onChange(of: selection) { _, pid in if pid > 0 { model.inspect(pid) } }
            .onExitCommand { dismiss() }
    }
}
