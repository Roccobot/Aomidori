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

    /// Where saving under `name` would write, and whether a file is already there (the
    /// Playground asks before replacing it).
    public func savePlan(forName name: String) -> StyleSavePlan {
        let fileName = Self.fileName(for: name)
        let url = directory.appendingPathComponent(fileName)
        // The folder may be on a case-insensitive volume: "a.css" replaces "A.css".
        let existing = styles().first { $0.name.compare(fileName, options: .caseInsensitive) == .orderedSame }
        return StyleSavePlan(fileName: existing?.name ?? fileName, url: existing?.url ?? url, replacesExisting: existing != nil)
    }

    /// A file name for `base` that no style has yet: `base.css`, then `base 2.css`, `base 3.css`…
    public func availableName(for base: String) -> String {
        let stem = (Self.fileName(for: base) as NSString).deletingPathExtension
        var candidate = stem + ".css"
        var number = 2
        while savePlan(forName: candidate).replacesExisting {
            candidate = "\(stem) \(number).css"
            number += 1
        }
        return candidate
    }

    /// Saves CSS into the folder (used by the CSS Playground), so it appears in the reader's style
    /// list at once through the folder watcher. Written as `CSSFile.data(for:)` describes.
    /// An existing file is replaced only with `overwrite`. Returns the saved file.
    @discardableResult
    public func save(css: String, named name: String, overwrite: Bool = false) throws -> StyleFile {
        let plan = savePlan(forName: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if plan.replacesExisting, !overwrite {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: plan.url.path])
        }
        try CSSFile.data(for: css).write(to: plan.url, options: .atomic)
        let date = (try? plan.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        return StyleFile(name: plan.fileName, url: plan.url, modificationDate: date)
    }

    /// A safe file name: path separators and leading dots (hidden files) removed, `.css`
    /// appended if missing.
    public static func fileName(for name: String) -> String {
        var stem = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if stem.lowercased().hasSuffix(".css") { stem.removeLast(4) }
        while stem.hasPrefix(".") { stem.removeFirst() }
        stem = stem.trimmingCharacters(in: .whitespaces)
        return (stem.isEmpty ? "Style" : stem) + ".css"
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
        return CSSFile.text(from: data)
    }

    /// Whether CSS text (not yet saved, as in the Playground) or a local sheet it `@import`s
    /// has `prefers-color-scheme` rules. Relative imports resolve in this folder.
    public func handlesColorScheme(css: String) -> Bool {
        if CSSScanner.mentionsColorScheme(css) { return true }
        var visited: Set<URL> = []
        for reference in CSSScanner.importedURLs(css) {
            guard !reference.contains(":"),
                  let imported = URL(string: reference, relativeTo: directory.appendingPathComponent("_")) else { continue }
            if handlesColorScheme(at: imported, visited: &visited) { return true }
        }
        return false
    }
}

/// Where saving a style would write.
public struct StyleSavePlan: Equatable, Sendable {
    /// The file name, as it is (or will be) on disk.
    public let fileName: String
    public let url: URL
    /// A style with that name (compared without case) already exists.
    public let replacesExisting: Bool
}

/// How style sheets are read and written.
///
/// Written for the widest compatibility (EPUB readers, editors, other platforms): UTF-8 without
/// BOM, LF line endings, exactly the text with one final newline. Non-ASCII characters stay
/// UTF-8. No `@charset` rule is added: CSS without one, and without BOM, is read as UTF-8 by
/// browsers when the document or the server says nothing else, and an `@charset` that is not
/// the very first bytes is ignored anyway.
public enum CSSFile {
    public static func data(for css: String) -> Data {
        Data(normalized(css).utf8)
    }

    /// CSS text as it is written to disk: no BOM, LF line endings, one final newline (an empty
    /// text stays empty).
    public static func normalized(_ css: String) -> String {
        var text = css.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        if !text.isEmpty, !text.hasSuffix("\n") { text.append("\n") }
        return text
    }

    /// The text of a style sheet file: UTF-8 (a BOM is dropped), else Latin-1, which can decode
    /// any bytes.
    public static func text(from data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .isoLatin1)
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
