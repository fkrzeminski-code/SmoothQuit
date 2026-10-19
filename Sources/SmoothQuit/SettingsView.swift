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
        for (index, pane) in [("Ogólne", "slider.horizontal.3"), ("Aplikacje", "square.grid.2x2"), ("Aktywność", "clock.arrow.circlepath")].enumerated() {
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
                Text("Zmiany są zapisywane automatycznie.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Quit SmoothQuit") { NSApp.terminate(nil) }
                    .help("Kończy cały program i wyłącza obserwację aplikacji.")
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
                            Text("Enable SmoothQuit").fontWeight(.medium)
                            Text(model.status).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.toggleStyle(.switch)
                    .accessibilityLabel("Enable SmoothQuit")
                    .help("Wyłączenie anuluje oczekujące Quit. SmoothQuit pozostaje uruchomiony.")
            }
            if !model.trusted { permissions }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center) {
                        Text("Opóźnienie zamknięcia")
                        Spacer()
                        (Text(model.preferences.delay, format: .number.precision(.fractionLength(2))) + Text(" s"))
                            .font(.body.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: $model.preferences.delay, in: 0.2...2, step: 0.05) {
                        Text("Opóźnienie Quit")
                    } minimumValueLabel: { Text("0,2 s") } maximumValueLabel: { Text("2 s") }
                    .labelsHidden().accessibilityLabel("Opóźnienie Quit")
                    Text("Po zamknięciu ostatniego okna. Nowe okno anuluje odliczanie, a animacją zarządza macOS.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.vertical, 4)
            } header: { Text("Zamykanie aplikacji") }
            Section {
                HStack {
                    Label("Pauza automatycznego Quit", systemImage: "pause.circle")
                    Spacer()
                    if model.preferences.isPaused, let until = model.preferences.pauseUntil {
                        Text("Do \(until.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                        Button("Wznów teraz") { model.pause(minutes: nil) }
                    } else {
                        Menu("Wstrzymaj…") {
                            ForEach([5, 15, 30, 60], id: \.self) { minutes in
                                Button("\(minutes) minut") { model.pause(minutes: minutes) }
                            }
                        }.fixedSize()
                    }
                }
                DisclosureGroup("Okna ukryte i zminimalizowane") {
                    Toggle("Monitoruj ukryte aplikacje", isOn: $model.preferences.monitorHidden)
                    Toggle("Monitoruj przy zminimalizowanych oknach", isOn: $model.preferences.monitorMinimized)
                    Text("Każde istniejące okno, także na innym Space, zawsze blokuje Quit. Wyłączenie tych opcji dodatkowo wstrzymuje obsługę danego stanu.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("Kontrola działania") }
            Section {
                Toggle(isOn: $model.showInMenuBar) {
                    preferenceLabel("Show in Menu Bar", symbol: "menubar.rectangle",
                                    caption: "Po ukryciu ikony wrócisz do ustawień przez Spotlight lub Finder.")
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Show in Menu Bar")
                    .accessibilityHint("Ukrycie ikony nie wyłącza SmoothQuit. Wrócisz do ustawień przez Spotlight lub Finder.")
                    .help("Ukrycie ikony nie wyłącza SmoothQuit.")
                Toggle(isOn: Binding(get: { model.loginEnabled }, set: model.setLogin)) {
                    preferenceLabel("Uruchamiaj przy logowaniu", symbol: "arrow.right.to.line",
                                    caption: "SmoothQuit rozpocznie pracę w tle po zalogowaniu do Maca.")
                }.toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Uruchamiaj przy logowaniu")
                    .accessibilityHint("SmoothQuit rozpocznie pracę w tle po zalogowaniu do Maca.")
                if model.loginNeedsApproval {
                    Button("Zatwierdź autostart w Ustawieniach systemowych…") { SMAppService.openSystemSettingsLoginItems() }
                }
            } header: { Text("Widoczność i uruchamianie") }
            if model.trusted { permissions }
        }.formStyle(.grouped)
    }
    private var permissions: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                preferenceLabel(model.trusted ? "Dostępność przyznana" : "Wymagana Dostępność",
                                symbol: model.trusted ? "checkmark.shield" : "lock.shield",
                                caption: "Pozwala sprawdzać, czy aplikacja ma otwarte okna.")
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if !model.trusted {
                        Button("Nadaj dostęp…") { model.requestAccessibility() }.buttonStyle(.borderedProminent)
                    }
                    if model.trusted {
                        Button("Sprawdź ponownie") { model.refresh() }
                    }
                }.fixedSize()
            }.padding(.vertical, 3)
        } header: { Text("Uprawnienia") }
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
                Picker("Tryb", selection: $model.preferences.mode) {
                    Text("Include — tylko z listy").tag(SelectionMode.include)
                    Text("Exclude — poza listą").tag(SelectionMode.exclude)
                }.pickerStyle(.segmented)
                Text(model.preferences.mode == .include ? "Bezpieczny start: dodaj jedną aplikację i sprawdź jej działanie." : "W tym trybie pozostałe zwykłe aplikacje mogą być zamykane. Dodaj wyjątki do listy.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Tryb działania") }
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
                            Text(rule.behavior == .mode ? "Zgodnie z trybem" : rule.behavior == .allow ? "Zawsze" : "Nigdy")
                                .font(.callout).foregroundStyle(.secondary)
                        }.padding(.vertical, 3).tag(rule.id)
                    }
                }.overlay {
                    if model.preferences.rules.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "app.badge").font(.largeTitle)
                            Text(model.preferences.mode == .include ? "Dodaj pierwszą aplikację" : "Brak wyjątków").font(.headline)
                            Text(model.preferences.mode == .include ? "W trybie Include pusta lista nie zamyka żadnej aplikacji." : "Dodaj aplikacje, które mają pozostać uruchomione.").foregroundStyle(.secondary)
                        }.allowsHitTesting(false)
                    }
                }.frame(height: 200).listStyle(.inset).scrollContentBackground(.hidden)
                HStack {
                    Button("Usuń", systemImage: "minus") {
                        model.preferences.rules.removeAll { $0.id == selection }; selection = nil
                    }.disabled(selection == nil)
                    Spacer()
                    Button("Dodaj aplikację…", systemImage: "plus") { showPicker = true }
                }
            } header: { Text(model.preferences.mode == .include ? "Wybrane aplikacje" : "Wyjątki") }
            Section {
                DisclosureGroup("Dodaj przez Bundle ID") {
                    HStack {
                        TextField("Bundle ID, np. com.apple.TextEdit", text: $bundleID).textFieldStyle(.roundedBorder)
                            .onSubmit(addBundle)
                        Button("Dodaj ID", action: addBundle).disabled(bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.padding(.top, 6)
                }
            }
            if let selection, let rule = model.preferences.rules.first(where: { $0.id == selection }) {
                let binding = model.binding(for: rule)
                Section {
                    Picker("Automatyczne Quit", selection: binding.behavior) {
                        Text("Zgodnie z trybem").tag(RuleBehavior.mode)
                        Text("Zawsze zezwalaj").tag(RuleBehavior.allow)
                        Text("Nigdy nie zamykaj").tag(RuleBehavior.never)
                    }
                    Toggle("Własne opóźnienie", isOn: Binding(get: { binding.wrappedValue.delay != nil }, set: {
                        binding.wrappedValue.delay = $0 ? model.preferences.delay : nil
                    }))
                    if let delay = binding.wrappedValue.delay {
                        HStack {
                            Slider(value: Binding(get: { binding.wrappedValue.delay ?? 0.5 }, set: { binding.wrappedValue.delay = $0 }), in: 0.2...2, step: 0.05) { Text("Opóźnienie dla aplikacji") }
                            Text(String(format: "%.2f s", delay)).monospacedDigit().frame(width: 60)
                        }
                    }
                    if selection == "com.apple.finder" {
                        Text("Finder jest domyślnie chroniony. Tylko jawna reguła „Zawsze zezwalaj” umożliwia jego zamykanie.").font(.callout).foregroundStyle(.secondary)
                    }
                } header: { Text("Reguła: \(rule.name)") }
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
            Text("Zainstalowane aplikacje").font(.title2.bold())
            TextField("Szukaj po nazwie lub Bundle ID", text: $query).textFieldStyle(.roundedBorder)
            if model.loadingApps { ProgressView("Wczytywanie aplikacji…") }
            List(model.installed.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }, selection: $selected) { app in
                HStack {
                    Image(nsImage: model.icon(for: app.id)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                    VStack(alignment: .leading) { Text(app.name); Text(app.id).font(.caption).foregroundStyle(.secondary) }
                }.tag(app.id)
            }
            HStack {
                Button("Wybierz plik .app…") { chooseFile() }
                Spacer()
                Button("Anuluj") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Dodaj zaznaczone") {
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
                Picker("Widok", selection: $historyOnly) {
                    Text("Diagnostyka").tag(false); Text("Historia Quit").tag(true)
                }.pickerStyle(.segmented).frame(maxWidth: 260)
                Spacer()
                Button("Odśwież obserwację") { model.refresh() }
                Button("Wyczyść") { model.diagnostics.removeAll() }.disabled(model.diagnostics.isEmpty)
            }
            Text("Ostatnie 200 zdarzeń, wyłącznie w pamięci tej sesji. Brak tytułów okien i treści dokumentów.")
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
                            Text(String(format: "Zmierzony czas: %.3f s", elapsed)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }.padding(.vertical, 5)
            }.overlay {
                if entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: historyOnly ? "clock.arrow.circlepath" : "waveform.path").font(.title)
                            .accessibilityHidden(true)
                        Text(historyOnly ? "Brak automatycznych zamknięć" : "Brak zdarzeń").font(.headline)
                        Text(historyOnly ? "Historia pojawi się po pierwszym żądaniu Quit w tej sesji." : "Zdarzenia pojawią się po włączeniu obserwacji wybranej aplikacji.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding().allowsHitTesting(false)
                }
            }
            Text("„Wysłano Quit” nie oznacza zakończenia procesu. Aplikacja może poprosić o zapis lub odmówić. SmoothQuit nie ponawia żądania i nigdy nie wymusza zamknięcia.")
                .font(.callout).foregroundStyle(.secondary)
        }.padding(20)
    }
}
