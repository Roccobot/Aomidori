import Foundation

/// The books listed on the empty window: `NSDocumentController`'s recent documents, most recent
/// first, as many as the system's Recent Items setting allows, without files that are gone
/// (or on a volume that is not mounted: they come back when it is).
public struct RecentBook: Equatable, Sendable {
    public let url: URL
    /// The file name without the `.epub` extension.
    public let title: String
}

public enum RecentBooks {
    public static func list(_ urls: [URL], limit: Int, fileExists: (URL) -> Bool) -> [RecentBook] {
        var seen: Set<String> = []
        var books: [RecentBook] = []
        for url in urls where url.isFileURL && books.count < max(limit, 0) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted, fileExists(url) else { continue }
            books.append(RecentBook(url: url, title: title(of: url)))
        }
        return books
    }

    /// "Una descrizione di Terramare.epub" → "Una descrizione di Terramare". Other extensions
    /// are part of the name.
    public static func title(of url: URL) -> String {
        let name = url.lastPathComponent
        guard url.pathExtension.lowercased() == "epub", name.count > 5 else { return name }
        return String(name.dropLast(5))
    }
}

/// Graphe's drop-zone book (`aomidori-dropzone-book.svg`, drawn in `currentColor`), recoloured
/// for the window's appearance. The frame round it is drawn in code (`DashedFrame`).
public enum EmptyStateArt {
    public static let lightTint = "#43B59E"
    public static let darkTint = "#5FD4BC"

    /// The SVG with its colour set (`#RRGGBB`).
    public static func svg(_ template: String, color: String) -> String {
        template.replacingOccurrences(of: ##"color="#[0-9A-Fa-f]{6}""##, with: "color=\"\(color)\"",
                                      options: .regularExpression)
    }
}
