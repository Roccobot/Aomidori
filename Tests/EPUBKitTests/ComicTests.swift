import Foundation
import Testing
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import EPUBKit

@Suite("Comics (CBZ)")
struct ComicTests {
    static let pixel = Data([0x89, 0x50, 0x4E, 0x47])

    /// Pages are the archive's pictures in the Finder's order (`2` before `10`), folders
    /// included; macOS's resource forks, hidden files and anything else are left out.
    @Test func pagesInNaturalOrder() {
        let paths = ["Vol 1/page10.jpg", "Vol 1/page2.jpg", "Vol 1/page1.JPG", "__MACOSX/Vol 1/._page1.jpg",
                     ".DS_Store", "Vol 1/.hidden.png", "ComicInfo.xml", "Vol 1/notes.txt", "Vol 2/a.webp", "cover.avif"]
        #expect(ComicArchive.pages(in: paths) == ["cover.avif", "Vol 1/page1.JPG", "Vol 1/page2.jpg", "Vol 1/page10.jpg", "Vol 2/a.webp"])
    }

    @Test func aComicIsOneScrollingDocument() throws {
        var fixture = EPUBFixture(files: [])
        fixture.add("002.png", Self.pixel)
        fixture.add("001 #1.png", Self.pixel)
        fixture.add("ComicInfo.xml", "<ComicInfo><Series>Prova</Series><Number>3</Number></ComicInfo>")
        let url = try fixture.write(extension: "cbz")
        defer { try? FileManager.default.removeItem(at: url) }

        let publication = try EPUBPublication(comicAt: url)
        let book = publication.book
        #expect(book.title == "Prova 3")
        #expect(book.spine.map(\.path) == [ComicArchive.documentPath])
        #expect(book.toc.map(\.title) == ["1", "2"])
        #expect(book.toc.map(\.fragment) == ["p1", "p2"])

        let page = try publication.resource(at: ComicArchive.documentPath)
        #expect(page.mediaType == "application/xhtml+xml")
        let document = try XMLParsing.document(from: page.data, path: "page")
        let sources = (document.rootElement()?.descendants(named: "img") ?? []).compactMap { $0.attributeValue("src") }
        #expect(sources == ["001%20%231.png", "002.png"])
        #expect(try publication.resource(at: "002.png").mediaType == "image/png")
    }

    @Test func titleFromComicInfoOrNone() throws {
        #expect(ComicArchive.title(fromComicInfo: Data("<ComicInfo><Title>Il titolo</Title><Series>S</Series></ComicInfo>".utf8)) == "Il titolo")
        #expect(ComicArchive.title(fromComicInfo: Data("<ComicInfo/>".utf8)) == nil)
        #expect(ComicArchive.title(fromComicInfo: Data("not xml".utf8)) == nil)
    }

    @Test func anArchiveWithoutPicturesIsRefused() throws {
        var fixture = EPUBFixture(files: [])
        fixture.add("readme.txt", "niente")
        let url = try fixture.write(extension: "cbz")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: EPUBError.emptySpine) { try EPUBPublication(comicAt: url) }
    }
}
