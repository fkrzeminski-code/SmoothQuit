import AppKit
import ApplicationServices
import SmoothQuitCore

struct Diagnostic: Identifiable {
    let id = UUID()
    let date = Date()
    let bundleID: String
    let message: String
    var requested = false
    var completed = false
    var elapsed: Double?
    var summary: String?
    var quitID: UUID?
    var activityMessage: String {
        if completed { return L("Exited after a normal Quit request") }
        if requested { return L("Quit requested — waiting for the app to exit") }
        return summary ?? message
    }
    static func activityEntries(_ entries: [Diagnostic], historyOnly: Bool) -> [Diagnostic] {
        let completed = Set(entries.filter(\.completed).compactMap(\.quitID))
        return entries.filter {
            ($0.summary != nil || $0.requested || $0.completed) &&
            (!historyOnly || $0.requested || $0.completed) &&
            !($0.requested && $0.quitID.map { completed.contains($0) } == true)
        }
    }
}

// ponytail: one serial queue owns all AX state; the main run loop only forwards events.
// A fence invalidates in-flight reads immediately, even while the worker is inside AX IPC.
final class EventFence {
    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var globalRevision: UInt64 = 0
    private var processRevisions: [pid_t: UInt64] = [:]
    private func current(_ pid: pid_t?) -> UInt64 {
        max(globalRevision, pid.flatMap { processRevisions[$0] } ?? 0)
    }
    @discardableResult
    func invalidate(pid: pid_t? = nil) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        revision &+= 1
        if let pid { processRevisions[pid] = revision }
        else { globalRevision = revision; processRevisions.removeAll() }
        return revision
    }
    func snapshot(pid: pid_t? = nil) -> UInt64 {
        lock.lock(); defer { lock.unlock() }; return current(pid)
    }
    func perform(ifUnchanged expected: UInt64, pid: pid_t? = nil, _ action: () -> Bool) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        guard expected == current(pid) else { return nil }
        return action()
    }
}

enum WindowReadError: Error, CustomStringConvertible {
    case ax(String, Int32), malformed, budget, subscription(Int32)
    var isTransient: Bool {
        switch self {
        case .ax(_, let code), .subscription(let code): return code == AXError.cannotComplete.rawValue
        case .malformed, .budget: return false
        }
    }
    var description: String {
        switch self {
        case let .ax(attribute, code): return L("AX %@: error %d", attribute, code)
        case .malformed: return L("Incomplete or invalid AX window list")
        case .budget: return L("AX read exceeded its 350 ms / 256 window budget")
        case let .subscription(code): return L("Cannot observe window destruction: %d", code)
        }
    }
}

