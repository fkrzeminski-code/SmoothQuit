import XCTest
@testable import SmoothQuitCore

final class CloseGateTests: XCTestCase {
    private func closed() -> (CloseGate, CloseGate.Pending) {
        var gate = CloseGate()
        gate.observe([ObservedWindow(1)])
        let pending = gate.destroyed(1, now: 10, delay: 0.5)!
        return (gate, pending)
    }
    private func quit(_ gate: CloseGate, _ pending: CloseGate.Pending, now: Double = 10.5,
                      snapshot: [ObservedWindow]? = [], cg: Bool? = false, eligible: Bool = true, trusted: Bool = true) -> Bool {
        gate.canQuit(token: pending.token, now: now, snapshot: snapshot, cgHasWindows: cg, eligible: eligible, trusted: trusted)
    }
    func testLastWindowWaitsConfiguredDelay() {
        let (gate, p) = closed()
        XCTAssertFalse(quit(gate, p, now: 10.49))
        XCTAssertTrue(quit(gate, p))
    }
    func testMultipleWindowsRemain() {
        var gate = CloseGate(); gate.observe([ObservedWindow(1), ObservedWindow(2)])
        let p = gate.destroyed(1, now: 10, delay: 0.5)!
        XCTAssertFalse(quit(gate, p, snapshot: [ObservedWindow(2)]))
        XCTAssertFalse(quit(gate, p)) // AX temporarily omits another Space's window
    }
    func testNewWindowCancelsEvenIfItClosesBeforeDeadline() {
        var (gate, p) = closed(); gate.created()
        XCTAssertFalse(quit(gate, p))
        gate.observe([ObservedWindow(2)])
        let next = gate.destroyed(2, now: 10.2, delay: 0.5)!
        XCTAssertFalse(quit(gate, p, now: 11))
        XCTAssertTrue(quit(gate, next, now: 10.7))
    }
    func testRecheckDiscoversNewWindowWithoutNotification() {
        var (gate, p) = closed(); gate.observe([ObservedWindow(2)])
        XCTAssertFalse(quit(gate, p))
    }
    func testOtherSpaceFullscreenOrMonitorNeverDisappearsFromLedger() {
        var gate = CloseGate(); gate.observe([ObservedWindow(1), ObservedWindow(2)])
        gate.observe([ObservedWindow(1)])
        let p = gate.destroyed(1, now: 10, delay: 0.5)!
        XCTAssertFalse(quit(gate, p))
        XCTAssertEqual(gate.windows.count, 1)
    }
    func testFailedMetadataCannotDiscardLaterWindowOnOtherSpace() {
        var gate = CloseGate()
        gate.observe((1...3).map { ObservedWindow(UInt64($0), .unknown) })
        gate.observe([ObservedWindow(1)]) // metadata for 2 fails; 3 is not visited
        gate.destroyed(2, now: 9, delay: 0.5)
        let pending = gate.destroyed(1, now: 10, delay: 0.5)!
        XCTAssertFalse(quit(gate, pending)) // window 3 omitted from the final AX list
        XCTAssertEqual(gate.windows[3]?.kind, .unknown)
    }
    func testMinimizeDoesNotArm() {
        var gate = CloseGate(); gate.observe([ObservedWindow(1, minimized: true)])
        gate.observe([]); XCTAssertNil(gate.pending); XCTAssertEqual(gate.windows.count, 1)
    }
    func testHiddenAndSpaceEventsCancel() {
        var (gate, p) = closed(); gate.cancel(); XCTAssertFalse(quit(gate, p))
    }
    func testReadFailuresAndPermissionLossNeverQuit() {
        let (gate, p) = closed()
        XCTAssertFalse(quit(gate, p, snapshot: nil))
        XCTAssertFalse(quit(gate, p, cg: nil))
        XCTAssertFalse(quit(gate, p, trusted: false))
        XCTAssertFalse(quit(gate, p, eligible: false))
    }
    func testCGVetoProtectsOffscreenWindow() {
        let (gate, p) = closed(); XCTAssertFalse(quit(gate, p, cg: true))
    }
    func testAuxiliaryAndUnknownWindowsBlock() {
        for kind in [WindowKind.auxiliary, .unknown] {
            var gate = CloseGate(); gate.observe([ObservedWindow(1), ObservedWindow(2, kind)])
            let p = gate.destroyed(1, now: 10, delay: 0.5)!
            XCTAssertFalse(quit(gate, p))
            XCTAssertNil(gate.destroyed(2, now: 10.2, delay: 0.5))
        }
    }
    func testAuxiliaryDestructionKeepsOriginalNormalCloseDeadline() {
        var gate = CloseGate()
        gate.observe([ObservedWindow(1), ObservedWindow(2, .auxiliary)])
        let pending = gate.destroyed(1, now: 10, delay: 0.5)!
        XCTAssertNil(gate.destroyed(2, now: 10.2, delay: 2))
        XCTAssertEqual(gate.pending, pending)
        XCTAssertFalse(quit(gate, pending, now: 10.49))
        XCTAssertTrue(quit(gate, pending))
    }
    func testAuxiliaryCloseCannotReviveCancelledQuit() {
        var gate = CloseGate()
        gate.observe([ObservedWindow(1), ObservedWindow(2, .auxiliary)])
        let pending = gate.destroyed(1, now: 10, delay: 0.5)!
        gate.created()
        XCTAssertNil(gate.destroyed(2, now: 10.2, delay: 0.5))
        XCTAssertNil(gate.pending)
        XCTAssertFalse(quit(gate, pending))
    }
    func testUnknownDestructionStillCancelsPending() {
        var gate = CloseGate()
        gate.observe([ObservedWindow(1), ObservedWindow(2, .unknown)])
        let pending = gate.destroyed(1, now: 10, delay: 0.5)!
        gate.destroyed(2, now: 10.2, delay: 0.5)
        XCTAssertFalse(quit(gate, pending))
    }
    func testUnseenAndAuxiliaryCloseNeverArms() {
        var gate = CloseGate()
        XCTAssertNil(gate.destroyed(100, now: 1, delay: 0.5))
        gate.observe([ObservedWindow(1, .auxiliary)])
        XCTAssertNil(gate.destroyed(1, now: 1, delay: 0.5))
    }
    func testRapidClosuresUseLastEventOnly() {
        var gate = CloseGate(); gate.observe((1...30).map { ObservedWindow(UInt64($0)) })
        var prior: CloseGate.Pending?
        for i in 1...30 {
            let p = gate.destroyed(UInt64(i), now: Double(i), delay: 0.2)!
            if let prior { XCTAssertFalse(quit(gate, prior, now: 40)) }
            prior = p
        }
        XCTAssertFalse(quit(gate, prior!, now: 30.19))
        XCTAssertTrue(quit(gate, prior!, now: 30.2))
    }
    func testConsumedRequestCannotRepeat() {
        var (gate, p) = closed(); XCTAssertTrue(quit(gate, p))
        gate.cancel(); XCTAssertFalse(quit(gate, p))
    }
    func testDefaultsAreSafe() {
        let prefs = Preferences()
        XCTAssertEqual(prefs.mode, .include); XCTAssertEqual(prefs.delay, 0.5)
        XCTAssertNotNil(prefs.reasonExcluded("com.apple.Safari"))
        XCTAssertNotNil(prefs.reasonExcluded("com.apple.finder"))
    }
    func testIncludeExcludeAndPerAppRules() {
        var prefs = Preferences(); prefs.rules = [AppRule(id: "com.apple.Safari", name: "Safari")]
        XCTAssertNil(prefs.reasonExcluded("com.apple.Safari"))
        prefs.mode = .exclude
        XCTAssertNotNil(prefs.reasonExcluded("com.apple.Safari"))
        XCTAssertNil(prefs.reasonExcluded("com.apple.TextEdit"))
        prefs.rules[0].behavior = .allow; prefs.rules[0].delay = 1.2
        XCTAssertNil(prefs.reasonExcluded("com.apple.Safari")); XCTAssertEqual(prefs.delay(for: "com.apple.Safari"), 1.2)
        prefs.rules[0].behavior = .never; XCTAssertNotNil(prefs.reasonExcluded("com.apple.Safari"))
    }
    func testFinderRequiresExplicitOverrideAndSelfNeverAllowed() {
        var prefs = Preferences(); prefs.rules = [AppRule(id: "com.apple.finder", name: "Finder")]
        XCTAssertNotNil(prefs.reasonExcluded("com.apple.finder"))
        prefs.rules[0].behavior = .allow; XCTAssertNil(prefs.reasonExcluded("com.apple.finder"))
        prefs.rules = [AppRule(id: "pl.smoothquit.app", name: "SmoothQuit")]; prefs.rules[0].behavior = .allow
        XCTAssertNotNil(prefs.reasonExcluded("pl.smoothquit.app"))
    }
    func testSelfProtectionCannotBeOverriddenInEitherMode() {
        for mode in SelectionMode.allCases {
            var prefs = Preferences(); prefs.mode = mode
            var rule = AppRule(id: "pl.smoothquit.app", name: "SmoothQuit"); rule.behavior = .allow
            prefs.rules = [rule]
            XCTAssertNotNil(prefs.reasonExcluded(rule.id, ownID: "test.host"))
            XCTAssertNotNil(prefs.reasonExcluded("test.host", ownID: "test.host"))
        }
    }
    func testDisableRejectsPendingQuitAndCancelledTokenCannotBeReused() {
        var (gate, pending) = closed()
        var prefs = Preferences(); prefs.mode = .exclude; prefs.enabled = false
        XCTAssertFalse(quit(gate, pending, eligible: prefs.reasonExcluded("com.apple.TextEdit") == nil))
        gate.cancel()
        prefs.enabled = true
        XCTAssertFalse(quit(gate, pending, eligible: prefs.reasonExcluded("com.apple.TextEdit") == nil))
    }
    func testPauseAndDisabledOverrideAllowRule() {
        var prefs = Preferences(); var rule = AppRule(id: "test.app", name: "Test"); rule.behavior = .allow; prefs.rules = [rule]
        prefs.enabled = false; XCTAssertNotNil(prefs.reasonExcluded("test.app"))
        prefs.enabled = true; prefs.pauseUntil = Date(timeIntervalSince1970: 100)
        XCTAssertNotNil(prefs.reasonExcluded("test.app", now: Date(timeIntervalSince1970: 99)))
        XCTAssertNil(prefs.reasonExcluded("test.app", now: Date(timeIntervalSince1970: 101)))
    }
    func testValidationAndDelayBounds() {
        XCTAssertTrue(Preferences.validBundleID("com.apple.TextEdit"))
        for id in ["", "foo", "com..app", "com.a b", "../app", "com.app\n"] { XCTAssertFalse(Preferences.validBundleID(id)) }
        XCTAssertEqual(Preferences.boundedDelay(-1), 0.2); XCTAssertEqual(Preferences.boundedDelay(9), 2)
        XCTAssertEqual(Preferences.boundedDelay(.nan), 0.5)
    }
    func testSettingsRoundTripAndMalformedDataFails() throws {
        var p = Preferences(); p.rules = [AppRule(id: "com.apple.Preview", name: "Podgląd")]; p.rules[0].delay = 0.8
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p)), p)
        XCTAssertThrowsError(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)))
    }
}
