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
    /// Parses XML without ever loading external entities or DTDs. XHTML files often rely on
    /// HTML named entities (`&nbsp;`) declared only in the XHTML DTD: those are rewritten as
    /// numeric references first, because some parsers silently drop unknown entities.
    static func document(from data: Data, path: String) throws -> XMLDocument {
        let options: XMLNode.Options = [.nodeLoadExternalEntitiesNever]
        if let text = String(data: data, encoding: .utf8), text.contains("&") {
            if let document = try? XMLDocument(xmlString: replacingHTMLEntities(in: text), options: options) {
                return document
            }
        } else if let document = try? XMLDocument(data: data, options: options) {
            return document
        }
        throw EPUBError.malformedXML(path: path)
    }

    private static func replacingHTMLEntities(in text: String) -> String {
        var result = text
        for (name, codePoint) in htmlEntities {
            result = result.replacingOccurrences(of: "&\(name);", with: "&#\(codePoint);")
        }
        return result
    }

    // The entities that actually show up in navigation documents; XML's own five are untouched.
    private static let htmlEntities: [(String, Int)] = [
        ("nbsp", 160), ("shy", 173), ("ndash", 8211), ("mdash", 8212), ("hellip", 8230),
        ("lsquo", 8216), ("rsquo", 8217), ("ldquo", 8220), ("rdquo", 8221), ("laquo", 171), ("raquo", 187),
        ("copy", 169), ("reg", 174), ("trade", 8482), ("middot", 183), ("bull", 8226), ("deg", 176),
        ("agrave", 224), ("egrave", 232), ("eacute", 233), ("igrave", 236), ("ograve", 242), ("ugrave", 249),
        ("Agrave", 192), ("Egrave", 200), ("Eacute", 201), ("Igrave", 204), ("Ograve", 210), ("Ugrave", 217),
        ("thinsp", 8201), ("ensp", 8194), ("emsp", 8195), ("zwnj", 8204), ("zwj", 8205),
    ]
}
