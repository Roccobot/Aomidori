import Foundation
import Testing
@testable import AomidoriCore

@Suite("Playground saving")
struct PlaygroundSaveTests {
    @Test func encoderWritesUTF8WithoutBOMWithLFAndFinalNewline() {
        #expect(CSSFile.data(for: "\u{FEFF}p {\r\n  color: red;\r}") == Data("p {\n  color: red;\n}\n".utf8))
        #expect(CSSFile.data(for: "p {}\n") == Data("p {}\n".utf8))
        #expect(CSSFile.data(for: "") == Data())
        // Non-ASCII stays UTF-8, and no @charset is added.
        let data = CSSFile.data(for: "p::before { content: \"è — ’\" }")
        #expect(data == Data("p::before { content: \"è — ’\" }\n".utf8))
        #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(!String(decoding: data, as: UTF8.self).contains("@charset"))
        #expect(!data.contains(0x0D))
    }

    @Test func readerDropsBOMAndFallsBackToLatin1() {
        #expect(CSSFile.text(from: Data([0xEF, 0xBB, 0xBF]) + Data("p{}".utf8)) == "p{}")
        #expect(CSSFile.text(from: Data([0x63, 0x61, 0x66, 0xE8])) == "cafè")
    }

    @Test func fileNames() {
        #expect(StyleLibrary.fileName(for: "Prova/1") == "Prova-1.css")
        #expect(StyleLibrary.fileName(for: " Mio stile.CSS ") == "Mio stile.css")
        #expect(StyleLibrary.fileName(for: ".nascosto") == "nascosto.css")
        #expect(StyleLibrary.fileName(for: ".css") == "Style.css")
        #expect(StyleLibrary.fileName(for: "") == "Style.css")
    }

    @Test func collisionsAreDetectedWithoutCase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-save-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = StyleLibrary(directory: directory)
        try library.prepare(installing: nil, as: "none.css")
        try Data("p {}".utf8).write(to: directory.appendingPathComponent("Notte.css"))

        let fresh = library.savePlan(forName: "Giorno")
        #expect(fresh.fileName == "Giorno.css")
        #expect(!fresh.replacesExisting)

        let clash = library.savePlan(forName: "notte")
        #expect(clash.replacesExisting)
        #expect(clash.fileName == "Notte.css") // the existing file keeps its name

        #expect(library.availableName(for: "Notte") == "Notte 2.css")
        try Data("p {}".utf8).write(to: directory.appendingPathComponent("Notte 2.css"))
        #expect(library.availableName(for: "Notte.css") == "Notte 3.css")
        #expect(library.availableName(for: "Alba") == "Alba.css")

        // Saving refuses to replace unless asked, then replaces the existing file.
        #expect(throws: CocoaError.self) { try library.save(css: "a {}", named: "NOTTE") }
        let saved = try library.save(css: "a {}", named: "NOTTE", overwrite: true)
        #expect(saved.name == "Notte.css")
        #expect(try String(contentsOf: saved.url, encoding: .utf8) == "a {}\n")
        #expect(library.styles().map(\.name) == ["Notte 2.css", "Notte.css"])
    }

    @Test func unsavedCSSColorSchemeFollowsImports() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-scheme-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = StyleLibrary(directory: directory)
        try library.prepare(installing: nil, as: "none.css")
        try Data("@media (prefers-color-scheme: dark) { p { color: white } }".utf8)
            .write(to: directory.appendingPathComponent("dark.css"))
        #expect(library.handlesColorScheme(css: "@import 'dark.css'; p { margin: 0 }"))
        #expect(library.handlesColorScheme(css: "@media (prefers-color-scheme: light) {}"))
        #expect(!library.handlesColorScheme(css: "@import 'missing.css'; p { margin: 0 }"))
    }
}
