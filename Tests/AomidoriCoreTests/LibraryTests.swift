import Foundation
import Testing
@testable import AomidoriCore

@Suite("Style library")
struct StyleLibraryTests {
    func makeLibrary() throws -> StyleLibrary {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-styles-\(UUID().uuidString)")
        return StyleLibrary(directory: directory.appendingPathComponent("Styles"))
    }

    @Test func installsDefaultStyleOnceAndListsCSS() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory.deletingLastPathComponent()) }
        try library.prepare(installing: readingRoccobotURL, as: "ReadingRoccobot.css")
        try Data("p {}".utf8).write(to: library.directory.appendingPathComponent("b.css"))
        try Data("x".utf8).write(to: library.directory.appendingPathComponent("notes.txt"))
        try Data("p {}".utf8).write(to: library.directory.appendingPathComponent("A10.css"))
        try Data("p {}".utf8).write(to: library.directory.appendingPathComponent("A9.css"))

        #expect(library.styles().map(\.name) == ["A9.css", "A10.css", "b.css", "ReadingRoccobot.css"])
        #expect(library.styles().last?.displayName == "ReadingRoccobot")

        // A user edit is never overwritten by a later launch.
        let installed = library.directory.appendingPathComponent("ReadingRoccobot.css")
        try Data("/* mine */".utf8).write(to: installed)
        try library.prepare(installing: readingRoccobotURL, as: "ReadingRoccobot.css")
        #expect(try String(contentsOf: installed, encoding: .utf8) == "/* mine */")
    }

    @Test func savesPlaygroundCSS() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory.deletingLastPathComponent()) }
        let saved = try library.save(css: "\u{FEFF}p {\r\n  color: red;\r}", named: "Prova/1")
        #expect(saved.name == "Prova-1.css")
        #expect(try Data(contentsOf: saved.url) == Data("p {\n  color: red;\n}\n".utf8))
        #expect(library.styles().map(\.name) == ["Prova-1.css"])
        #expect(throws: CocoaError.self) { try library.save(css: "a {}", named: "Prova-1.css") }
        try library.save(css: "a {}", named: "Prova-1.css", overwrite: true)
        #expect(try String(contentsOf: saved.url, encoding: .utf8) == "a {}\n")
    }

    @Test func colorSchemeThroughImports() throws {
        let library = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: library.directory.deletingLastPathComponent()) }
        try library.prepare(installing: nil, as: "none.css")
        let write = { (name: String, css: String) in
            try Data(css.utf8).write(to: library.directory.appendingPathComponent(name))
        }
        try write("dark.css", "@media (prefers-color-scheme: dark) { body { color: white } }")
        try write("main.css", "@import url(\"dark.css\"); p { margin: 0 }")
        try write("plain.css", "@import 'plain.css'; p { color: black }")
        let styles = Dictionary(uniqueKeysWithValues: library.styles().map { ($0.name, $0) })

        #expect(library.handlesColorScheme(styles["main.css"]!))
        #expect(library.handlesColorScheme(styles["dark.css"]!))
        #expect(!library.handlesColorScheme(styles["plain.css"]!)) // self-import terminates
    }

    @Test func cyclingWrapsAround() {
        let styles = ["a.css", "b.css", "c.css"].map { StyleFile(name: $0, url: URL(fileURLWithPath: "/tmp/\($0)"), modificationDate: nil) }
        #expect(StyleCycle.style(from: "a.css", offset: 1, in: styles)?.name == "b.css")
        #expect(StyleCycle.style(from: "c.css", offset: 1, in: styles)?.name == "a.css")
        #expect(StyleCycle.style(from: "a.css", offset: -1, in: styles)?.name == "c.css")
        #expect(StyleCycle.style(from: "gone.css", offset: -1, in: styles)?.name == "c.css")
        #expect(StyleCycle.style(from: nil, offset: 1, in: styles)?.name == "a.css")
        #expect(StyleCycle.style(from: "a.css", offset: 1, in: []) == nil)
    }
}

@Suite("Reader settings")
struct ReaderSettingsTests {
    @Test func textScaleSteps() {
        #expect(TextScale.larger(than: 1) == 1.05)
        #expect(TextScale.smaller(than: 1) == 0.95)
        #expect(TextScale.larger(than: 3) == 3)
        #expect(TextScale.smaller(than: 0.5) == 0.5)
        #expect(TextScale.larger(than: 1.07) == 1.1)
        #expect(TextScale.sanitized(.nan) == 1)
        #expect(TextScale.sanitized(9) == 3)
    }

    @Test func positionsRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-positions-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = ReadingPositionStore(fileURL: url)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.setPosition(ReadingPosition(spinePath: "OEBPS/c2.xhtml", spineIndex: 2, fraction: 1.7, updated: date), forBook: "book")
        try store.save()

        let reloaded = ReadingPositionStore(fileURL: url)
        #expect(reloaded.position(forBook: "book") == ReadingPosition(
            spinePath: "OEBPS/c2.xhtml", spineIndex: 2, fraction: 1, updated: date,
            chapters: ["OEBPS/c2.xhtml": ChapterPosition(fraction: 1)]))
        #expect(reloaded.position(forBook: "other") == nil)
    }

    @Test func configurationJSON() throws {
        let configuration = ReaderConfiguration(overrideEnabled: true, styleHref: "/.aomidori/Styles/A%20B.css?v=1",
                                                night: true, nightPaletteCSS: "a { color: red !important; }", scale: 1.2)
        let decoded = try JSONDecoder().decode(ReaderConfiguration.self, from: Data(configuration.json().utf8))
        #expect(decoded == configuration)
    }

    /// Flush left by default; ⌘J switches to justified and back, and the page gets the choice.
    @Test func alignmentIsFlushLeftUnlessJustified() throws {
        #expect(ReaderConfiguration().justified == false)
        var justified = ReaderConfiguration()
        justified.justified = true
        #expect(justified.json().contains("\"justified\":true"))
        // A configuration written before 0.70 has no key: flush left.
        let old = #"{"overrideEnabled":false,"styleHandlesColorScheme":false,"night":false,"nightPaletteCSS":"","scale":1,"fontFaceCSS":""}"#
        #expect(try JSONDecoder().decode(ReaderConfiguration.self, from: Data(old.utf8)).justified == false)
    }
}
