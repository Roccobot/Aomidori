import Foundation
import ZIPFoundation
@testable import EPUBKit

/// Builds small EPUB files on disk for tests.
struct EPUBFixture {
    var files: [(path: String, data: Data)] = [("mimetype", Data("application/epub+zip".utf8))]

    mutating func add(_ path: String, _ text: String) {
        files.append((path, Data(text.utf8)))
    }

    mutating func add(_ path: String, _ data: Data) {
        files.append((path, data))
    }

    mutating func addContainer(packagePath: String = "OEBPS/content.opf") {
        add("META-INF/container.xml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="\(packagePath)" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """)
    }

    /// Writes the archive to a fresh temporary file and returns its URL.
    func write() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("aomidori-test-\(UUID().uuidString).epub")
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
                                 compressionMethod: path == "mimetype" ? .none : .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        return url
    }

    static func chapter(_ title: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>\(title)</title></head>
        <body><h1 id="top">\(title)</h1><p>Testo.</p></body></html>
        """
    }

    /// An EPUB 3 book with a navigation document, a non-linear item and a percent-encoded href.
    static func epub3() -> EPUBFixture {
        var fixture = EPUBFixture()
        fixture.addContainer()
        fixture.add("OEBPS/content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="isbn">urn:isbn:9780000000000</dc:identifier>
            <dc:identifier id="pub-id">urn:uuid:12345678-90ab-cdef-1234-567890abcdef</dc:identifier>
            <dc:title>  Una   prova </dc:title>
            <dc:language>it</dc:language>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            <item id="c1" href="Text/Capitolo%201.xhtml" media-type="application/xhtml+xml"/>
            <item id="notes" href="Text/notes.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="Text/c2.xhtml" media-type="application/xhtml+xml"/>
            <item id="css" href="Styles/book.css" media-type="text/css"/>
            <item id="font" href="Fonts/Serif.otf" media-type="application/vnd.ms-opentype"/>
            <item id="cover" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
            <itemref idref="notes" linear="no"/>
            <itemref idref="c2"/>
            <itemref idref="missing"/>
          </spine>
        </package>
        """)
        fixture.add("OEBPS/nav.xhtml", """
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><title>Indice</title></head><body>
          <nav epub:type="landmarks"><ol><li><a href="Text/c2.xhtml">Landmark</a></li></ol></nav>
          <nav epub:type="toc"><ol>
            <li><a href="Text/Capitolo%201.xhtml">Capitolo&nbsp;uno</a>
              <ol><li><a href="Text/Capitolo%201.xhtml#sez-2">Sezione
                due</a></li></ol></li>
            <li><span>Parte seconda</span>
              <ol><li><a href="Text/c2.xhtml">Capitolo due</a></li></ol></li>
          </ol></nav>
        </body></html>
        """)
        fixture.add("OEBPS/Text/Capitolo 1.xhtml", chapter("Uno"))
        fixture.add("OEBPS/Text/notes.xhtml", chapter("Note"))
        fixture.add("OEBPS/Text/c2.xhtml", chapter("Due"))
        fixture.add("OEBPS/Styles/book.css", "p { margin: 0 }")
        fixture.add("OEBPS/Fonts/Serif.otf", Data((0..<2048).map { UInt8($0 % 251) }))
        fixture.add("OEBPS/Images/cover.jpg", Data([0xFF, 0xD8, 0xFF]))
        return fixture
    }

    /// An EPUB 2 book whose TOC lives in an NCX file.
    static func epub2() -> EPUBFixture {
        var fixture = EPUBFixture()
        fixture.addContainer(packagePath: "content.opf")
        fixture.add("content.opf", """
        <?xml version="1.0" encoding="UTF-8"?>
        <opf:package xmlns:opf="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="BookId">
          <opf:metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="BookId">book-2</dc:identifier><dc:title>Due</dc:title>
          </opf:metadata>
          <opf:manifest>
            <opf:item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <opf:item id="a" href="text/a.html" media-type="application/xhtml+xml"/>
            <opf:item id="b" href="text/b.html" media-type="application/xhtml+xml"/>
          </opf:manifest>
          <opf:spine toc="ncx"><opf:itemref idref="a"/><opf:itemref idref="b"/></opf:spine>
        </opf:package>
        """)
        fixture.add("toc.ncx", """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><navMap>
          <navPoint id="p1" playOrder="1"><navLabel><text>Primo</text></navLabel><content src="text/a.html"/>
            <navPoint id="p2" playOrder="2"><navLabel><text>Primo, parte 2</text></navLabel><content src="text/a.html#p2"/></navPoint>
          </navPoint>
          <navPoint id="p3" playOrder="3"><navLabel><text>Secondo</text></navLabel><content src="text/b.html"/></navPoint>
        </navMap></ncx>
        """)
        fixture.add("text/a.html", chapter("A"))
        fixture.add("text/B.html", chapter("B"))
        return fixture
    }
}
