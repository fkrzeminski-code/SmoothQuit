import XCTest
import Foundation
@testable import SmoothQuit

private final class ReleaseProtocol: URLProtocol {
    // Tests run serially and every request uses the same deterministic response.
    static let payload = Data(#"{"tag_name":"v1.7.0","html_url":"https://github.com/fkrzeminski-code/SmoothQuit/releases/tag/v1.7.0","draft":false,"prerelease":false}"#.utf8)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class UpdateTests: XCTestCase {
    private func evaluate(_ version: String = "v1.7.0", current: String = "1.6.0", draft: Bool = false, prerelease: Bool = false,
                          link: String? = nil, status: Int = 200) -> UpdatePhase {
        let payload: [String: Any] = ["tag_name": version, "html_url": link ?? "https://github.com/fkrzeminski-code/SmoothQuit/releases/tag/\(version)", "draft": draft, "prerelease": prerelease]
        let response = HTTPURLResponse(url: URL(string: "https://api.github.com/repos/fkrzeminski-code/SmoothQuit/releases/latest")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return UpdateChecker.evaluate(data: try! JSONSerialization.data(withJSONObject: payload), response: response, currentVersion: current)
    }
    func testStableVersionsCompareNumericallyWithoutDowngrades() {
        guard case .available = evaluate("v1.10.0", current: "1.9.0") else { return XCTFail("1.10 is newer than 1.9") }
        XCTAssertEqual(evaluate("v1.6.0"), .current)
        XCTAssertEqual(evaluate("v1.5.0"), .current)
        guard case .available = evaluate("v2.0.0") else { return XCTFail("Major update missing") }
    }
    func testUnsafeOrPreviewMetadataNeverBecomesAnUpdate() {
        for result in [evaluate(draft: true), evaluate(prerelease: true), evaluate("v1.7.0-beta"),
                       evaluate("v1.7.0", link: "http://github.com/fkrzeminski-code/SmoothQuit/releases/tag/v1.7.0"),
                       evaluate(link: "https://github.com/other/repo/releases/tag/v1.7.0"),
                       evaluate(link: "https://github.com/fkrzeminski-code/SmoothQuit/releases/tag/v9.9.9"),
                       evaluate("v999999999.0.0"), evaluate("v1.7.0", current: "invalid")] {
            guard case .failed = result else { XCTFail("Invalid metadata accepted"); continue }
        }
        XCTAssertNil(ReleaseInfo.releaseURL("https://github.com@evil.example/fkrzeminski-code/SmoothQuit/releases/tag/v1.7.0"))
        XCTAssertNil(ReleaseInfo.releaseURL("https://github.com/fkrzeminski-code/SmoothQuit/releases/tag/v1.7.0?redirect=elsewhere"))
    }
    func testTransportAndServiceErrorsAreNotUpToDateResults() {
        for status in [403, 404, 429, 500] {
            guard case .failed = evaluate(status: status) else { XCTFail("HTTP error treated as success"); continue }
        }
        XCTAssertNotEqual(UpdateChecker.evaluate(data: nil, response: nil, currentVersion: "1.6.0"), .current)
        let response = HTTPURLResponse(url: URL(string: "https://api.github.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)
        guard case .failed = UpdateChecker.evaluate(data: Data("invalid json".utf8), response: response, currentVersion: "1.6.0") else { return XCTFail("Malformed JSON accepted") }
    }
    @MainActor func testManualCheckWorksWithAutomaticChecksOffAndDoesNotDuplicateRequests() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ReleaseProtocol.self]
        let checker = UpdateChecker(defaults: defaults, currentVersion: "1.6.0", session: URLSession(configuration: configuration))
        XCTAssertTrue(checker.automaticallyChecks)
        checker.automaticallyChecks = false
        checker.check(automatically: true)
        XCTAssertEqual(checker.phase, .idle)
        XCTAssertFalse(UpdateChecker(defaults: defaults).automaticallyChecks)
        let ready = expectation(description: "Manual response")
        ready.expectedFulfillmentCount = 1
        checker.onResult = { phase, automatically in
            XCTAssertFalse(automatically)
            guard case .available(let release) = phase else { return XCTFail("Missing available release") }
            XCTAssertEqual(release.version, "1.7.0"); ready.fulfill()
        }
        checker.check(); checker.check()
        XCTAssertTrue(checker.isChecking)
        wait(for: [ready], timeout: 2)
    }
    @MainActor func testDisablingAutomaticChecksSuppressesAnInFlightNotification() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ReleaseProtocol.self]
        let checker = UpdateChecker(defaults: defaults, currentVersion: "1.6.0", session: URLSession(configuration: configuration))
        var callbacks = 0
        checker.onResult = { _, _ in callbacks += 1 }
        checker.check(automatically: true)
        checker.automaticallyChecks = false
        let deadline = Date().addingTimeInterval(2)
        while checker.isChecking, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(callbacks, 0)
        XCTAssertEqual(checker.availableRelease?.version, "1.7.0")
    }
    func testActivityGroupsOnlyTheMatchingQuitAttempt() {
        let first = UUID(), second = UUID()
        let request = Diagnostic(bundleID: "com.apple.iCal", message: "request", requested: true, quitID: first)
        let exit = Diagnostic(bundleID: "com.apple.iCal", message: "exit", completed: true, quitID: first)
        let another = Diagnostic(bundleID: "com.apple.iCal", message: "another launch", requested: true, quitID: second)
        let raw = Diagnostic(bundleID: "com.apple.iCal", message: "AX read")
        let rows = Diagnostic.activityEntries([another, exit, request, raw], historyOnly: true)
        XCTAssertEqual(rows.map(\.id), [another.id, exit.id])
        XCTAssertEqual(Diagnostic.activityEntries([request], historyOnly: false).map(\.id), [request.id])
    }
    @MainActor func testQuickExceptionPreservesModeAndCustomDelayAndReportIsBounded() throws {
        let suite = "pl.smoothquit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        model.add(id: "com.apple.TextEdit", name: "TextEdit")
        model.preferences.rules[0].delay = 1.25
        model.keepRunning("com.apple.TextEdit", name: "TextEdit")
        XCTAssertEqual(model.preferences.mode, .include)
        XCTAssertEqual(model.preferences.rules.count, 1)
        XCTAssertEqual(model.preferences.rules[0].delay, 1.25)
        XCTAssertEqual(model.preferences.rules[0].behavior, .never)
        model.keepRunning("pl.smoothquit.app", name: "Self")
        XCTAssertEqual(model.preferences.rules.count, 1)
        let entries = (0...25).map { Diagnostic(bundleID: "com.apple.TextEdit", message: "Event-\($0)") }
        let report = model.diagnosticReport(entries: entries)
        XCTAssertTrue(report.contains("macOS")); XCTAssertTrue(report.contains("com.apple.TextEdit"))
        XCTAssertTrue(report.contains("Event-19")); XCTAssertFalse(report.contains("Event-20"))
        XCTAssertFalse(report.contains(NSHomeDirectory()))
    }
}
