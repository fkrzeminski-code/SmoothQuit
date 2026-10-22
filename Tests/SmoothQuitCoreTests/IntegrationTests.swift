import XCTest
import AppKit
import ApplicationServices
import SmoothQuitCore
@testable import SmoothQuit

final class IntegrationTests: XCTestCase {
    /// Opt-in: the operator must prepare ONLY disposable blank TextEdit windows.
    /// This test runs the production monitor and sends its normal Quit request.
    func testLiveTextEditCloseAndQuit() throws {
        guard ProcessInfo.processInfo.environment["SMOOTHQUIT_LIVE_TEXTEDIT"] == "1" else {
            throw XCTSkip("Interaktywny test wymaga zgody i pustego okna TextEdit")
        }
        _ = NSApplication.shared // Bootstrap the GUI event connection for live AX callbacks.
        XCTAssertTrue(AXIsProcessTrusted())
        let app = try XCTUnwrap(NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.TextEdit" })
        let windows = try WindowReader.windows(AXUIElementCreateApplication(app.processIdentifier))
        XCTAssertFalse(windows.isEmpty)
        let monitor = Monitor()
        var prefs = Preferences()
        prefs.rules = [AppRule(id: "com.apple.TextEdit", name: "TextEdit")]
        let requested = expectation(description: "Production monitor requested Quit")
        let completed = expectation(description: "TextEdit exited after Quit")
        monitor.onDiagnostic = { entry in
            print("LIVE: \(entry.message) elapsed=\(entry.elapsed ?? -1)")
            fflush(stdout)
            if entry.requested { requested.fulfill() }
            if entry.completed { completed.fulfill() }
        }
        monitor.start(preferences: prefs)
        print("LIVE READY: close the prepared blank TextEdit window within 45 seconds")
        fflush(stdout)
        wait(for: [requested, completed], timeout: 45, enforceOrder: true)
        prefs.enabled = false
        monitor.update(prefs)
        XCTAssertTrue(app.isTerminated)
    }
    /// Opt-in operator test. No app is launched by this test; the operator opens
    /// Mail/Calendar’s main window or a disposable Preview document after LIVE READY.
    func testLiveMailOrPreviewCloseAndQuit() throws {
        guard let id = ProcessInfo.processInfo.environment["SMOOTHQUIT_LIVE_APP"],
              ["com.apple.mail", "com.apple.Preview", "com.apple.iCal", "net.whatsapp.WhatsApp", "com.microsoft.Excel"].contains(id) else {
            throw XCTSkip("Interactive application test requires operator authorization")
        }
        _ = NSApplication.shared // Bootstrap the GUI event connection for live AX callbacks.
        XCTAssertTrue(AXIsProcessTrusted())
        let monitor = Monitor()
        var prefs = Preferences(); prefs.rules = [AppRule(id: id, name: id)]
        let requested = expectation(description: "Production monitor requested Quit")
        let completed = expectation(description: "Target process exited after Quit")
        monitor.onDiagnostic = { entry in
            guard entry.bundleID == id else { return }
            print("LIVE \(entry.date.ISO8601Format()) \(id): \(entry.message) elapsed=\(entry.elapsed ?? -1)"); fflush(stdout)
            if entry.requested {
                XCTAssertGreaterThanOrEqual(entry.elapsed ?? 0, 0.5)
                requested.fulfill()
            }
            if entry.completed { completed.fulfill() }
        }
        monitor.start(preferences: prefs)
        print("LIVE READY: open and close the authorized test window of \(id) within 90 seconds"); fflush(stdout)
        wait(for: [requested, completed], timeout: 90, enforceOrder: true)
        prefs.enabled = false; monitor.update(prefs)
        XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty)
    }
    func testLivePreviewKeepsExistingWindowsAfterDisposableClose() throws {
        guard ProcessInfo.processInfo.environment["SMOOTHQUIT_LIVE_PREVIEW_KEEP"] == "1" else {
            throw XCTSkip("Requires operator-prepared disposable Preview window and an existing window to protect")
        }
        _ = NSApplication.shared
        XCTAssertTrue(AXIsProcessTrusted())
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Preview").first)
        let existing = try WindowReader.windows(AXUIElementCreateApplication(app.processIdentifier))
        guard existing.contains(where: { (try? WindowReader.metadata($0, id: 0))?.kind == .normal }) else {
            throw XCTSkip("AX cannot confirm an existing normal Preview window; activate its document before this test")
        }
        let monitor = Monitor()
        var prefs = Preferences(); prefs.rules = [AppRule(id: "com.apple.Preview", name: "Preview")]
        let blocked = expectation(description: "Existing window vetoes Quit")
        let noQuit = expectation(description: "No Quit while another window exists"); noQuit.isInverted = true
        monitor.onDiagnostic = { entry in
            print("PREVIEW KEEP: \(entry.message) elapsed=\(entry.elapsed ?? -1)"); fflush(stdout)
            if entry.summary == L("Kept running: an open or remembered window remains") { blocked.fulfill() }
            if entry.requested || entry.completed { noQuit.fulfill() }
        }
        monitor.start(preferences: prefs)
        print("LIVE READY: open and close ONLY the disposable Preview test document"); fflush(stdout)
        wait(for: [blocked], timeout: 60)
        wait(for: [noQuit], timeout: 1)
        prefs.enabled = false; monitor.update(prefs)
        XCTAssertFalse(app.isTerminated)
        XCTAssertFalse(try WindowReader.windows(AXUIElementCreateApplication(app.processIdentifier)).isEmpty)
    }
    func testMainAndFocusedWindowSupplementAnEmptyCatalystWindowList() throws {
        let app = AXUIElementCreateApplication(100)
        let window = AXUIElementCreateApplication(101) // Opaque identity; no IPC in this fixture.
        let result = try WindowReader.windows(app) { _, attribute in
            if attribute == kAXWindowsAttribute { return [] as CFArray }
            return window
        }
        XCTAssertEqual(result.count, 1) // Main/focused point to the same window.
        XCTAssertTrue(CFEqual(result[0], window))
    }
    func testSupplementalWindowNeverReplacesOtherSpaceOrMasksAXFailure() throws {
        let app = AXUIElementCreateApplication(100)
        let offSpace = AXUIElementCreateApplication(101), main = AXUIElementCreateApplication(102)
        let result = try WindowReader.windows(app) { _, attribute in
            if attribute == kAXWindowsAttribute { return [offSpace] as CFArray }
            return main
        }
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains { CFEqual($0, offSpace) })
        for error in [AXError.cannotComplete, .apiDisabled, .invalidUIElement] {
            XCTAssertThrowsError(try WindowReader.windows(app) { _, attribute in
                if attribute == kAXWindowsAttribute { return [] as CFArray }
                throw WindowReadError.ax(attribute, error.rawValue)
            })
        }
        XCTAssertThrowsError(try WindowReader.windows(app) { _, attribute in
            if attribute == kAXWindowsAttribute { throw WindowReadError.ax(attribute, AXError.cannotComplete.rawValue) }
            return main
        })
        for missing in [AXError.noValue, .attributeUnsupported] {
            XCTAssertTrue(try WindowReader.windows(app) { _, attribute in
                if attribute == kAXWindowsAttribute { return [] as CFArray }
                throw WindowReadError.ax(attribute, missing.rawValue)
            }.isEmpty)
        }
        XCTAssertThrowsError(try WindowReader.windows(app) { _, attribute in
            if attribute == kAXWindowsAttribute { return [] as CFArray }
            return "invalid window payload" as CFString
        })
    }
    func testLiveWindowInventoryWithoutTitles() throws {
        guard let id = ProcessInfo.processInfo.environment["SMOOTHQUIT_INVENTORY_APP"] else { throw XCTSkip("Read-only opt-in window inventory") }
        _ = NSApplication.shared
        guard AXIsProcessTrusted() else { throw XCTSkip("Test host lacks Accessibility") }
        let app = try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: id).first)
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.12)
        for attribute in [kAXWindowsAttribute, kAXMainWindowAttribute, kAXFocusedWindowAttribute, kAXChildrenAttribute] {
            var raw: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &raw)
            print("INVENTORY \(attribute): error=\(error.rawValue)")
            let children: [AXUIElement]
            if let list = raw as? [AXUIElement] { children = list }
            else if let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() { children = [unsafeBitCast(raw, to: AXUIElement.self)] }
            else { continue }
            for (index, child) in children.prefix(256).enumerated() {
                let role = (try? WindowReader.value(child, kAXRoleAttribute)) as? String ?? "unreadable"
                let subrole = role == kAXWindowRole ? ((try? WindowReader.value(child, kAXSubroleAttribute)) as? String ?? "unreadable") : "—"
                print("INVENTORY child \(index) role=\(role) subrole=\(subrole)")
            }
        }
    }
    func testFenceRejectsEventDuringSlowRead() {
        let fence = EventFence(); let revision = fence.snapshot()
        let event = expectation(description: "Incoming event")
        DispatchQueue.global().async { fence.invalidate(); event.fulfill() }
        wait(for: [event], timeout: 2)
        var invoked = false
        XCTAssertNil(fence.perform(ifUnchanged: revision) { invoked = true; return true })
        XCTAssertFalse(invoked)
        XCTAssertEqual(fence.perform(ifUnchanged: fence.snapshot()) { true }, true)
    }
    func testFenceRejectsEventDuringCountdown() {
        let fence = EventFence()
        let closeRevision = fence.invalidate()
        fence.invalidate() // creation received before the timer's worker block begins
        var invoked = false
        XCTAssertNil(fence.perform(ifUnchanged: closeRevision) { invoked = true; return true })
        XCTAssertFalse(invoked)
    }
    func testOtherApplicationCannotCancelPendingQuit() {
        let fence = EventFence()
        let mail = fence.snapshot(pid: 100), preview = fence.snapshot(pid: 200)
        fence.invalidate(pid: 200)
        var requests = 0
        XCTAssertEqual(fence.perform(ifUnchanged: mail, pid: 100) { requests += 1; return true }, true)
        XCTAssertNil(fence.perform(ifUnchanged: preview, pid: 200) { requests += 1; return true })
        XCTAssertEqual(requests, 1)
        let current = fence.snapshot(pid: 200)
        fence.invalidate() // disable, settings, Space, sleep, refresh
        XCTAssertNil(fence.perform(ifUnchanged: mail, pid: 100) { true })
        XCTAssertNil(fence.perform(ifUnchanged: current, pid: 200) { true })
    }
    func testTargetApplicationEventDuringReadStillCancels() {
        let fence = EventFence()
        let revision = fence.snapshot(pid: 100)
        let changed = expectation(description: "target created a window while AX IPC was in progress")
        DispatchQueue.global().async { fence.invalidate(pid: 100); changed.fulfill() }
        wait(for: [changed], timeout: 2)
        XCTAssertNil(fence.perform(ifUnchanged: revision, pid: 100) { XCTFail("stale Quit"); return true })
    }
    func testAuxiliaryWithoutMinimizedAttributeStillVetoesQuit() throws {
        let auxiliary = try WindowReader.metadata(fields: [kAXWindowRole, kAXDialogSubrole, NSNull()], id: 2)
        XCTAssertEqual(auxiliary.kind, .auxiliary)
        var gate = CloseGate(); gate.observe([ObservedWindow(1), auxiliary])
        let pending = try XCTUnwrap(gate.destroyed(1, now: 10, delay: 0.5))
        XCTAssertFalse(gate.canQuit(token: pending.token, now: 11, snapshot: [], cgHasWindows: false, eligible: true, trusted: true))
        XCTAssertThrowsError(try WindowReader.metadata(fields: [kAXWindowRole, kAXStandardWindowSubrole, NSNull()], id: 1))
        XCTAssertThrowsError(try WindowReader.metadata(fields: [kAXWindowRole, NSNull(), false], id: 1))
    }
    func testRealObserverSubscriptionsOnRunningAppleWindows() throws {
        guard AXIsProcessTrusted() else { throw XCTSkip("Brak Accessibility dla hosta testów") }
        let apps = NSWorkspace.shared.runningApplications.filter { ["com.apple.Safari", "com.apple.finder"].contains($0.bundleIdentifier ?? "") }
        guard !apps.isEmpty else { throw XCTSkip("Brak działających aplikacji testowych") }
        for app in apps {
            var observer: AXObserver?
            XCTAssertEqual(AXObserverCreate(app.processIdentifier, { _, _, _, _ in }, &observer), .success)
            let actual = try XCTUnwrap(observer)
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.12)
            XCTAssertEqual(AXObserverAddNotification(actual, element, kAXWindowCreatedNotification as CFString, nil), .success)
            XCTAssertNoThrow(try WindowReader.observeDestruction(actual, element: element, context: nil))
            for window in try WindowReader.windows(element) {
                let kind = try WindowReader.metadata(window, id: 1).kind
                do {
                    try WindowReader.observeDestruction(actual, element: window, context: nil)
                    print("AX destruction subscription: \(app.bundleIdentifier ?? ""), kind: \(kind), supported")
                    AXObserverRemoveNotification(actual, window, kAXUIElementDestroyedNotification as CFString)
                } catch WindowReadError.subscription(let code) where code == AXError.notificationUnsupported.rawValue && kind != .normal {
                    // Finder exposes auxiliary surfaces that cannot be observed. The production
                    // helper MUST throw, rather than returning a successful empty snapshot.
                    XCTAssertThrowsError(try WindowReader.observeDestruction(actual, element: window, context: nil))
                    print("AX destruction subscription: \(app.bundleIdentifier ?? ""), auxiliary unsupported; production reader fails closed")
                }
            }
            AXObserverRemoveNotification(actual, element, kAXWindowCreatedNotification as CFString)
            print("Read-only AXObserver subscriptions: \(app.bundleIdentifier ?? "")")
        }
    }
    func testRealAXInvalidProcessIsErrorNotZeroWindows() {
        XCTAssertThrowsError(try WindowReader.windows(AXUIElementCreateApplication(2_000_000_000)))
    }
    func testCGBackingSurfacesDoNotMasqueradeAsOpenWindows() {
        let base: [String: Any] = [kCGWindowOwnerPID as String: 123, kCGWindowLayer as String: 0]
        XCTAssertEqual(WindowReader.visibleCGWindow(in: [base], pid: 123), false)
        var visible = base; visible[kCGWindowIsOnscreen as String] = true
        XCTAssertEqual(WindowReader.visibleCGWindow(in: [visible], pid: 123), true)
        XCTAssertEqual(WindowReader.visibleCGWindow(in: [visible], pid: 456), false)
        XCTAssertNil(WindowReader.visibleCGWindow(in: [[:]], pid: 123))
        var unknownLayer = visible; unknownLayer.removeValue(forKey: kCGWindowLayer as String)
        XCTAssertNil(WindowReader.visibleCGWindow(in: [unknownLayer], pid: 123))
    }
    func testRealWindowServerRead() throws {
        XCTAssertNotNil(WindowReader.cgHasWindows(pid: ProcessInfo.processInfo.processIdentifier))
    }
    func testAppleApplicationsAreInstalled() throws {
        for id in ["com.apple.Safari", "com.apple.mail", "com.apple.Preview", "com.apple.TextEdit", "com.apple.calculator", "com.apple.finder"] {
            XCTAssertNotNil(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id), id)
        }
    }
    func testReadOnlyLiveAppleAXWindows() throws {
        guard AXIsProcessTrusted() else { throw XCTSkip("Host testów nie ma Accessibility. Nie żądamy uprawnień ani nie uruchamiamy aplikacji.") }
        let ids = ["com.apple.Safari", "com.apple.mail", "com.apple.Preview", "com.apple.TextEdit", "com.apple.calculator", "com.apple.finder"]
        let apps = NSWorkspace.shared.runningApplications.filter { ids.contains($0.bundleIdentifier ?? "") }
        guard !apps.isEmpty else { throw XCTSkip("Brak uruchomionych aplikacji testowych; nie uruchamiamy ich bez zgody.") }
        for app in apps {
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.12)
            let windows = try WindowReader.windows(ax)
            for (i, window) in windows.enumerated() { _ = try WindowReader.metadata(window, id: UInt64(i)) }
            print("Read-only AX: \(app.bundleIdentifier ?? ""), windows: \(windows.count)")
        }
    }
}
