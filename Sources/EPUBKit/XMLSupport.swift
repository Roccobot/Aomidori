import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Namespace-agnostic helpers over Foundation's XML tree. EPUB files in the wild mix default
/// namespaces, prefixes and missing declarations, so elements are matched by local name.
extension XMLElement {
    var localNameOrName: String {
        localName ?? name.map { $0.split(separator: ":").last.map(String.init) ?? $0 } ?? ""
    }

    func childElements(named name: String) -> [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localNameOrName == name }
    }

    func firstChild(named name: String) -> XMLElement? {
        (children ?? []).lazy.compactMap { $0 as? XMLElement }.first { $0.localNameOrName == name }
    }

    /// Depth-first search of all descendants (excluding self) with the given local name.
    func descendants(named name: String) -> [XMLElement] {
        var found: [XMLElement] = []
        var stack = (children ?? []).reversed().compactMap { $0 as? XMLElement }
        while let element = stack.popLast() {
            if element.localNameOrName == name { found.append(element) }
            stack.append(contentsOf: (element.children ?? []).reversed().compactMap { $0 as? XMLElement })
        }
        return found
    }

    /// Value of an unprefixed attribute, or of a prefixed one by local name (`epub:type` -> `type`).
    func attributeValue(_ name: String) -> String? {
        if let value = attribute(forName: name)?.stringValue { return value }
        return attributes?.first { attribute in
            let attributeName = attribute.name ?? ""
            return attribute.localName == name || attributeName.split(separator: ":").last.map(String.init) == name
        }?.stringValue
    }

    /// Text content with runs of white space collapsed to single spaces.
    var normalizedText: String {
        (stringValue ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum XMLParsing {
    /// Parses a book's XML without ever loading external entities or DTDs, and without its
    /// document type declaration: an internal subset can declare entities that expand
    /// exponentially, and an EPUB never needs one. With the DTD gone, named references are
    /// resolved here in one pass: the XHTML DTD's HTML entities become numeric references,
    /// XML's own five stay, and any other name is kept as literal text instead of failing
    /// the whole document.
    static func document(from data: Data, path: String) throws -> XMLDocument {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw EPUBError.malformedXML(path: path)
        }
        let prepared = resolvingEntities(in: removingDoctype(from: text))
        guard let document = try? XMLDocument(xmlString: prepared, options: [.nodeLoadExternalEntitiesNever]) else {
            throw EPUBError.malformedXML(path: path)
        }
        return document
    }

    /// The `<!DOCTYPE ...>` declaration, with its internal subset in brackets if there is one.
    private static let doctype = try! NSRegularExpression(
        pattern: #"<!DOCTYPE\b(?:[^\[>"']|"[^"]*"|'[^']*')*(?:\[[\s\S]*?\]\s*)?>"#,
        options: [.caseInsensitive])

    static func removingDoctype(from text: String) -> String {
        guard text.range(of: "<!DOCTYPE", options: [.caseInsensitive]) != nil else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return doctype.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    private static let xmlEntities: Set<String> = ["amp", "lt", "gt", "quot", "apos"]

    static func resolvingEntities(in text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var rest = text[...]
        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            let afterAmpersand = rest.index(after: ampersand)
            let name = rest[afterAmpersand...].prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
            let semicolon = name.endIndex
            guard !name.isEmpty, semicolon < rest.endIndex, rest[semicolon] == ";",
                  name.first!.isLetter, !xmlEntities.contains(String(name)) else {
                // Numeric references, XML's own entities and stray ampersands go through as written.
                result += "&"
                rest = rest[afterAmpersand...]
                continue
            }
            if let codePoint = htmlEntities[String(name)] {
                result += "&#\(codePoint);"
            } else {
                result += "&amp;\(name);"
            }
            rest = rest[rest.index(after: semicolon)...]
        }
        result += rest
        return result
    }
}
