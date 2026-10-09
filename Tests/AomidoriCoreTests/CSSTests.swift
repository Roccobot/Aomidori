import Foundation
import Testing
@testable import AomidoriCore

/// Rocco's default style, as shipped with the app.
let readingRoccobotURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/ReadingRoccobot.css")

@Suite("CSS analysis")
struct CSSTests {
    @Test func commentsAreStrippedButStringsKept() {
        let css = #"a { content: "/* not a comment */"; } /* comment */ b { x: url('a/*b.png') }"#
        let stripped = CSSScanner.strippingComments(css)
        #expect(stripped.contains("\"/* not a comment */\""))
        #expect(stripped.contains("url('a/*b.png')"))
        #expect(!stripped.contains("comment */ b"))
    }

    @Test func colorSchemeDetection() throws {
        let rocco = try String(contentsOf: readingRoccobotURL, encoding: .utf8)
        #expect(CSSScanner.mentionsColorScheme(rocco))
        #expect(CSSScanner.mentionsColorScheme("@media screen and (PREFERS-COLOR-SCHEME:light) { a { color: red } }"))
        #expect(!CSSScanner.mentionsColorScheme("/* supports prefers-color-scheme */ body { color: #111 }"))
        #expect(!CSSScanner.mentionsColorScheme("p { margin: 0 }"))
    }

    @Test func importsAreListed() {
        let css = #"@import url("base.css"); @import 'night.css' screen; @import url(plain.css); /* @import "no.css"; */"#
        #expect(CSSScanner.importedURLs(css) == ["base.css", "night.css", "plain.css"])
    }

    @Test func rulesAndDeclarations() {
        let rules = CSSScanner.rules(in: "@charset 'utf-8'; a { b: c; } @media x { d { e: f } }")
        #expect(rules.map(\.prelude) == ["a", "@media x"])
        let declarations = CSSScanner.declarations(in: " color: red ; background: url(a;b.png) ; ;x")
        #expect(declarations.map(\.property) == ["color", "background"])
        #expect(declarations.last?.value == "url(a;b.png)")
    }

    @Test func nightPaletteFromReadingRoccobot() throws {
        let rocco = try String(contentsOf: readingRoccobotURL, encoding: .utf8)
        let palette = NightPalette.css(fromDarkRulesOf: rocco)
        let lines = palette.split(separator: "\n").map(String.init)

        #expect(lines.first == ":root { color-scheme: dark; }")
        #expect(lines.contains("html, body { background-color: #403d3a !important; color: #f5f5f2 !important; }"))
        #expect(lines.contains("h1, h2, h3, .title, .aut, .aut-sub, .titoletto { color: #c8c2bc !important; }"))
        #expect(lines.contains("h1 { border-bottom-color: #50545b !important; }"))
        #expect(lines.contains("hr { border-top-color: #50545b !important; }"))
        #expect(lines.contains("a:link, a:visited, a:active { color: #b6d9f4 !important; text-decoration-color: #91b4cd !important; }"))
        #expect(lines.contains("blockquote { color: #e2e5e8 !important; border-left-color: #bba081 !important; }"))
        #expect(lines.contains("::selection { background-color: #27685B !important; color: #f5f5f2 !important; }"))
        // Never fonts, sizes or spacing; and nothing from the light rules.
        #expect(!palette.contains("font"))
        #expect(!palette.contains("margin"))
        #expect(!palette.contains("#FCFAF6"))
        #expect(lines.contains("a:hover, a:focus { color: #e0f1ff !important; }"))
        #expect(lines.count == 9)
    }

    @Test func nightPaletteIsEmptyWithoutDarkRules() {
        #expect(NightPalette.css(fromDarkRulesOf: "@media (prefers-color-scheme: light) { a { color: red } } p { color: blue }").isEmpty)
    }
}
