import Foundation
import Testing
@testable import EPUBKit

@Suite("EPUB parsing")
struct EPUBParserTests {
    @Test func epub3MetadataSpineAndManifest() throws {
        let url = try EPUBFixture.epub3().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try EPUBPublication(contentsOf: url).book

        #expect(book.identifier == "urn:uuid:12345678-90ab-cdef-1234-567890abcdef")
        #expect(book.title == "Una prova")
        #expect(book.language == "it")
        #expect(book.packagePath == "OEBPS/content.opf")
        // The itemref pointing at a missing manifest item is dropped.
        #expect(book.spine.map(\.path) == ["OEBPS/Text/Capitolo 1.xhtml", "OEBPS/Text/notes.xhtml", "OEBPS/Text/c2.xhtml"])
        #expect(book.spine.map(\.isLinear) == [true, false, true])
        #expect(book.spineIndex(forPath: "OEBPS/Text/c2.xhtml") == 2)
        #expect(book.manifestItem(forPath: "OEBPS/Images/cover.jpg")?.properties == ["cover-image"])
    }

    @Test func descriptiveMetadataAndCover() throws {
        let url = try EPUBFixture.epub3().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try EPUBPublication(contentsOf: url).book

        #expect(book.metadata.title == "Una prova")
        #expect(book.metadata.creators == ["Ursula K. Le Guin", "Seconda Autrice"])
        #expect(book.metadata.publisher == "Editore")
        #expect(book.metadata.modified == "2026-09-30T13:14:58Z")
        #expect(book.metadata.identifier == "urn:uuid:12345678-90ab-cdef-1234-567890abcdef")
        #expect(book.metadata.rights == nil)
        #expect(book.coverPath == "OEBPS/Images/cover.jpg")

        let epub2URL = try EPUBFixture.epub2().write()
        defer { try? FileManager.default.removeItem(at: epub2URL) }
        // EPUB 2: <meta name="cover" content="…"> names the manifest item.
        #expect(try EPUBPublication(contentsOf: epub2URL).book.coverPath == "images/c.png")
    }

    @Test func tableOfContentsPageInTheSpine() {
        func book(manifest: [(String, String, Set<String>)], spine: [(String, String)]) -> EPUBBook {
            EPUBBook(identifier: "x", title: nil, language: nil, packagePath: "OEBPS/content.opf",
                     manifest: manifest.map { ManifestItem(id: $0.0, path: $0.1, mediaType: "application/xhtml+xml", properties: $0.2) },
                     spine: spine.map { SpineItem(idref: $0.0, path: $0.1, mediaType: "application/xhtml+xml", isLinear: true) },
                     toc: [])
        }
        let nav = book(manifest: [("cover", "OEBPS/cover.xhtml", []), ("n", "OEBPS/nav.xhtml", ["nav"]), ("c1", "OEBPS/c1.xhtml", [])],
                       spine: [("cover", "OEBPS/cover.xhtml"), ("n", "OEBPS/nav.xhtml"), ("c1", "OEBPS/c1.xhtml")])
        #expect(nav.tableOfContentsIndex == 1)
        let navOutsideSpine = book(manifest: [("n", "OEBPS/nav.xhtml", ["nav"]), ("c1", "OEBPS/c1.xhtml", []), ("i", "OEBPS/Text/Indice.html", [])],
                                   spine: [("c1", "OEBPS/c1.xhtml"), ("i", "OEBPS/Text/Indice.html")])
        #expect(navOutsideSpine.tableOfContentsIndex == 1, "an HTML contents page by name")
        let none = book(manifest: [("c1", "OEBPS/c1.xhtml", [])], spine: [("c1", "OEBPS/c1.xhtml")])
        #expect(none.tableOfContentsIndex == nil)
    }

    @Test func linearNavigationSkipsNonLinearItems() throws {
        let url = try EPUBFixture.epub3().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let book = try EPUBPublication(contentsOf: url).book

        #expect(book.firstReadableIndex == 0)
        #expect(book.nextReadableIndex(after: 0) == 2)
        #expect(book.nextReadableIndex(after: 1) == 2)
        #expect(book.nextReadableIndex(after: 2) == nil)
        #expect(book.previousReadableIndex(before: 2) == 0)
        #expect(book.previousReadableIndex(before: 1) == 0)
        #expect(book.previousReadableIndex(before: 0) == nil)
    }

