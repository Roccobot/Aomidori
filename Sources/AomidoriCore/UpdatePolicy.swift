import Foundation

/// When the Sparkle updater may run. Sparkle checks the feed itself; this decides only whether
/// the updater starts at all, so that a build that cannot verify updates, or a scripted smoke
/// session on Rocco's Mac, never talks to the feed or writes Sparkle's settings.
public enum UpdatePolicy {
    /// The appcast, served by GitHub Pages from `publish/appcast.xml`. Info.plist's `SUFeedURL`
    /// must say the same (a test checks it).
    public static let feedURL = "https://roccobot.github.io/Aomidori/appcast.xml"

    /// Why the updater stays off, or `nil` when it may start.
    public static func reasonNotToStart(feedURL: String?, publicEDKey: String?, smokeTestActive: Bool) -> String? {
        if smokeTestActive { return "smoke test" }
        guard let feedURL, let url = URL(string: feedURL), url.scheme == "https", url.host != nil else {
            return "no HTTPS feed URL (SUFeedURL)"
        }
        guard let publicEDKey, isEd25519PublicKey(publicEDKey) else { return "no EdDSA public key (SUPublicEDKey)" }
        return nil
    }

    /// A Sparkle EdDSA public key: 32 bytes, base64 encoded (`generate_keys` prints it).
    public static func isEd25519PublicKey(_ text: String) -> Bool {
        Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))?.count == 32
    }
}