/// Public APIs only. Never reads window titles, documents, keyboard events or images.
enum WindowReader {
    static func value(_ element: AXUIElement, _ attribute: String) throws -> CFTypeRef {
        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
        guard error == .success, let result else { throw WindowReadError.ax(attribute, error.rawValue) }
        return result
    }
    static func windows(_ element: AXUIElement, discovered: ([AXUIElement]) -> Void = { _ in },
                        read: (AXUIElement, String) throws -> CFTypeRef = value) throws -> [AXUIElement] {
        let value = try read(element, kAXWindowsAttribute)
        guard CFGetTypeID(value) == CFArrayGetTypeID(), let windows = value as? [AXUIElement],
              windows.allSatisfy({ CFGetTypeID($0) == AXUIElementGetTypeID() }) else { throw WindowReadError.malformed }
        guard windows.count <= 256 else { throw WindowReadError.budget }
        var result = windows
        // Retain known identities even if a later supplemental read fails.
        // Incomplete reads still throw; discovery is never proof that Quit is safe.
        discovered(result)
        // Catalyst apps can expose a real main/focused window while AXWindows is
        // successfully empty. These are additive identities, never replacements
        // for AXWindows or the off-Space ledger.
        for attribute in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            let raw: CFTypeRef
            do { raw = try read(element, attribute) }
            catch WindowReadError.ax(_, let code) where code == AXError.attributeUnsupported.rawValue || code == AXError.noValue.rawValue { continue }
            guard CFGetTypeID(raw) == AXUIElementGetTypeID() else { throw WindowReadError.malformed }
            let window = unsafeBitCast(raw, to: AXUIElement.self)
            if !result.contains(where: { CFEqual($0, window) }) {
                result.append(window)
                discovered([window])
            }
        }
        guard result.count <= 256 else { throw WindowReadError.budget }
        return result
    }
    static func metadata(_ element: AXUIElement, id: UInt64) throws -> ObservedWindow {
        AXUIElementSetMessagingTimeout(element, 0.12)
        var values: CFArray?
        let attributes = [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute] as CFArray
        let error = AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values)
        guard error == .success else { throw WindowReadError.ax("metadata", error.rawValue) }
        guard let fields = values as? [Any] else { throw WindowReadError.malformed }
        return try metadata(fields: fields, id: id)
    }
    static func metadata(fields: [Any], id: UInt64) throws -> ObservedWindow {
        guard fields.count == 3, let role = fields[0] as? String,
              let subrole = fields[1] as? String else { throw WindowReadError.malformed }
        let normal = role == kAXWindowRole && subrole == kAXStandardWindowSubrole
        // Auxiliary windows always veto Quit and never arm it. Some panels do not
        // implement AXMinimized; that cannot make them disappear from the ledger.
        guard !normal || fields[2] is Bool else { throw WindowReadError.malformed }
        return ObservedWindow(id, normal ? .normal : .auxiliary, minimized: fields[2] as? Bool ?? false)
    }
    static func observeDestruction(_ observer: AXObserver, element: AXUIElement, context: UnsafeMutableRawPointer?) throws {
        let error = AXObserverAddNotification(observer, element, kAXUIElementDestroyedNotification as CFString, context)
        guard error == .success || error == .notificationAlreadyRegistered else { throw WindowReadError.subscription(error.rawValue) }
    }
    static func cgHasWindows(pid: pid_t) -> Bool? {
        // AX and its identity ledger protect other Spaces, minimized and hidden windows.
        // WindowServer keeps off-screen backing surfaces after AX destruction (TextEdit).
        // Only a visible layer-zero surface is an independent CG veto; no size heuristics.
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        return visibleCGWindow(in: list, pid: pid)
    }
    static func visibleCGWindow(in list: [[String: Any]], pid: pid_t) -> Bool? {
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? Int else { return nil }
            guard owner == Int(pid) else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int else { return nil }
            if layer == 0 && (info[kCGWindowIsOnscreen as String] as? Bool == true) { return true }
        }
        return false
    }
}