    @Test func epub3NavigationDocument() throws {
        let url = try EPUBFixture.epub3().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let toc = try EPUBPublication(contentsOf: url).book.toc

        // The `toc` nav is chosen over `landmarks`; &nbsp; is understood; white space is collapsed.
        #expect(toc.count == 2)
        #expect(toc[0].title == "Capitolo uno")
        #expect(toc[0].path == "OEBPS/Text/Capitolo 1.xhtml")
        #expect(toc[0].fragment == nil)
        #expect(toc[0].children == [TOCEntry(title: "Sezione due", path: "OEBPS/Text/Capitolo 1.xhtml", fragment: "sez-2", children: [])])
        #expect(toc[1].title == "Parte seconda")
        #expect(toc[1].path == nil)
        #expect(toc[1].children.first?.path == "OEBPS/Text/c2.xhtml")
    }

    @Test func epub2NCXFallback() throws {
        let url = try EPUBFixture.epub2().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let publication = try EPUBPublication(contentsOf: url)
        let book = publication.book

        #expect(book.identifier == "book-2")
        #expect(book.toc.map(\.title) == ["Primo", "Secondo"])
        #expect(book.toc[0].children == [TOCEntry(title: "Primo, parte 2", path: "text/a.html", fragment: "p2", children: [])])
        #expect(book.tocTitle(forPath: "text/b.html") == "Secondo")
        // The archive stores "text/B.html": lookups fall back to a case-insensitive match.
        #expect(try publication.resource(at: "text/b.html").data.isEmpty == false)
    }

    @Test func resourceMediaTypes() throws {
        let url = try EPUBFixture.epub3().write()
        defer { try? FileManager.default.removeItem(at: url) }
        let publication = try EPUBPublication(contentsOf: url)

        #expect(try publication.resource(at: "OEBPS/Text/c2.xhtml").mediaType == "application/xhtml+xml")
        #expect(try publication.resource(at: "OEBPS/Styles/book.css").mediaType == "text/css")
        #expect(try publication.resource(at: "OEBPS/Fonts/Serif.otf").mediaType == "font/otf")
        #expect(try publication.resource(at: "OEBPS/Images/cover.jpg").mediaType == "image/jpeg")
        // Not in the manifest: inferred from the extension.
        #expect(try publication.resource(at: "mimetype").mediaType == "application/octet-stream")
        #expect(throws: EPUBError.missingResource(path: "OEBPS/nope.css")) {
            try publication.resource(at: "OEBPS/nope.css")
        }
    }

    @Test func missingContainerIsReported() throws {
        var fixture = EPUBFixture()
        fixture.add("OEBPS/content.opf", "<package/>")
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: EPUBError.missingContainer) { try EPUBPublication(contentsOf: url) }
    }

    @Test func notAZipIsReported() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-not-zip-\(UUID().uuidString).epub")
        try Data("not a zip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: EPUBError.unreadableArchive) { try EPUBPublication(contentsOf: url) }
    }

    @Test func encryptedContentIsReportedAsDRM() throws {
        var fixture = EPUBFixture.epub3()
        fixture.add("META-INF/encryption.xml", """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData><enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/Text/c2.xhtml"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """)
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: EPUBError.drmProtected) { try EPUBPublication(contentsOf: url) }
    }
}

@Suite("Resource paths")
struct ResourcePathTests {
    @Test func resolvesRelativeReferences() {
        #expect(ResourcePath.resolve("../Images/a%20b.png", relativeTo: "OEBPS/Text/c1.xhtml")! == ("OEBPS/Images/a b.png", nil))
        #expect(ResourcePath.resolve("c2.xhtml#n%C3%A81", relativeTo: "OEBPS/Text/c1.xhtml")! == ("OEBPS/Text/c2.xhtml", "nè1"))
        #expect(ResourcePath.resolve("#note", relativeTo: "OEBPS/c1.xhtml")! == ("OEBPS/c1.xhtml", "note"))
        #expect(ResourcePath.resolve("/OEBPS/x.css?v=1", relativeTo: "a/b.xhtml")! == ("OEBPS/x.css", nil))
        #expect(ResourcePath.resolve("../../../x.css", relativeTo: "a/b.xhtml")! == ("x.css", nil))
    }

    @Test func externalReferencesAreNotResolved() {
        #expect(ResourcePath.resolve("https://example.com/a", relativeTo: "a.xhtml") == nil)
        #expect(ResourcePath.resolve("mailto:a@b.c", relativeTo: "a.xhtml") == nil)
    }
}
