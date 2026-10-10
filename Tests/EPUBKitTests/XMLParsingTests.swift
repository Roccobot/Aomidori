import Foundation
import Testing
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import EPUBKit

@Suite("XML parsing")
struct XMLParsingTests {
    static func parse(_ text: String) throws -> XMLDocument {
        try XMLParsing.document(from: Data(text.utf8), path: "test.xhtml")
    }

    /// An internal DTD subset can declare entities that expand exponentially ("billion
    /// laughs"): a book must not be able to stall or exhaust the app with a few lines.
    @Test func internalEntityDeclarationsAreNotExpanded() throws {
        var declarations = #"<!ENTITY l0 "laughlaughlaughlaughlaughlaughlaughlaughlaughlaugh">"#
        for level in 1...6 {
            let previous = String(repeating: "&l\(level - 1);", count: 10)
            declarations += "\n<!ENTITY l\(level) \"\(previous)\">"
        }
        let text = """
        <?xml version="1.0"?>
        <!DOCTYPE html [
        \(declarations)
        ]>
        <html><body><p>&l6;</p></body></html>
        """
        let started = Date()
        let length = (try? Self.parse(text))?.rootElement()?.stringValue?.count ?? 0
        #expect(length < 1000)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    /// The XHTML DTD's named entities are never loaded, so every one of them is rewritten:
    /// an accented letter written as an entity must not vanish from the text.
    @Test func htmlNamedEntitiesKeepTheirLetters() throws {
        let document = try Self.parse("""
        <html><body><p>caf&eacute; perch&oacute; gar&ccedil;on &Uuml;ber na&iuml;ve &euro;&nbsp;5</p></body></html>
        """)
        #expect(document.rootElement()?.stringValue == "café perchó garçon Über naïve €\u{A0}5")
    }

    /// A reference that is neither XML's nor HTML's stays readable as written instead of
    /// failing the whole document or disappearing.
    @Test func unknownEntityStaysLiteral() throws {
        let document = try Self.parse("<html><body><p>a &bogus; b &amp; c</p></body></html>")
        #expect(document.rootElement()?.stringValue == "a &bogus; b & c")
    }

    /// A plain DOCTYPE with a public identifier (the usual XHTML one) still parses.
    @Test func publicDoctypeStillParses() throws {
        let document = try Self.parse("""
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml"><body><p>Testo&hellip;</p></body></html>
        """)
        #expect(document.rootElement()?.stringValue == "Testo\u{2026}")
    }
}
