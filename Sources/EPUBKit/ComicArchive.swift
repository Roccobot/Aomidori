import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// A comic book archive (CBZ, a ZIP of pictures, or CBR, a RAR) read as a publication with a single document,
/// generated here, that shows every page one below the other: the reader scrolls it like a
/// chapter, and its table of contents lists the pages. The pictures are served from the archive
/// like any resource of a book.
/// Author: Rocco Casadei, a.k.a. Roccobot
public enum ComicArchive {
    /// The generated document, at the archive's root so the pictures' paths resolve as they are.
    public static let documentPath = "aomidori-comic.xhtml"
    static let pictureExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "avif"]

    /// The pages: the archive's pictures in the Finder's order (numbers compared as numbers, so
    /// `2` comes before `10`), leaving out macOS's `__MACOSX` copies and every hidden file.
    public static func pages(in paths: [String]) -> [String] {
        paths.filter(isPage).sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending }
    }

    static func isPage(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        guard let name = components.last, !components.contains(where: { $0.hasPrefix(".") || $0 == "__MACOSX" }) else { return false }
        return pictureExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    /// What a comic needs from its archive: the pages and the `ComicInfo.xml` at its root.
    static func isNeeded(_ path: String) -> Bool {
        isPage(path) || path.lowercased() == "comicinfo.xml"
    }

    /// The archive's container: a ZIP is read lazily, a file at a time; anything else (RAR, RAR5,
    /// 7z, whatever the extension says) goes to libarchive, on macOS.
    static func container(at url: URL) throws -> any ResourceContainer {
        do {
            return try ZIPContainer(url: url)
        } catch EPUBError.unreadableArchive {
            #if canImport(CArchive)
            return try LibArchiveContainer(url: url, keep: isNeeded)
            #else
            throw EPUBError.unreadableArchive
            #endif
        }
    }

    /// The title in a `ComicInfo.xml`: its `Title`, else its `Series` and `Number`, else nothing.
    public static func title(fromComicInfo data: Data) -> String? {
        guard let root = (try? XMLParsing.document(from: data, path: "ComicInfo.xml"))?.rootElement() else { return nil }
        func text(_ name: String) -> String? {
            root.firstChild(named: name).map(\.normalizedText).flatMap { $0.isEmpty ? nil : $0 }
        }
        if let title = text("Title") { return title }
        guard let series = text("Series") else { return nil }
        return [series, text("Number")].compactMap { $0 }.joined(separator: " ")
    }

    /// The book (one spine item, the pages as table of contents) and its generated document.
    static func publication(in container: any ResourceContainer) throws -> (book: EPUBBook, document: EPUBResource) {
        let pages = pages(in: container.paths)
        guard !pages.isEmpty else { throw EPUBError.emptySpine }
        let info = container.storedPath(for: "ComicInfo.xml").flatMap { try? container.data(at: $0) }
        let title = info.flatMap(title(fromComicInfo:))

        let manifest = [ManifestItem(id: "comic", path: documentPath, mediaType: "application/xhtml+xml", properties: [])]
            + pages.enumerated().map { ManifestItem(id: "p\($0 + 1)", path: $1, mediaType: MediaType.forPath($1), properties: []) }
        let book = EPUBBook(
            identifier: "", title: title, language: nil, packagePath: documentPath, manifest: manifest,
            spine: [SpineItem(idref: "comic", path: documentPath, mediaType: "application/xhtml+xml", isLinear: true)],
            toc: pages.indices.map { TOCEntry(title: "\($0 + 1)", path: documentPath, fragment: "p\($0 + 1)", children: []) },
            coverPath: pages.first)
        return (book, EPUBResource(data: Data(document(pages: pages, title: title).utf8), mediaType: "application/xhtml+xml"))
    }

    /// One picture per page, as wide as the text column (the whole window, unless a user style
    /// narrows the body). The sizing is inline because inline styles on pictures survive the
    /// reader's style override.
    static func document(pages: [String], title: String?) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#;")
        let pictures = pages.enumerated().map { index, path in
            let source = path.split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }.joined(separator: "/")
            return #"<img id="p\#(index + 1)" src="\#(escape(source))" alt="\#(index + 1)" style="display: block; width: 100%; height: auto; margin: 0 auto;"/>"#
        }
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><meta charset="utf-8"/><title>\(escape(title ?? ""))</title></head>
        <body style="margin: 0; padding: 0;">
        \(pictures.joined(separator: "\n"))
        </body>
        </html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
