import Foundation
import Testing
@testable import EPUBKit

@Suite("Text search")
struct TextSearchTests {
    @Test func plainTextSkipsScriptsAndSeparatesBlocks() throws {
        let xhtml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Titolo</title><style>p{}</style></head>
        <body><h1>Capitolo</h1><p>Primo&nbsp;paragrafo.</p><p>Secondo<br/>rigo <ruby>漢<rt>kan</rt></ruby></p>
        <script>var x = 1;</script></body></html>
        """
        let text = try EPUBTextIndex.plainText(ofXHTML: Data(xhtml.utf8), path: "c.xhtml")
        #expect(text == "Capitolo Primo paragrafo. Secondo rigo 漢") // no-break spaces collapse too
    }

    @Test func matchesIgnoringCaseDiacriticsAndQuotes() {
        let text = "L\u{2019}acqua è calma. Poi l'ACQUA sale, e l’Àcqua torna."
        let hits = EPUBTextIndex.hits(of: EPUBTextIndex.folded("l'acqua"), in: text, spineIndex: 2, path: "t.xhtml", limit: 10)
        #expect(hits.count == 3)
        #expect(hits.map(\.occurrence) == [0, 1, 2])
        #expect(hits.allSatisfy { $0.spineIndex == 2 && $0.path == "t.xhtml" })
        let first = hits[0]
        #expect((first.snippet as NSString).substring(with: NSRange(location: first.matchLocation, length: first.matchLength)) == "L\u{2019}acqua")
        #expect(first.fraction == 0)
        #expect(EPUBTextIndex.hits(of: "acqua", in: text, spineIndex: 0, path: "", limit: 2).count == 2)
    }

    @Test func snippetsAreTrimmedAtWords() {
        let words = (1...60).map { "parola\($0)" }.joined(separator: " ")
        let hit = EPUBTextIndex.hits(of: "parola30", in: words, spineIndex: 0, path: "", limit: 1)[0]
        #expect(hit.snippet.hasPrefix("…parola"))
        #expect(hit.snippet.hasSuffix("…"))
        #expect(!hit.snippet.contains("  "))
        #expect((hit.snippet as NSString).substring(with: NSRange(location: hit.matchLocation, length: hit.matchLength)) == "parola30")
        #expect(hit.fraction > 0.4 && hit.fraction < 0.6)
    }

    @Test func searchesTheWholeBook() throws {
        let url = try EPUBFixture.epub3().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let index = EPUBTextIndex(publication: try EPUBPublication(contentsOf: url))
        let hits = index.search("testo")
        #expect(!hits.isEmpty)
        #expect(Set(hits.map(\.spineIndex)).count == hits.count) // one "Testo." per chapter
        #expect(index.search(" t ").isEmpty)
        #expect(index.search("testo", isCancelled: { true }).isEmpty)
    }
}
