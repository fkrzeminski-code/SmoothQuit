import AppKit
import Combine
import Foundation

// Native, one-shot checks. No installer, background polling, credentials or telemetry.
enum AppVersion {
    static let number = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    static let display = "SmoothQuit \(number)"
    static let repository = URL(string: "https://github.com/fkrzeminski-code/SmoothQuit")!
}

struct ReleaseInfo: Decodable, Equatable {
    let tag_name: String
    let html_url: String
    let draft: Bool
    let prerelease: Bool
    var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    var url: URL? { Self.releaseURL(html_url) }
    static func releaseURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "github.com",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/fkrzeminski-code/SmoothQuit/releases/tag/"),
              url.pathComponents.count == 6 else { return nil }
        return url
    }
    static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }), part.count <= 6 else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }
}

enum UpdatePhase: Equatable {
    case idle, checking, current, available(ReleaseInfo), failed(String)
    var message: String {
        switch self {
        case .idle: return L("Checks GitHub for a newer release.")
        case .checking: return L("Checking for updates…")
        case .current: return L("No newer release is available.")
        case .available(let release): return L("SmoothQuit %@ is available.", release.version)
        case .failed(let reason): return reason
        }
    }
}

final class UpdateChecker: ObservableObject {
    @Published var automaticallyChecks: Bool {
        didSet { defaults.set(automaticallyChecks, forKey: "automaticallyCheckUpdates") }
    }
    @Published private(set) var phase: UpdatePhase = .idle
    @Published var notificationHint: String?
    var onResult: ((UpdatePhase, Bool) -> Void)?
    private let defaults: UserDefaults
    private let currentVersion: String
    private let session: URLSession
    private var task: URLSessionDataTask?
    init(defaults: UserDefaults = .standard, currentVersion: String = AppVersion.number, session: URLSession? = nil) {
        self.defaults = defaults; self.currentVersion = currentVersion
        automaticallyChecks = defaults.object(forKey: "automaticallyCheckUpdates") as? Bool ?? true
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        self.session = session ?? URLSession(configuration: configuration)
    }
    deinit { task?.cancel(); session.invalidateAndCancel() }
    var isChecking: Bool { phase == .checking }
    var availableRelease: ReleaseInfo? {
        if case .available(let release) = phase { return release }; return nil
    }
    func check(automatically: Bool = false) {
        guard !isChecking, !automatically || automaticallyChecks else { return }
        notificationHint = nil
        phase = .checking
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/fkrzeminski-code/SmoothQuit/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SmoothQuit", forHTTPHeaderField: "User-Agent")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let result: UpdatePhase
            if error != nil { result = .failed(L("Could not connect to GitHub. Try again when you are online.")) }
            else { result = Self.evaluate(data: data, response: response as? HTTPURLResponse, currentVersion: self.currentVersion) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.phase = result; self.task = nil
                if !automatically || self.automaticallyChecks { self.onResult?(result, automatically) }
            }
        }
        task?.resume()
    }
    static func evaluate(data: Data?, response: HTTPURLResponse?, currentVersion: String) -> UpdatePhase {
        guard let response, response.url?.scheme == "https", response.url?.host == "api.github.com" else {
            return .failed(L("GitHub returned an unexpected response. Try again later."))
        }
        guard response.statusCode == 200 else {
            return .failed(response.statusCode == 403 || response.statusCode == 429
                ? L("GitHub is limiting update checks. Try again later.")
                : L("Could not read the latest release. Try again later."))
        }
        guard let data, data.count <= 2_000_000,
              let release = try? JSONDecoder().decode(ReleaseInfo.self, from: data),
              !release.draft, !release.prerelease, release.url?.lastPathComponent == release.tag_name,
              let latest = ReleaseInfo.components(release.version), let current = ReleaseInfo.components(currentVersion) else {
            return .failed(L("GitHub returned invalid release information. No update was opened."))
        }
        return current.lexicographicallyPrecedes(latest) ? .available(release) : .current
    }
    func openRelease() { if let url = availableRelease?.url { NSWorkspace.shared.open(url) } }
}
