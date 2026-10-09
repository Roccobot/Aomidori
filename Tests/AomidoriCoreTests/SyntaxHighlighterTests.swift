import Testing
@testable import AomidoriCore

@Suite("Syntax highlighter")
struct SyntaxHighlighterTests {
    /// The tokens as (kind, text) pairs, easier to read in expectations.
    func spans(_ text: String, _ language: SyntaxLanguage = .css) -> [(SyntaxTokenKind, String)] {
        let units = Array(text.utf16)
        return SyntaxHighlighter.tokens(in: units, language: language).map {
            ($0.kind, String(decoding: units[$0.range], as: UTF16.self))
        }
    }

    func expect(_ text: String, _ language: SyntaxLanguage = .css, _ expected: [(SyntaxTokenKind, String)],
                sourceLocation: SourceLocation = #_sourceLocation) {
        let actual = spans(text, language)
        #expect(actual.map(\.0) == expected.map(\.0), sourceLocation: sourceLocation)
        #expect(actual.map(\.1) == expected.map(\.1), sourceLocation: sourceLocation)
    }

    @Test func cssRule() {
        expect("h1.no, p + p { margin: 1em 0 0 0; color: #7c7773 !important; }", .css, [
            (.selector, "h1.no, p + p"),
            (.property, "margin"), (.number, "1em"), (.number, "0"), (.number, "0"), (.number, "0"),
            (.property, "color"), (.color, "#7c7773"), (.important, "!important"),
        ])
    }

    @Test func cssValuesFunctionsAndStrings() {
        expect("body { font: 400 min(1.6em, 26px)/1.75 \"MiSans\", sans-serif; width: -.5%; }", .css, [
            (.selector, "body"),
            (.property, "font"), (.number, "400"), (.keyword, "min"), (.number, "1.6em"), (.number, "26px"),
            (.number, "1.75"), (.string, "\"MiSans\""), (.keyword, "sans-serif"),
            (.property, "width"), (.number, "-.5%"),
        ])
    }

    @Test func atRulesAndNesting() {
        let css = """
        @font-face { font-family: "X"; src: url(../Fonts/X.otf); }
        @media (prefers-color-scheme: dark) {
          html, body { color: #f5f5f2; }
        }
        a { color: red; &:hover { color: blue; } }
        """
        expect(css, .css, [
            (.atRule, "@font-face"), (.property, "font-family"), (.string, "\"X\""),
            (.property, "src"), (.keyword, "url"), (.string, "../Fonts/X.otf"),
            (.atRule, "@media"), (.keyword, "prefers-color-scheme"), (.keyword, "dark"),
            (.selector, "html, body"), (.property, "color"), (.color, "#f5f5f2"),
            (.selector, "a"), (.property, "color"), (.keyword, "red"),
            (.selector, "&:hover"), (.property, "color"), (.keyword, "blue"),
        ])
    }

    @Test func commentsAndUnterminatedText() {
        expect("/* a { b: c } */ p { /* x */ color: red }", .css, [
            (.comment, "/* a { b: c } */"), (.selector, "p"), (.comment, "/* x */"), (.property, "color"), (.keyword, "red"),
        ])
        // An unfinished comment or string runs to the end and never traps the scanner.
        expect("p { content: \"abc", .css, [(.selector, "p"), (.property, "content"), (.string, "\"abc")])
        expect("p { } /* open", .css, [(.selector, "p"), (.comment, "/* open")])
        expect("@import \"a.css\";", .css, [(.atRule, "@import"), (.string, "\"a.css\"")])
    }

    @Test func selectorsWithAttributeStrings() {
        expect("a[href^=\"http\"] > b::before {}", .css, [
            (.selector, "a[href^="), (.string, "\"http\""), (.selector, "] > b::before"),
        ])
    }

    @Test func nonASCIIOffsetsAreUTF16() {
        // "è" is one UTF-16 unit, "𝄞" two: ranges must stay aligned with NSString.
        let tokens = SyntaxHighlighter.tokens(in: "/* è𝄞 */ p { }", language: .css)
        #expect(tokens.first == SyntaxToken(.comment, 0..<9))
        #expect(tokens.last == SyntaxToken(.selector, 10..<11))
    }

    @Test func html() {
        let html = """
        <!DOCTYPE html><p class="center" id=x>Caf&eacute; <!-- nota --></p><style>p { color: red }</style><script>let a = 'b';</script>
        """
        expect(html, .html, [
            (.atRule, "<!DOCTYPE html>"),
            (.tag, "<p"), (.attribute, "class"), (.string, "\"center\""), (.attribute, "id"), (.string, "x"), (.tag, ">"),
            (.entity, "&eacute;"), (.comment, "<!-- nota -->"), (.tag, "</p"), (.tag, ">"),
            (.tag, "<style"), (.tag, ">"), (.selector, "p"), (.property, "color"), (.keyword, "red"), (.tag, "</style"), (.tag, ">"),
            (.tag, "<script"), (.tag, ">"), (.keyword, "let"), (.string, "'b'"), (.tag, "</script"), (.tag, ">"),
        ])
    }

    @Test func javaScript() {
        expect("const x = `a\nb`; // fine\nif (y-1 > 2.5) { return null }", .javascript, [
            (.keyword, "const"), (.string, "`a\nb`"), (.comment, "// fine"),
            (.keyword, "if"), (.number, "1"), (.number, "2.5"), (.keyword, "return"), (.keyword, "null"),
        ])
    }

    @Test func detectsLanguage() {
        #expect(SyntaxLanguage.detect(text: "<html>", fileExtension: "css") == .css)
        #expect(SyntaxLanguage.detect(text: "p {}", fileExtension: "html") == .html)
        #expect(SyntaxLanguage.detect(text: "  \n<!DOCTYPE html>") == .html)
        #expect(SyntaxLanguage.detect(text: "const a = 1") == .javascript)
        #expect(SyntaxLanguage.detect(text: "/* style */ p { margin: 0 }") == .css)
        #expect(SyntaxLanguage.detect(text: "") == .css)
    }

    // MARK: Incremental restyling

    func restyle(_ before: String, _ after: String, location: Int, oldLength: Int, newLength: Int) -> Range<Int> {
        SyntaxHighlighter.restyleRange(
            old: SyntaxHighlighter.tokens(in: before, language: .css),
            new: SyntaxHighlighter.tokens(in: after, language: .css),
            location: location, oldLength: oldLength, newLength: newLength)
    }

    @Test func typingInsideAValueRestylesOnlyThatToken() {
        let before = "a { color: red; }\nb { margin: 1em; }\nc { padding: 0; }"
        let after = "a { color: red; }\nb { margin: 12em; }\nc { padding: 0; }"
        // "2" inserted after the "1" of "1em" (which starts at offset 30).
        let range = restyle(before, after, location: 31, oldLength: 0, newLength: 1)
        #expect(range == 30..<34)
    }

    @Test func openingACommentRestylesToTheEnd() {
        let before = "a { color: red; }\nb { margin: 1em; }"
        let after = "/*a { color: red; }\nb { margin: 1em; }"
        let range = restyle(before, after, location: 0, oldLength: 0, newLength: 2)
        #expect(range == 0..<after.utf16.count)
    }

    @Test func deletionShiftsTheFollowingTokens() {
        let before = "a { color: red; }\nb { margin: 1em; }"
        let after = "a { color: ; }\nb { margin: 1em; }"
        // "red" (offset 11, 3 units) deleted: nothing after it needs new colours.
        let range = restyle(before, after, location: 11, oldLength: 3, newLength: 0)
        #expect(range == 11..<11)
    }
}
