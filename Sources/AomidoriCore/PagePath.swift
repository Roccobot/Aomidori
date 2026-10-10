import Foundation

/// Where a path served to a page leads (`aomidori://<host>/<path>`, without the leading slash).
/// Only the book, the user's `Styles` and `Fonts` folders, the Playground's unsaved buffer and the
/// chosen system font files are reachable; anything else, `.` and `..` included, is `nil`.
/// Author: Rocco Casadei, a.k.a. Roccobot
public enum PagePath: Equatable, Sendable {
    /// A resource of the open book, by container-relative path.
    case book(String)
    /// A file of the user's support folder: `["Styles", "Reading.css"]`, `["Fonts", "a.otf"]`.
    case userFile([String])
    /// The Playground's unsaved buffer, by its file name.
    case playgroundBuffer(String)
    /// A file of the installed family chosen as custom font, by its token.
    case systemFont(token: String)

    public static let userPrefix = ".aomidori/"
    public static let playgroundPrefix = ".playground-"
    static let userFolders: Set<String> = ["Styles", "Fonts"]

    public init?(_ path: String) {
        guard path.hasPrefix(Self.userPrefix) else {
            self = .book(path)
            return
        }
        let components = path.dropFirst(Self.userPrefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty, !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else { return nil }
        if components.count == 2, components[0] == "SystemFonts" {
            self = .systemFont(token: components[1])
        } else if components.count == 2, components[0] == "Styles", components[1].hasPrefix(Self.playgroundPrefix) {
            self = .playgroundBuffer(components[1])
        } else if components.count >= 2, Self.userFolders.contains(components[0]) {
            self = .userFile(components)
        } else {
            return nil
        }
    }
}
