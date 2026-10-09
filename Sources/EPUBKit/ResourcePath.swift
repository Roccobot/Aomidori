import Foundation

/// Helpers for container-relative paths. Paths never start with `/` and are not percent-encoded.
public enum ResourcePath {
    /// The directory part of `path`, with a trailing slash, or an empty string at the root.
    public static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    /// Resolves a URL reference found in a document at `basePath`.
    ///
    /// Returns `nil` for references that leave the container (they carry a URL scheme,
    /// such as `https:` or `mailto:`). A reference made only of a fragment resolves to `basePath`.
    public static func resolve(_ reference: String, relativeTo basePath: String) -> (path: String, fragment: String?)? {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasScheme(trimmed) { return nil }

        var body = Substring(trimmed)
        var fragment: String?
        if let hash = body.firstIndex(of: "#") {
            let raw = body[body.index(after: hash)...]
            fragment = raw.isEmpty ? nil : (String(raw).removingPercentEncoding ?? String(raw))
            body = body[..<hash]
        }
        if let query = body.firstIndex(of: "?") { body = body[..<query] }

        let decoded = String(body).removingPercentEncoding ?? String(body)
        if decoded.isEmpty { return (basePath, fragment) }
        let joined = decoded.hasPrefix("/") ? String(decoded.dropFirst()) : directory(of: basePath) + decoded
        return (normalize(joined), fragment)
    }

    /// Removes `.` and `..` segments and empty segments. `..` never climbs above the root.
    public static func normalize(_ path: String) -> String {
        var segments: [Substring] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".": continue
            case "..": if !segments.isEmpty { segments.removeLast() }
            default: segments.append(segment)
            }
        }
        return segments.joined(separator: "/")
    }

    private static func hasScheme(_ reference: String) -> Bool {
        guard let colon = reference.firstIndex(of: ":"), colon != reference.startIndex else { return false }
        let scheme = reference[..<colon]
        guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
        return scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == ".") }
    }
}
