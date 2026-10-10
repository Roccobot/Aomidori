import Foundation

/// Decides whether a page is loaded again after WebKit's content process ended. A page that
/// crashes the process every time would otherwise be reloaded forever: each page gets
/// `attempts` reloads within `window`, then stays as it is.
/// Author: Rocco Casadei, a.k.a. Roccobot
public struct CrashRecovery: Sendable {
    public static let attempts = 2
    public static let window: TimeInterval = 60

    private var reloads: [String: [Date]] = [:]

    public init() {}

    public mutating func shouldReload(_ path: String, at now: Date = Date()) -> Bool {
        let recent = (reloads[path] ?? []).filter { now.timeIntervalSince($0) < Self.window }
        guard recent.count < Self.attempts else {
            reloads[path] = recent
            return false
        }
        reloads[path] = recent + [now]
        return true
    }
}
