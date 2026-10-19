import Foundation

public enum SelectionMode: String, Codable, CaseIterable { case include, exclude }
public enum RuleBehavior: String, Codable, CaseIterable { case mode, allow, never }

public struct AppRule: Codable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var behavior: RuleBehavior = .mode
    public var delay: Double?
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Preferences: Codable, Equatable {
    public var enabled = true
    public var mode: SelectionMode = .include
    public var delay = 0.5
    public var monitorHidden = false
    public var monitorMinimized = true
    public var pauseUntil: Date?
    public var rules: [AppRule] = []
    public init() {}

    public static func validBundleID(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return value.count <= 255 && parts.count >= 2 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }
    }
    public static func boundedDelay(_ value: Double) -> Double {
        value.isFinite ? min(2, max(0.2, value)) : 0.5
    }
    public var isPaused: Bool { pauseUntil.map { $0 > Date() } ?? false }
    public func reasonExcluded(_ id: String, ownID: String = "pl.smoothquit.app", now: Date = Date()) -> String? {
        if !enabled { return "Automatic Quit disabled" }
        if let pauseUntil, pauseUntil > now { return "Paused" }
        if id == ownID || id == "pl.smoothquit.app" || ["com.apple.dock", "com.apple.loginwindow", "com.apple.SystemUIServer", "com.apple.WindowManager", "com.apple.systempreferences"].contains(id) {
            return "Protected system app or SmoothQuit"
        }
        let rule = rules.first { $0.id == id }
        if rule?.behavior == .never { return "Rule: never quit" }
        if rule?.behavior == .allow { return nil }
        if id == "com.apple.finder" { return "Finder protected — requires an explicit Always allow rule" }
        return (mode == .include ? rule != nil : rule == nil) ? nil : "Outside Include list / on Exclude list"
    }
    public func delay(for id: String) -> Double {
        Self.boundedDelay(rules.first { $0.id == id }?.delay ?? delay)
    }
}

public enum WindowKind: Equatable { case normal, auxiliary, unknown }
public struct ObservedWindow: Equatable {
    public var id: UInt64
    public var kind: WindowKind
    public var minimized: Bool
    public init(_ id: UInt64, _ kind: WindowKind = .normal, minimized: Bool = false) {
        self.id = id; self.kind = kind; self.minimized = minimized
    }
}

/// No snapshot can silently discard a known window. Only its destruction can.
public struct CloseGate {
    public struct Pending: Equatable {
        public let token: UInt64
        public let closedAt: TimeInterval
        public let deadline: TimeInterval
    }
    public private(set) var windows: [UInt64: ObservedWindow] = [:]
    public private(set) var pending: Pending?
    private var generation: UInt64 = 0
    public init() {}

    public mutating func cancel() { generation &+= 1; pending = nil }
    public mutating func created() { cancel() }
    public mutating func observe(_ snapshot: [ObservedWindow]) {
        if snapshot.contains(where: { windows[$0.id] == nil }) { cancel() }
        for window in snapshot { windows[window.id] = window }
    }
    @discardableResult
    public mutating func destroyed(_ id: UInt64, now: TimeInterval, delay: Double) -> Pending? {
        guard let removed = windows.removeValue(forKey: id) else { cancel(); return nil }
        // A confirmed auxiliary close only removes a veto. Keep the original
        // normal-window deadline; an auxiliary close alone never requests Quit.
        if removed.kind == .auxiliary { return nil }
        cancel()
        guard removed.kind == .normal else { return nil }
        let value = Pending(token: generation, closedAt: now, deadline: now + Preferences.boundedDelay(delay))
        pending = value
        return value
    }
    public func canQuit(token: UInt64, now: TimeInterval, snapshot: [ObservedWindow]?, cgHasWindows: Bool?, eligible: Bool, trusted: Bool) -> Bool {
        guard let pending, pending.token == token, now >= pending.deadline,
              eligible, trusted, let snapshot, snapshot.isEmpty,
              windows.isEmpty, cgHasWindows == false else { return false }
        return true
    }
}
