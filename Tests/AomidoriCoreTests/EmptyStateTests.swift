import Foundation
import Testing
@testable import AomidoriCore

@Suite("Empty window")
struct EmptyStateTests {
    private let a = URL(fileURLWithPath: "/Books/Una descrizione di Terramare.epub")
    private let b = URL(fileURLWithPath: "/Books/b.EPUB")
    private let c = URL(fileURLWithPath: "/Volumes/Gone/c.epub")
    private let d = URL(fileURLWithPath: "/Books/d.epub")

    @Test func recentsKeepOrderSkipMissingAndRespectTheLimit() {
        let exists: (URL) -> Bool = { $0 != c }
        let all = RecentBooks.list([a, b, c, d], limit: 10, fileExists: exists)
        #expect(all.map(\.url) == [a, b, d])
        #expect(RecentBooks.list([a, b, c, d], limit: 2, fileExists: exists).map(\.url) == [a, b])
        #expect(RecentBooks.list([a, b], limit: 0, fileExists: exists).isEmpty, "Recent Items set to None")
    }

    @Test func recentsDropDuplicatesAndNonFileURLs() {
        let again = URL(fileURLWithPath: "/Books/./d.epub")
        let web = URL(string: "https://example.com/x.epub")!
        let list = RecentBooks.list([d, web, again, a], limit: 10) { _ in true }
        #expect(list.map(\.url) == [d, a])
    }

    @Test func titlesDropOnlyTheEPUBExtension() {
        #expect(RecentBooks.title(of: a) == "Una descrizione di Terramare")
        #expect(RecentBooks.title(of: b) == "b")
        #expect(RecentBooks.title(of: URL(fileURLWithPath: "/x/notes.v2.zip")) == "notes.v2.zip")
        #expect(RecentBooks.title(of: URL(fileURLWithPath: "/x/.epub")) == ".epub")
    }

    @Test func artIsRecolouredAndHighlighted() {
        let template = ##"<svg color="#43B59E"><rect fill-opacity="0.04" stroke="currentColor" stroke-width="1.5" stroke-dasharray="5 6" stroke-linecap="round" opacity="0.6"/></svg>"##
        let dark = EmptyStateArt.svg(template, color: EmptyStateArt.darkTint, highlighted: false)
        #expect(dark.contains(##"color="#5FD4BC""##) && !dark.contains("#43B59E"))
        #expect(dark.contains(#"stroke-dasharray="5 6""#))
        let lit = EmptyStateArt.svg(template, color: EmptyStateArt.lightTint, highlighted: true)
        #expect(lit.contains(#"fill-opacity="0.12""#) && lit.contains(#"stroke-width="2.25""#) && lit.contains(#"opacity="1""#))
        #expect(!lit.contains("stroke-dasharray"))
    }

    @Test func graphesArtMatchesTheHighlightPatterns() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/EmptyState/aomidori-empty.svg")
        let template = try String(contentsOf: url, encoding: .utf8)
        let lit = EmptyStateArt.svg(template, color: "#000000", highlighted: true)
        #expect(lit.contains(##"color="#000000""##))
        #expect(lit.contains(#"stroke-width="2.25""#) && lit.contains(#"fill-opacity="0.12""#) && !lit.contains("stroke-dasharray"))
    }
}
