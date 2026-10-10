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
        // A comic loses its extension too.
        #expect(RecentBooks.title(of: URL(fileURLWithPath: "/x/Pinocchio n. 1.CBZ")) == "Pinocchio n. 1")
        #expect(RecentBooks.title(of: URL(fileURLWithPath: "/x/Pinocchio n. 2.cbr")) == "Pinocchio n. 2")
    }

    @Test func formatsByExtension() {
        #expect(BookFormat(url: URL(fileURLWithPath: "/x/a.epub")) == .epub)
        #expect(BookFormat(url: URL(fileURLWithPath: "/x/a.CBZ")) == .cbz)
        #expect(BookFormat(url: URL(fileURLWithPath: "/x/a.cbr")) == .cbr)
        #expect(BookFormat(url: URL(fileURLWithPath: "/x/a.zip")) == nil)
        #expect(BookFormat.allCases.filter(\.isComic) == [.cbz, .cbr])
    }

    @Test func artIsRecoloured() {
        let template = ##"<svg color="#43B59E"><path stroke="currentColor"/></svg>"##
        let dark = EmptyStateArt.svg(template, color: EmptyStateArt.darkTint)
        #expect(dark.contains(##"color="#5FD4BC""##) && !dark.contains("#43B59E"))
    }

    @Test func graphesBookIsTheBookAloneInItsBox() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/EmptyState/aomidori-dropzone-book.svg")
        let template = try String(contentsOf: url, encoding: .utf8)
        // The app places the book by this box (`DropZoneView.bookSize`) and draws the frame itself.
        #expect(template.contains(#"viewBox="80 42 80 72""#))
        #expect(!template.contains("<rect") && !template.contains("stroke-dasharray"))
        #expect(EmptyStateArt.svg(template, color: "#000000").contains(##"color="#000000""##))
    }
}
