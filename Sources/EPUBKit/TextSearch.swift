import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// One occurrence of a search query in the book.
public struct SearchHit: Equatable, Sendable {
    public let spineIndex: Int
    public let path: String
    /// Index of this occurrence among the query's occurrences in the same spine item.
    public let occurrence: Int
    /// Where the occurrence sits in the item's text, 0...1: a fallback for scrolling to it.
    public let fraction: Double
    /// A short excerpt around the occurrence, on one line.
    public let snippet: String
    /// The occurrence inside `snippet`, in UTF-16 units (for `NSAttributedString`).
    public let matchLocation: Int
    public let matchLength: Int
}

/// Full-text search over every spine item. The plain text of each item is extracted once,
/// on first use, and kept for later queries. Thread-safe; meant to run off the main thread.
public final class EPUBTextIndex: @unchecked Sendable {
    private let publication: EPUBPublication
    private let lock = NSLock()
    private var texts: [Int: String] = [:]

    /// Searches stop collecting after this many hits.
    public static let defaultLimit = 500

    public init(publication: EPUBPublication) {
        self.publication = publication
    }

    /// Case-, diacritic- and width-insensitive; typographic quotes match straight ones.
    /// Queries shorter than two characters (after trimming) give no hits.
    public func search(_ query: String, limit: Int = EPUBTextIndex.defaultLimit,
                       isCancelled: () -> Bool = { false }) -> [SearchHit] {
        let needle = Self.folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard needle.count >= 2 else { return [] }
        var hits: [SearchHit] = []
        for (index, item) in publication.book.spine.enumerated() {
            if isCancelled() || hits.count >= limit { break }
            let text = self.text(at: index)
            hits += Self.hits(of: needle, in: text, spineIndex: index, path: item.path, limit: limit - hits.count)
        }
        return hits
    }

    /// The plain text of a spine item; empty if it cannot be read or parsed.
    public func text(at spineIndex: Int) -> String {
        if let cached = lock.withLock({ texts[spineIndex] }) { return cached }
        let path = publication.book.spine[spineIndex].path
        let text = (try? publication.resource(at: path)).flatMap { try? Self.plainText(ofXHTML: $0.data, path: path) } ?? ""
        lock.withLock { texts[spineIndex] = text }
        return text
    }

    // MARK: Pure helpers (internal for tests)

    /// Visible text of an XHTML document: the body without scripts and styles, with block
    /// boundaries turned into spaces and runs of white space collapsed.
    static func plainText(ofXHTML data: Data, path: String) throws -> String {
        let document = try XMLParsing.document(from: data, path: path)
        guard let root = document.rootElement() else { return "" }
        let body = root.descendants(named: "body").first ?? root
        var output = ""
        append(body, to: &output)
        return output.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func append(_ node: XMLNode, to output: inout String) {
        guard let element = node as? XMLElement else {
            if node.kind == .text { output += node.stringValue ?? "" }
            return
        }
        let name = element.localNameOrName.lowercased()
        if skippedElements.contains(name) { return }
        let isBlock = blockElements.contains(name)
        if isBlock { output += " " }
        for child in element.children ?? [] { append(child, to: &output) }
        if isBlock { output += " " }
    }

    private static let skippedElements: Set<String> = ["script", "style", "head", "rt", "rp"]
    private static let blockElements: Set<String> = [
        "p", "div", "br", "li", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote",
        "section", "article", "aside", "header", "footer", "td", "th", "tr", "figcaption", "pre", "hr",
    ]

    /// Folds typographic quotes to straight ones. Every replacement is one UTF-16 unit for one,
    /// so ranges found in the folded text are valid in the original.
    static func folded(_ text: String) -> String {
        var result = ""
        result.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{2018}", "\u{2019}", "\u{201B}", "\u{02BC}": result.unicodeScalars.append("'")
            case "\u{201C}", "\u{201D}", "\u{201F}": result.unicodeScalars.append("\"")
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func hits(of needle: String, in text: String, spineIndex: Int, path: String, limit: Int) -> [SearchHit] {
        let original = text as NSString
        let haystack = folded(text) as NSString
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        var hits: [SearchHit] = []
        var searchRange = NSRange(location: 0, length: haystack.length)
        while hits.count < limit {
            let found = haystack.range(of: needle, options: options, range: searchRange)
            guard found.location != NSNotFound, found.length > 0 else { break }
            let (snippet, location) = excerpt(of: original, around: found)
            hits.append(SearchHit(
                spineIndex: spineIndex, path: path, occurrence: hits.count,
                fraction: Double(found.location) / Double(max(haystack.length, 1)),
                snippet: snippet, matchLocation: location, matchLength: found.length
            ))
            let next = found.location + found.length
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return hits
    }

    /// About 40 characters before and 80 after the match, cut at word boundaries.
    private static func excerpt(of text: NSString, around match: NSRange) -> (String, Int) {
        var start = max(0, match.location - 40)
        var end = min(text.length, match.location + match.length + 80)
        if start > 0 {
            let space = text.range(of: " ", options: [], range: NSRange(location: start, length: match.location - start))
            if space.location != NSNotFound { start = space.location + 1 }
        }
        if end < text.length {
            let tail = NSRange(location: match.location + match.length, length: end - match.location - match.length)
            let space = text.range(of: " ", options: .backwards, range: tail)
            if space.location != NSNotFound { end = space.location }
        }
        // Never split a surrogate pair or a composed character at the edges.
        let range = text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        let prefix = range.location > 0 ? "…" : ""
        let suffix = range.location + range.length < text.length ? "…" : ""
        let snippet = prefix + text.substring(with: range) + suffix
        return (snippet, match.location - range.location + (prefix as NSString).length)
    }
}
