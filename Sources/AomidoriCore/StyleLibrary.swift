import Foundation

/// A user style sheet in the styles folder.
public struct StyleFile: Hashable, Sendable {
    /// File name, including the `.css` extension. It is the style's identity.
    public let name: String
    public let url: URL
    public let modificationDate: Date?

    /// The name shown in menus: the file name without extension.
    public var displayName: String { (name as NSString).deletingPathExtension }
}

/// The folder of user style sheets (`~/Library/Application Support/Aomidori/Styles`).
/// Files are plain CSS and can be edited by any external application.
public struct StyleLibrary: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Creates the folder if needed and installs `bundledStyle` under `name` when no file has that
    /// name. An existing file is never overwritten: it may hold the user's own edits.
    public func prepare(installing bundledStyle: URL?, as name: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        if let bundledStyle, !fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: bundledStyle, to: destination)
        }
    }

    /// The `.css` files in the folder, sorted as the Finder sorts them.
    public func styles() -> [StyleFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "css" }
            .compactMap { url -> StyleFile? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile ?? true else { return nil }
                return StyleFile(name: url.lastPathComponent, url: url, modificationDate: values?.contentModificationDate)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The text of a style file, decoded as UTF-8 (with BOM), falling back to Latin-1.
    public func contents(of style: StyleFile) -> String? {
        Self.readText(at: style.url)
    }

    /// Whether the style, or any local sheet it `@import`s, has `prefers-color-scheme` rules.
    public func handlesColorScheme(_ style: StyleFile) -> Bool {
        var visited: Set<URL> = []
        return handlesColorScheme(at: style.url, visited: &visited)
    }

    private func handlesColorScheme(at url: URL, visited: inout Set<URL>) -> Bool {
        let url = url.standardizedFileURL
        guard visited.insert(url).inserted, visited.count <= 16, let css = Self.readText(at: url) else { return false }
        if CSSScanner.mentionsColorScheme(css) { return true }
        for reference in CSSScanner.importedURLs(css) {
            // Only relative, local imports can be followed; remote ones are not fetched.
            guard !reference.contains(":"), let imported = URL(string: reference, relativeTo: url) else { continue }
            if handlesColorScheme(at: imported, visited: &visited) { return true }
        }
        return false
    }

    static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

/// Moving through the styles list, wrapping around at both ends.
public enum StyleCycle {
    /// The style `offset` positions away from `name`. If `name` is not in the list,
    /// moving forward starts from the first style and moving backward from the last.
    public static func style(from name: String?, offset: Int, in styles: [StyleFile]) -> StyleFile? {
        guard !styles.isEmpty else { return nil }
        guard let name, let current = styles.firstIndex(where: { $0.name == name }) else {
            return offset >= 0 ? styles.first : styles.last
        }
        let count = styles.count
        return styles[((current + offset) % count + count) % count]
    }
}
