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
                Text(L("Changes are saved automatically."))
                    .font(.callout).foregroundStyle(.secondary)
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
                Toggle(isOn: $model.preferences.enabled) {
                    HStack(spacing: 12) {
                        Image(nsImage: Brand.image(size: 36))
                            .foregroundStyle(.tint).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Enable SmoothQuit")).fontWeight(.medium)
                            Text(model.status).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.toggleStyle(.switch)
                    .accessibilityLabel(L("Enable SmoothQuit"))
                    .help(L("Disabling cancels pending Quit requests. SmoothQuit keeps running."))
            }
            if !model.trusted { permissions }
            Section {
                VStack(alignment: .leading, spacing: 12) {
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
                    Text(L("After the last window closes. A new window cancels the countdown; macOS handles the animation."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            } header: { Text(L("Closing apps")) }
            Section {
                HStack {
                    Label(L("Pause automatic Quit"), systemImage: "pause.circle")
                    Spacer()
                    if model.preferences.isPaused, let until = model.preferences.pauseUntil {
                        Text(L("Until %@", until.formatted(date: .omitted, time: .shortened))).foregroundStyle(.secondary)
                        Button(L("Resume now")) { model.pause(minutes: nil) }
                    } else {
                        Menu(L("Pause…")) {
                            ForEach([5, 15, 30, 60], id: \.self) { minutes in
                                Button(L("%d minutes", minutes)) { model.pause(minutes: minutes) }
                            }
                        }.fixedSize()
                    }
                }
                DisclosureGroup(L("Hidden and minimized windows")) {
                    Toggle(L("Monitor hidden apps"), isOn: $model.preferences.monitorHidden)
                    Toggle(L("Monitor apps with minimized windows"), isOn: $model.preferences.monitorMinimized)
                    Text(L("Any existing window, including one on another Space, always prevents Quit. Turning these options off also suspends monitoring in that state."))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text(L("Automation")) }
            Section {
                Toggle(isOn: $model.showInMenuBar) {
                    preferenceLabel(L("Show in Menu Bar"), symbol: "menubar.rectangle",
                                    caption: L("Open SmoothQuit from Spotlight or Finder to return to settings when the icon is hidden."))
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(L("Show in Menu Bar"))
                    .accessibilityHint(L("Hiding the icon keeps SmoothQuit running. Return to settings through Spotlight or Finder."))
                    .help(L("Hiding the icon keeps SmoothQuit running."))
                Toggle(isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)) {
                    preferenceLabel(L("Launch at login"), symbol: "arrow.right.to.line",
                                    caption: L("SmoothQuit starts in the background when you log in to your Mac."))
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel(L("Launch at login"))
                    .accessibilityHint(L("SmoothQuit starts in the background when you log in to your Mac."))
                if model.loginNeedsApproval {
                    Button(L("Approve login item in System Settings…")) { SMAppService.openSystemSettingsLoginItems() }
                }
            } header: { Text(L("Visibility and startup")) }
            if model.trusted { permissions }
        }.formStyle(.grouped)
    }
    private var permissions: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                preferenceLabel(model.trusted ? L("Accessibility granted") : L("Accessibility required"),
                                symbol: model.trusted ? "checkmark.shield" : "lock.shield",
                                caption: L("Allows SmoothQuit to check whether apps have open windows."))
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if !model.trusted {
                        Button(L("Grant access…")) { model.requestAccessibility() }.buttonStyle(.borderedProminent)
                    }
                    if model.trusted {
                        Button(L("Check again")) { model.refresh() }
                    }
                }.fixedSize()
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
    @State private var selection: String?
    @State private var showPicker = false
    @State private var bundleID = ""
    var body: some View {
        Form {
            Section {
                Picker(L("Mode"), selection: $model.preferences.mode) {
                    Text(L("Include — selected apps only")).tag(SelectionMode.include)
                    Text(L("Exclude — all except listed")).tag(SelectionMode.exclude)
                }.pickerStyle(.segmented)
                Text(model.preferences.mode == .include ? L("Start safely: add one app and test how it behaves.") : L("Other regular apps may quit automatically in this mode. Add exceptions to the list."))
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text(L("Selection mode")) }
            Section {
                List(selection: $selection) {
                    ForEach(model.preferences.rules) { rule in
                        HStack(spacing: 10) {
                            Image(nsImage: model.icon(for: rule.id)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(rule.name)
                                Text(rule.id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(rule.behavior == .mode ? L("Follow mode") : rule.behavior == .allow ? L("Always") : L("Never"))
                                .font(.callout).foregroundStyle(.secondary)
                        }.padding(.vertical, 3).tag(rule.id)
                    }
                }.overlay {
                    if model.preferences.rules.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "app.badge").font(.largeTitle)
                            Text(model.preferences.mode == .include ? L("Add your first app") : L("No exceptions")).font(.headline)
                            Text(model.preferences.mode == .include ? L("An empty Include list never quits any apps.") : L("Add apps you want to keep running.")).foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }.frame(height: 200).listStyle(.inset).scrollContentBackground(.hidden)
                HStack {
                    Button(L("Remove"), systemImage: "minus") {
                        model.preferences.rules.removeAll { $0.id == selection }; selection = nil
                    }.disabled(selection == nil)
                    Spacer()
                    Button(L("Add app…"), systemImage: "plus") { showPicker = true }
                }
            } header: { Text(model.preferences.mode == .include ? L("Selected apps") : L("Exceptions")) }
            Section {
                DisclosureGroup(L("Add by Bundle ID")) {
                    HStack {
                        TextField(L("Bundle ID, e.g. com.apple.TextEdit"), text: $bundleID).textFieldStyle(.roundedBorder)
                            .onSubmit(addBundle)
                        Button(L("Add ID"), action: addBundle).disabled(bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.top, 6)
                }
            }
            if let selection, let rule = model.preferences.rules.first(where: { $0.id == selection }) {
                let binding = model.binding(for: rule)
                Section {
                    Picker(L("Automatic Quit"), selection: binding.behavior) {
                        Text(L("Follow mode")).tag(RuleBehavior.mode)
                        Text(L("Always allow")).tag(RuleBehavior.allow)
                        Text(L("Never quit")).tag(RuleBehavior.never)
                    }
                    Toggle(L("Custom delay"), isOn: Binding(get: { binding.wrappedValue.delay != nil }, set: {
                        binding.wrappedValue.delay = $0 ? model.preferences.delay : nil
                    }))
                    if let delay = binding.wrappedValue.delay {
                        HStack {
                            Slider(value: Binding(get: { binding.wrappedValue.delay ?? 0.5 }, set: { binding.wrappedValue.delay = $0 }), in: 0.2...2, step: 0.05) { Text(L("App-specific delay")) }
                            Text(String(format: "%.2f s", delay)).monospacedDigit().frame(width: 60)
                        }
                    }
                    if selection == "com.apple.finder" {
                        Text(L("Finder is protected by default. Only an explicit Always allow rule enables automatic Quit.")).font(.callout).foregroundStyle(.secondary)
                    }
                } header: { Text(L("Rule: %@", rule.name)) }
            }
        }.formStyle(.grouped)
        .sheet(isPresented: $showPicker) { AppPicker(model: model) }
    }
    private func addBundle() { model.add(id: bundleID); bundleID = "" }
}

struct AppPicker: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = Set<String>()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Installed apps")).font(.title2.bold())
            TextField(L("Search by name or Bundle ID"), text: $query).textFieldStyle(.roundedBorder)
            if model.loadingApps { ProgressView(L("Loading apps…")) }
            List(model.installed.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }, selection: $selected) { app in
                HStack {
                    Image(nsImage: model.icon(for: app.id)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading) { Text(app.name); Text(app.id).font(.caption).foregroundStyle(.secondary) }
                }.tag(app.id)
            }
            HStack {
                Button(L("Choose .app file…")) { chooseFile() }
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Add selected")) {
                    for app in model.installed where selected.contains(app.id) { model.add(id: app.id, name: app.name) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(selected.isEmpty)
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
    @State private var historyOnly = false
    private var entries: [Diagnostic] {
        model.diagnostics.filter { !historyOnly || $0.requested || $0.completed }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker(L("View"), selection: $historyOnly) {
                    Text(L("Diagnostics")).tag(false); Text(L("Quit history")).tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 260)
                Spacer()
                Button(L("Refresh monitoring")) { model.refresh() }
                Button(L("Clear")) { model.diagnostics.removeAll() }.disabled(model.diagnostics.isEmpty)
            }
            Text(L("The last 200 events, held only in memory for this session. No window titles or document contents."))
                .font(.callout).foregroundStyle(.secondary)
            List(entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: entry.completed ? "checkmark.circle" : entry.requested ? "arrow.right.circle" : "info.circle").frame(width: 20).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.bundleID).fontWeight(.medium)
                            Spacer()
                            Text(entry.date, style: .time).foregroundStyle(.secondary)
                        }
                        Text(entry.message).textSelection(.enabled)
                        if let elapsed = entry.elapsed {
                            Text(L("Measured time: %.3f s", elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.vertical, 5)
            }.overlay {
                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: historyOnly ? "clock.arrow.circlepath" : "waveform.path").font(.title)
                            .accessibilityHidden(true)
                        Text(historyOnly ? L("No automatic quits yet") : L("No events yet")).font(.headline)
                        Text(historyOnly ? L("History appears after the first Quit request in this session.") : L("Events appear when monitoring is enabled for a selected app."))
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding().allowsHitTesting(false)
                }
            }
            Text(L("A Quit request does not mean the process has exited. An app may ask you to save or refuse to quit. SmoothQuit never repeats the request or force-quits."))
                .font(.callout).foregroundStyle(.secondary)
        }.padding(20)
    }
}