final class Monitor {
    private final class ObserverContext {
        weak var monitor: Monitor?
        let pid: pid_t
        init(_ monitor: Monitor, pid: pid_t) { self.monitor = monitor; self.pid = pid }
    }
    private final class Watch {
        let app: NSRunningApplication
        let element: AXUIElement
        let observer: AXObserver
        let context: ObserverContext
        var tracked: [(id: UInt64, element: AXUIElement, subscribed: Bool)] = []
        var gate = CloseGate()
        var timer: DispatchWorkItem?
        var readRetry: DispatchWorkItem?
        var readWasTransient = false
        var requestedAt: Double?
        var closeAt: Double?
        var quitID: UUID?
        var terminationObservation: NSKeyValueObservation?
        init(app: NSRunningApplication, element: AXUIElement, observer: AXObserver, context: ObserverContext) {
            self.app = app; self.element = element; self.observer = observer; self.context = context
        }
    }
    private let queue = DispatchQueue(label: "pl.smoothquit.accessibility", qos: .userInitiated)
    private let fence = EventFence()
    private let settingsFence = EventFence()
    private var watches: [pid_t: Watch] = [:]
    private var attachmentRetries: [pid_t: DispatchWorkItem] = [:]
    private var launchObservations: [pid_t: NSKeyValueObservation] = [:]
    private var nextID: UInt64 = 0
    private var preferences = Preferences()
    private var workspaceTokens: [NSObjectProtocol] = []
    private var wakeTimer: DispatchWorkItem?
    var onDiagnostic: ((Diagnostic) -> Void)?
    var onPermission: ((Bool) -> Void)?
    private var ownID: String { Bundle.main.bundleIdentifier ?? "pl.smoothquit.app" }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    deinit {
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        wakeTimer?.cancel()
        for work in attachmentRetries.values { work.cancel() }
        for observation in launchObservations.values { observation.invalidate() }
        let active = Array(watches.values)
        for watch in active { watch.timer?.cancel(); watch.readRetry?.cancel() }
        DispatchQueue.main.async {
            for watch in active {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watch.observer), .commonModes)
            }
        }
    }
    func start(preferences: Preferences) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                // Activation alone is not a window change. Hiding/termination affect
                // only that process; Spaces/sleep/wake invalidate every process.
                if name != NSWorkspace.didActivateApplicationNotification {
                    self.fence.invalidate(pid: app?.processIdentifier)
                }
                self.queue.async { self.workspaceEvent(name, app: app) }
            })
        }
        update(preferences)
    }
    func update(_ value: Preferences) {
        fence.invalidate()
        let revision = settingsFence.invalidate()
        queue.async { [self] in
            guard settingsFence.snapshot() == revision else { return }
            self.preferences = value
            self.wakeTimer?.cancel()
            self.removeAll()
            self.reconcile()
            if let until = value.pauseUntil, until > Date() {
                let work = DispatchWorkItem { [weak self] in self?.reconcile() }
                self.wakeTimer = work
                self.queue.asyncAfter(deadline: .now() + until.timeIntervalSinceNow, execute: work)
            }
        }
    }
    func refresh() {
        fence.invalidate()
        queue.async { self.removeAll(); self.reconcile() }
    }
    private func emit(_ id: String, _ message: String, elapsed: Double? = nil, requested: Bool = false, completed: Bool = false, summary: String? = nil, quitID: UUID? = nil) {
        let entry = Diagnostic(bundleID: id, message: message, requested: requested, completed: completed, elapsed: elapsed, summary: summary, quitID: quitID)
        DispatchQueue.main.async { self.onDiagnostic?(entry) }
    }
    private func remove(_ pid: pid_t, terminated: Bool = false) {
        attachmentRetries.removeValue(forKey: pid)?.cancel()
        launchObservations.removeValue(forKey: pid)?.invalidate()
        guard let watch = watches.removeValue(forKey: pid) else { return }
        // Workspace activation can precede the termination notification. If
        // reconcile already knows the process exited, retain that confirmation.
        if (terminated || watch.app.isTerminated), let closeAt = watch.closeAt, watch.requestedAt != nil {
            emit(watch.app.bundleIdentifier ?? "", L("Process exited after a normal Quit request"), elapsed: now - closeAt, completed: true, quitID: watch.quitID)
        }
        watch.terminationObservation?.invalidate()
        watch.timer?.cancel(); watch.readRetry?.cancel()
        // Keep the callback context alive until the main run loop has removed its source.
        DispatchQueue.main.async {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(watch.observer), .commonModes)
        }
    }
    private func removeAll() {
        for work in attachmentRetries.values { work.cancel() }
        attachmentRetries.removeAll()
        for observation in launchObservations.values { observation.invalidate() }
        launchObservations.removeAll()
        for pid in Array(watches.keys) { remove(pid) }
    }
    private func cancel(_ watch: Watch, reason: String, log: Bool = true) {
        if log && watch.gate.pending != nil { emit(watch.app.bundleIdentifier ?? "", reason, summary: reason) }
        watch.timer?.cancel(); watch.timer = nil; watch.gate.cancel()
    }
    private func workspaceEvent(_ name: Notification.Name, app: NSRunningApplication?) {
        if name == NSWorkspace.didTerminateApplicationNotification, let app {
            if watches[app.processIdentifier]?.app == app { remove(app.processIdentifier, terminated: true) }
        }
        if name == NSWorkspace.activeSpaceDidChangeNotification || name == NSWorkspace.willSleepNotification || name == NSWorkspace.didWakeNotification {
            for watch in watches.values { cancel(watch, reason: L("Cancelled: Space change / sleep / wake")) }
            if name == NSWorkspace.willSleepNotification { removeAll(); return }
        } else if name != NSWorkspace.didActivateApplicationNotification, let app, let watch = watches[app.processIdentifier] {
            cancel(watch, reason: L("Cancelled: application activity or visibility changed"))
        }
        let existing = app.flatMap { watches[$0.processIdentifier] }
        reconcile(app: app)
        if let watch = existing, watches[watch.app.processIdentifier] === watch,
           watch.requestedAt == nil, watch.gate.pending == nil {
            readWhenReady(watch)
        }
    }
    private func reconcile(app target: NSRunningApplication? = nil) {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async { self.onPermission?(trusted) }
        guard trusted, preferences.enabled, !preferences.isPaused else { removeAll(); return }
        let apps = NSWorkspace.shared.runningApplications
        // runningApplications can drop an app before isTerminated / didTerminate
        // updates. Keep its watch through that gap to retain the Quit receipt.
        let departed = watches.filter { $0.value.app.isTerminated }.map(\.key)
        for pid in departed { remove(pid) }
        for app in target.map({ [$0] }) ?? apps {
            guard app.processIdentifier > 0, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.activationPolicy == .regular, !app.isTerminated,
                  let id = app.bundleIdentifier, preferences.reasonExcluded(id, ownID: ownID) == nil,
                  watches[app.processIdentifier] == nil, attachmentRetries[app.processIdentifier] == nil else { continue }
            observeLaunch(app)
            attach(app)
        }
    }
    private func observeLaunch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard !app.isFinishedLaunching, launchObservations[pid] == nil else { return }
        // LaunchServices can announce Mail before its AX server is ready. KVO gives
        // us readiness without a long sleep or polling; early AX attachment still works
        // for apps that never publish finishedLaunching.
        launchObservations[pid] = app.observe(\.isFinishedLaunching, options: [.initial, .new]) { [weak self] app, _ in
            guard app.isFinishedLaunching, let self else { return }
            self.queue.async {
                guard !app.isTerminated, NSRunningApplication(processIdentifier: pid) == app,
                      self.launchObservations.removeValue(forKey: pid) != nil else { return }
                self.attachmentRetries.removeValue(forKey: pid)?.cancel()
                let existing = self.watches[pid]
                self.reconcile(app: app)
                if let watch = existing, self.watches[pid] === watch, watch.app == app,
                   watch.readWasTransient, watch.gate.pending == nil, watch.requestedAt == nil {
                    self.readWhenReady(watch)
                }
            }
        }
    }
    // Bounded recovery for launch-time AX IPC failures, never a polling loop.
    static func recoveryDelay(attempt: Int) -> Double? {
        let delays = [0.15, 0.35, 1.0, 2.0]
        return delays.indices.contains(attempt) ? delays[attempt] : nil
    }
    private func retryAttachment(_ app: NSRunningApplication, attempt: Int, error: AXError) {
        guard error == .cannotComplete,
              let delay = Self.recoveryDelay(attempt: attempt) else { return }
        emit(app.bundleIdentifier ?? "", L("AX temporarily unavailable; retrying observation in %.0f ms (%d/4)", delay * 1000, attempt + 1))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.attachmentRetries.removeValue(forKey: app.processIdentifier)
            guard !app.isTerminated, NSRunningApplication(processIdentifier: app.processIdentifier) == app,
                  self.watches[app.processIdentifier] == nil, AXIsProcessTrusted(), let id = app.bundleIdentifier,
                  self.preferences.reasonExcluded(id, ownID: self.ownID) == nil else { return }
            self.attach(app, attempt: attempt + 1)
        }
        attachmentRetries[app.processIdentifier] = work
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func attach(_ app: NSRunningApplication, attempt: Int = 0) {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.12)
        let callbackContext = ObserverContext(self, pid: app.processIdentifier)
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()
        var result: AXObserver?
        let error = AXObserverCreate(app.processIdentifier, { observer, element, notification, context in
            guard let context else { return }
            let source = Unmanaged<ObserverContext>.fromOpaque(context).takeUnretainedValue()
            guard let monitor = source.monitor else { return }
            let name = notification as String
            // Creation/minimization must invalidate in-flight reads immediately.
            // Destruction only removes windows; the serial ledger handles it. App-level
            // destruction also reports controls, which must not cancel a window timer.
            let structural = name == kAXWindowCreatedNotification || name == kAXWindowMiniaturizedNotification || name == kAXWindowDeminiaturizedNotification
            // The destroyed element may no longer answer AXUIElementGetPid.
            let revision = structural ? monitor.fence.invalidate(pid: source.pid) : monitor.fence.snapshot(pid: source.pid)
            let eventTime = ProcessInfo.processInfo.systemUptime
            monitor.queue.async { monitor.event(observer, element: element, name: name, at: eventTime, revision: revision) }
        }, &result)
        guard error == .success, let observer = result else {
            emit(app.bundleIdentifier ?? "", L("Could not create AXObserver: %d", error.rawValue))
            retryAttachment(app, attempt: attempt, error: error); return
        }
        let subscription = AXObserverAddNotification(observer, element, kAXWindowCreatedNotification as CFString, context)
        guard subscription == .success else {
            emit(app.bundleIdentifier ?? "", L("AXWindowCreated unavailable: %d. Launch finished: %@. Quit blocked.", subscription.rawValue, String(app.isFinishedLaunching)))
            retryAttachment(app, attempt: attempt, error: subscription); return
        }
        // AppKit may accept a window subscription without delivering its destruction.
        // Subscribe at the application as well; callbacks for controls are ignored.
        do { try WindowReader.observeDestruction(observer, element: element, context: context) }
        catch {
            emit(app.bundleIdentifier ?? "", L("App-level destruction observation unavailable: %@. Quit blocked.", String(describing: error)))
            if case WindowReadError.subscription(let code) = error, let axError = AXError(rawValue: code) {
                retryAttachment(app, attempt: attempt, error: axError)
            }
            return
        }
        for name in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            _ = AXObserverAddNotification(observer, element, name as CFString, context)
        }
        let watch = Watch(app: app, element: element, observer: observer, context: callbackContext)
        watches[app.processIdentifier] = watch
        watch.terminationObservation = app.observe(\.isTerminated, options: [.new]) { [weak self, weak watch] app, _ in
            guard app.isTerminated, let self, let watch else { return }
            self.queue.async {
                guard self.watches[app.processIdentifier] === watch else { return }
                self.remove(app.processIdentifier, terminated: true)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        readWhenReady(watch)
    }
    private func readWhenReady(_ watch: Watch, attempt: Int = 0) {
        watch.readRetry?.cancel(); watch.readRetry = nil
        if let snapshot = read(watch) {
            if attempt > 0 { emit(watch.app.bundleIdentifier ?? "", L("AX read recovered after retry")) }
            emit(watch.app.bundleIdentifier ?? "", L("Monitoring active: %d normal, %d auxiliary windows", snapshot.filter { $0.kind == .normal }.count, snapshot.filter { $0.kind != .normal }.count))
            // Calendar can accept AX subscriptions before publishing its main window.
            // An empty AX list alongside a visible CG surface is not a settled snapshot.
            // Reuse bounded startup recovery to seed identities; this never arms Quit.
            guard snapshot.isEmpty,
                  attempt == 0 || WindowReader.cgHasWindows(pid: watch.app.processIdentifier) == true || !watch.tracked.isEmpty else { return }
            emit(watch.app.bundleIdentifier ?? "", L("AX window list is empty during discovery; checking readiness again"))
        } else if !watch.readWasTransient { return }
        if let delay = Self.recoveryDelay(attempt: attempt) {
            let work = DispatchWorkItem { [weak self, weak watch] in
                guard let self, let watch, self.watches[watch.app.processIdentifier] === watch,
                      watch.gate.pending == nil, watch.requestedAt == nil else { return }
                self.readWhenReady(watch, attempt: attempt + 1)
            }
            watch.readRetry = work
            emit(watch.app.bundleIdentifier ?? "", L("Retrying AX read in %.0f ms (%d/4)", delay * 1000, attempt + 1))
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
    @discardableResult
    private func read(_ watch: Watch, cancelOnFailure: Bool = true) -> [ObservedWindow]? {
        let started = now
        watch.readWasTransient = false
        do {
            let elements = try WindowReader.windows(watch.element, discovered: { self.seed($0, watch: watch) })
            var snapshot: [ObservedWindow] = []
            for element in elements {
                guard now - started < 0.35 else { throw WindowReadError.budget }
                snapshot.append(try track(element, watch: watch))
            }
            guard now - started < 0.35 else { throw WindowReadError.budget }
            watch.gate.observe(snapshot)
            return snapshot
        } catch {
            watch.readWasTransient = (error as? WindowReadError)?.isTransient == true
            if cancelOnFailure { cancel(watch, reason: L("Cancelled: uncertain window read")) }
            emit(watch.app.bundleIdentifier ?? "", L("Quit blocked. %@", String(describing: error)), elapsed: now - started,
                 summary: L("Kept running: window state could not be confirmed"))
            return nil
        }
    }
    private func seed(_ elements: [AXUIElement], watch: Watch) {
        for element in elements where !watch.tracked.contains(where: { CFEqual($0.element, element) }) {
            nextID &+= 1
            watch.tracked.append((nextID, element, false))
            watch.gate.observe([ObservedWindow(nextID, .unknown)])
        }
    }
    @discardableResult
    private func track(_ element: AXUIElement, watch: Watch) throws -> ObservedWindow {
        seed([element], watch: watch)
        guard let index = watch.tracked.firstIndex(where: { CFEqual($0.element, element) }) else { throw WindowReadError.malformed }
        let metadata = try WindowReader.metadata(element, id: watch.tracked[index].id)
        watch.gate.observe([metadata])
        if !watch.tracked[index].subscribed {
            let context = Unmanaged.passUnretained(watch.context).toOpaque()
            do { try WindowReader.observeDestruction(watch.observer, element: element, context: context) }
            catch WindowReadError.subscription(let code) where code == AXError.notificationUnsupported.rawValue {
                emit(watch.app.bundleIdentifier ?? "", L("Window uses app-level destruction observation"))
            }
            watch.tracked[index].subscribed = true
            for name in [kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                _ = AXObserverAddNotification(watch.observer, element, name as CFString, context)
            }
        }
        return metadata
    }
    private func event(_ observer: AXObserver, element: AXUIElement, name: String, at time: Double, revision: UInt64) {
        guard let watch = watches.values.first(where: { CFEqual($0.observer, observer) }), !watch.app.isTerminated else { return }
        let id = watch.app.bundleIdentifier ?? ""
        if name == kAXWindowCreatedNotification {
            emit(id, L("AX: new window created"))
            cancel(watch, reason: L("Cancelled: a new window was created"))
            watch.requestedAt = nil; watch.closeAt = nil; watch.quitID = nil
            // Creation supplies the window itself before AXWindows necessarily lists it.
            // Observe that identity now so a fast close cannot be lost to startup timing.
            AXUIElementSetMessagingTimeout(element, 0.12)
            if (try? WindowReader.value(element, kAXRoleAttribute)) as? String == kAXWindowRole {
                do { try track(element, watch: watch) }
                catch { emit(id, L("New window observation incomplete: %@", String(describing: error))) }
            }
            readWhenReady(watch)
        } else if name == kAXUIElementDestroyedNotification {
            guard watch.requestedAt == nil else { return }
            guard let index = watch.tracked.firstIndex(where: { CFEqual($0.element, element) }) else {
                // Application-wide destruction includes controls and duplicate events.
                // Neither can arm Quit or invalidate an already confirmed window close.
                return
            }
            let window = watch.tracked.remove(at: index)
            let wasMinimized = watch.gate.windows[window.id]?.minimized ?? false
            guard let pending = watch.gate.destroyed(window.id, now: time, delay: preferences.delay(for: id)) else {
                if watch.gate.pending != nil { emit(id, L("Auxiliary window closed; keeping the countdown")) }
                return
            }
            watch.timer?.cancel(); watch.readRetry?.cancel(); watch.readRetry = nil
            if !preferences.monitorMinimized && wasMinimized {
                cancel(watch, reason: L("Quit blocked: a minimized window closed while monitoring that state is disabled"))
                return
            }
            let work = DispatchWorkItem { [weak self, weak watch] in
                guard let self, let watch else { return }
                self.verify(watch, pending: pending, revision: revision)
            }
            watch.timer = work
            emit(id, L("Normal window closed; verifying after %.2f s", preferences.delay(for: id)))
            queue.asyncAfter(deadline: .now() + max(0, pending.deadline - now), execute: work)
        } else if name == kAXWindowMiniaturizedNotification || name == kAXWindowDeminiaturizedNotification {
            cancel(watch, reason: L("Cancelled: window minimized / restored"))
            readWhenReady(watch)
        } else if watch.gate.pending == nil && watch.requestedAt == nil {
            // Focus changes accompany native closing animations. The timer already
            // guarantees a fresh AX read; an eager read here can fail while AppKit is busy.
            readWhenReady(watch)
        }
    }
    private func verify(_ watch: Watch, pending: CloseGate.Pending, revision: UInt64, attempt: Int = 0) {
        guard watches[watch.app.processIdentifier] === watch, watch.gate.pending == pending else { return }
        let id = watch.app.bundleIdentifier ?? ""
        let started = now
        let lateness = max(0, started - pending.deadline)
        func block(_ reason: String, summary: String? = nil) {
            cancel(watch, reason: reason, log: false)
            emit(id, reason, elapsed: now - pending.closedAt, summary: summary ?? L("Kept running: window state could not be confirmed"))
        }
        guard fence.snapshot(pid: watch.app.processIdentifier) == revision else { block(L("Quit cancelled: a new event arrived during the countdown")); return }
        guard lateness < 0.5 else { block(L("Quit cancelled: worker queue delayed by more than 500 ms")); return }
        guard AXIsProcessTrusted(), preferences.reasonExcluded(id, ownID: ownID) == nil,
              !watch.app.isTerminated, watch.app.activationPolicy == .regular,
              NSRunningApplication(processIdentifier: watch.app.processIdentifier) == watch.app else {
            block(L("Quit blocked: permissions, rules or process identity changed")); return
        }
        guard preferences.monitorHidden || !watch.app.isHidden else { block(L("Quit blocked: app is hidden"), summary: L("Kept running: the app is hidden")); return }
        guard let snapshot = read(watch, cancelOnFailure: false) else {
            // A busy AX server must not permanently lose an already confirmed close.
            // Keep every fence and the original deadline; recovery is bounded, not polling.
            if watch.readWasTransient, attempt < 2, now - pending.deadline < 0.35 {
                let work = DispatchWorkItem { [weak self, weak watch] in
                    guard let self, let watch else { return }
                    self.verify(watch, pending: pending, revision: revision, attempt: attempt + 1)
                }
                watch.timer = work
                emit(id, L("AX busy after close; verifying again in 100 ms (%d/2)", attempt + 1), elapsed: now - pending.closedAt)
                queue.asyncAfter(deadline: .now() + 0.1, execute: work)
            } else { cancel(watch, reason: L("Cancelled: uncertain window read")) }
            return
        }
        if !preferences.monitorMinimized && snapshot.contains(where: \.minimized) {
            block(L("Quit blocked: minimized-window monitoring is disabled"), summary: L("Kept running: a minimized window remains")); return
        }
        guard snapshot.isEmpty && watch.gate.windows.isEmpty else {
            emit(id, L("Window veto: AX snapshot %d, remembered %d", snapshot.count, watch.gate.windows.count))
            block(L("Quit blocked: a normal, auxiliary or unconfirmed off-Space window remains"), summary: L("Kept running: an open or remembered window remains")); return
        }
        let cg = WindowReader.cgHasWindows(pid: watch.app.processIdentifier)
        guard watch.gate.canQuit(token: pending.token, now: now, snapshot: snapshot, cgHasWindows: cg,
                                 eligible: true, trusted: AXIsProcessTrusted()) else {
            block(cg == true ? L("Quit blocked: WindowServer still reports a visible window") : L("Quit blocked: incomplete state or cancelled countdown")); return
        }
        // Close the CG/AX read gap as far as public APIs permit. No API can atomically
        // assert zero windows and quit a different process; a tiny residual race remains.
        guard let finalWindows = try? WindowReader.windows(watch.element, discovered: { self.seed($0, watch: watch) }), finalWindows.isEmpty,
              now - started < 0.35 else { block(L("Quit cancelled: state changed or verification exceeded 350 ms")); return }
        guard let sent = fence.perform(ifUnchanged: revision, pid: watch.app.processIdentifier, {
            guard AXIsProcessTrusted(), preferences.monitorHidden || !watch.app.isHidden else { return false }
            return watch.app.terminate()
        }) else { block(L("Quit cancelled: a new event arrived during verification")); return }
        watch.gate.cancel(); watch.timer = nil
        if sent {
            watch.closeAt = pending.closedAt; watch.requestedAt = now; watch.quitID = UUID()
            emit(id, L("Normal Quit requested. Read %.0f ms; queue +%.0f ms. Waiting for process exit.", (now - started) * 1000, lateness * 1000), elapsed: now - pending.closedAt, requested: true, quitID: watch.quitID)
        } else { emit(id, L("The system did not accept the Quit request"), elapsed: now - pending.closedAt, summary: L("The system did not accept the Quit request")) }
    }
    // Explicit diagnostic read: never changes observers, identities, deadlines or Quit eligibility.
    func inspect(_ app: NSRunningApplication, preferences value: Preferences, completion: @escaping (String) -> Void) {
        queue.async { [self] in
            let text: String
            let id = app.bundleIdentifier ?? ""
            if app.isTerminated { text = L("This app is not running.") }
            else if !AXIsProcessTrusted() { text = L("Accessibility required") }
            else if let reason = value.reasonExcluded(id, ownID: ownID) { text = L("Not monitored: %@", L(reason)) }
            else if app.activationPolicy != .regular { text = L("Background apps are not monitored.") }
            else if !value.monitorHidden && app.isHidden { text = L("Kept running: the app is hidden") }
            else if let watch = watches[app.processIdentifier], watch.requestedAt != nil {
                text = L("Quit requested — waiting for the app to exit")
            } else if let pending = watches[app.processIdentifier]?.gate.pending {
                text = L("Verifying the last window in %.2f s", max(0, pending.deadline - now))
            } else {
                do {
                    let element = AXUIElementCreateApplication(app.processIdentifier)
                    AXUIElementSetMessagingTimeout(element, 0.12)
                    let windows = try WindowReader.windows(element)
                    let started = now
                    var normal = 0, auxiliary = 0, minimized = 0
                    for (index, window) in windows.enumerated() {
                        guard now - started < 0.35 else { throw WindowReadError.budget }
                        let metadata = try WindowReader.metadata(window, id: UInt64(index))
                        if metadata.kind == .normal { normal += 1 } else { auxiliary += 1 }
                        if metadata.minimized { minimized += 1 }
                    }
                    if !windows.isEmpty {
                        text = L("Kept running: %d normal, %d auxiliary, %d minimized windows.", normal, auxiliary, minimized)
                    } else if watches[app.processIdentifier]?.gate.windows.isEmpty == false {
                        text = L("Kept running: a remembered window has not confirmed its closure, possibly on another Space.")
                    } else if WindowReader.cgHasWindows(pid: app.processIdentifier) != false {
                        text = L("Kept running: WindowServer still reports a window or an uncertain state.")
                    } else if watches[app.processIdentifier] == nil {
                        text = L("Waiting for Accessibility observation to become ready.")
                    } else { text = L("No windows now. Waiting for a confirmed normal-window close; an empty list alone never triggers Quit.") }
                } catch { text = L("Kept running: window state could not be confirmed") }
            }
            DispatchQueue.main.async { completion(text) }
        }
    }
}
