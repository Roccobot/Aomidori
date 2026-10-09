import Foundation

/// The languages the CSS Playground editor colours.
public enum SyntaxLanguage: Sendable, Equatable {
    case css, html, javascript

    /// The language of a file: by extension when it is a known one, otherwise by content.
    /// Markup starts with `<`; script is recognised by its usual opening words; anything else
    /// is treated as CSS, the Playground's main language.
    public static func detect(text: String, fileExtension: String? = nil) -> SyntaxLanguage {
        switch fileExtension?.lowercased() {
        case "css": return .css
        case "html", "htm", "xhtml", "xml", "svg": return .html
        case "js", "mjs": return .javascript
        default: break
        }
        guard let first = text.unicodeScalars.firstIndex(where: { !CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            return .css
        }
        let head = text.unicodeScalars[first...].prefix(64)
        if head.first == "<" { return .html }
        let opening = String(String.UnicodeScalarView(head))
        let scriptOpenings = ["function", "const ", "let ", "var ", "import ", "export ", "'use strict'", "\"use strict\"", "(()", "(function", "//"]
        if scriptOpenings.contains(where: opening.hasPrefix) { return .javascript }
        return .css
    }
}

/// What a highlighted span of source is.
public enum SyntaxTokenKind: Sendable, Equatable {
    case comment
    case string
    case number
    /// A hex colour (`#1F8E78`).
    case color
    /// `@media`, `@font-face`; `<!DOCTYPE …>` and `<?xml …?>` in markup.
    case atRule
    case selector
    case property
    /// A CSS value keyword or function name (`solid`, `min(`); a script keyword.
    case keyword
    /// `!important`
    case important
    /// A markup tag name with its angle brackets.
    case tag
    /// A markup attribute name.
    case attribute
    /// A character reference (`&amp;`).
    case entity
}

/// A highlighted span, in UTF-16 offsets (the units of `NSString` and `NSRange`).
public struct SyntaxToken: Sendable, Equatable {
    public var kind: SyntaxTokenKind
    public var range: Range<Int>

    public init(_ kind: SyntaxTokenKind, _ range: Range<Int>) {
        self.kind = kind
        self.range = range
    }
}

/// A small, tolerant tokenizer for colouring source text: CSS (including nested rules and
/// at-rules), HTML (with `<style>` and `<script>` content coloured as CSS and script) and
/// basic JavaScript. It never fails: unterminated comments and strings run to the end.
///
/// The whole text is tokenized at every edit (a few milliseconds for thousands of lines), and
/// `restyleRange` tells which part of the text actually needs new attributes, so only that
/// part is re-coloured. Tokenizing everything keeps multi-line comments and strings right
/// without tracking state per line.
public enum SyntaxHighlighter {
    public static func tokens(in text: String, language: SyntaxLanguage) -> [SyntaxToken] {
        tokens(in: Array(text.utf16), language: language)
    }

    public static func tokens(in text: [UInt16], language: SyntaxLanguage) -> [SyntaxToken] {
        var scanner = Scanner(text: text)
        switch language {
        case .css: scanner.scanCSS(until: text.count)
        case .html: scanner.scanHTML()
        case .javascript: scanner.scanJavaScript(until: text.count)
        }
        return scanner.tokens
    }

    /// The part of the new text whose colouring may differ after an edit that replaced
    /// `oldLength` units at `location` with `newLength` units: the edited text itself plus every
    /// token that is not identical (same kind, same place after shifting) before and after.
    public static func restyleRange(old: [SyntaxToken], new: [SyntaxToken],
                                    location: Int, oldLength: Int, newLength: Int) -> Range<Int> {
        let delta = newLength - oldLength
        let oldEditEnd = location + oldLength
        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix], old[prefix].range.upperBound <= location {
            prefix += 1
        }
        var oldEnd = old.count
        var newEnd = new.count
        while oldEnd > prefix, newEnd > prefix {
            let candidate = old[oldEnd - 1]
            guard candidate.range.lowerBound >= oldEditEnd else { break }
            let shifted = SyntaxToken(candidate.kind, (candidate.range.lowerBound + delta)..<(candidate.range.upperBound + delta))
            guard shifted == new[newEnd - 1] else { break }
            oldEnd -= 1
            newEnd -= 1
        }
        // Where a position of the old text is in the new one.
        func mapped(_ position: Int) -> Int {
            if position <= location { return position }
            if position >= oldEditEnd { return position + delta }
            return location + newLength
        }
        var lower = location
        var upper = location + newLength
        if prefix < oldEnd {
            lower = min(lower, mapped(old[prefix].range.lowerBound))
            upper = max(upper, mapped(old[oldEnd - 1].range.upperBound))
        }
        if prefix < newEnd {
            lower = min(lower, new[prefix].range.lowerBound)
            upper = max(upper, new[newEnd - 1].range.upperBound)
        }
        return max(0, lower)..<max(max(0, lower), upper)
    }
}

// MARK: - Scanner

private struct Scanner {
    let text: [UInt16]
    var index = 0
    var tokens: [SyntaxToken] = []

    init(text: [UInt16]) {
        self.text = text
    }

    // MARK: Characters

    static func unit(_ character: Character) -> UInt16 { character.utf16.first! }
    static let slash = unit("/"), star = unit("*"), backslash = unit("\\"), quote = unit("\""), apostrophe = unit("'")
    static let backtick = unit("`"), openBrace = unit("{"), closeBrace = unit("}"), semicolon = unit(";")
    static let colon = unit(":"), openParen = unit("("), closeParen = unit(")"), hash = unit("#"), at = unit("@")
    static let bang = unit("!"), less = unit("<"), greater = unit(">"), equals = unit("="), ampersand = unit("&")
    static let minus = unit("-"), plus = unit("+"), dot = unit("."), newline = unit("\n"), carriageReturn = unit("\r")
    static let question = unit("?"), percent = unit("%"), underscore = unit("_"), comma = unit(",")

    func at(_ position: Int) -> UInt16? { position < text.count ? text[position] : nil }

    static func isWhitespace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0C }
    static func isDigit(_ unit: UInt16) -> Bool { unit >= 0x30 && unit <= 0x39 }
    static func isLetter(_ unit: UInt16) -> Bool { (unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x7A }
    static func isHex(_ unit: UInt16) -> Bool { isDigit(unit) || ((unit | 0x20) >= 0x61 && (unit | 0x20) <= 0x66) }
    /// CSS identifier characters (non-ASCII counts as a name character).
    static func isNameUnit(_ unit: UInt16) -> Bool { isLetter(unit) || isDigit(unit) || unit == minus || unit == underscore || unit >= 0x80 }
    /// Script identifier characters (`$` included, `-` excluded).
    static func isScriptName(_ unit: UInt16) -> Bool { isLetter(unit) || isDigit(unit) || unit == underscore || unit == 0x24 || unit >= 0x80 }

    mutating func add(_ kind: SyntaxTokenKind, _ start: Int, _ end: Int) {
        guard end > start else { return }
        tokens.append(SyntaxToken(kind, start..<end))
    }

    func matches(_ literal: String, at position: Int, caseInsensitive: Bool = false) -> Bool {
        var cursor = position
        for unit in literal.utf16 {
            guard let current = at(cursor) else { return false }
            if caseInsensitive ? (current | 0x20) != (unit | 0x20) : current != unit { return false }
            cursor += 1
        }
        return true
    }

    /// Skips a `/* … */` comment at `index`, recording it. Returns `false` if there is none.
    mutating func blockComment(until limit: Int) -> Bool {
        guard index + 1 < limit, text[index] == Self.slash, text[index + 1] == Self.star else { return false }
        let start = index
        index += 2
        while index < limit, !(text[index] == Self.star && index + 1 < limit && text[index + 1] == Self.slash) { index += 1 }
        index = min(limit, index + 2)
        add(.comment, start, index)
        return true
    }

    /// Skips a quoted string at `index`, recording it. CSS and script strings end at an
    /// unescaped line break; template literals (`multiline`) do not.
    mutating func quoted(until limit: Int, multiline: Bool = false) {
        let start = index
        let delimiter = text[index]
        index += 1
        while index < limit {
            let unit = text[index]
            if unit == Self.backslash { index += 2; continue }
            if unit == delimiter { index += 1; break }
            if !multiline, unit == Self.newline { break }
            index += 1
        }
        index = min(index, limit)
        add(.string, start, index)
    }

    mutating func skipWhitespaceAndComments(until limit: Int) {
        while index < limit {
            if Self.isWhitespace(text[index]) { index += 1 } else if !blockComment(until: limit) { return }
        }
    }

    // MARK: CSS

    enum Block { case rules, declarations }

    mutating func scanCSS(until limit: Int) {
        var blocks: [Block] = []
        while index < limit {
            skipWhitespaceAndComments(until: limit)
            guard index < limit else { return }
            let unit = text[index]
            if unit == Self.closeBrace {
                index += 1
                if !blocks.isEmpty { blocks.removeLast() }
                continue
            }
            if unit == Self.semicolon { index += 1; continue }
            if unit == Self.at {
                blocks.append(contentsOf: cssAtRule(until: limit))
                continue
            }
            if blocks.last == .declarations, !statementOpensBlock(until: limit) {
                cssDeclaration(until: limit)
            } else {
                cssSelector(until: limit)
                if index < limit, text[index] == Self.openBrace {
                    index += 1
                    blocks.append(.declarations)
                }
            }
        }
    }

    /// Whether the statement at `index` is a nested rule (`&:hover { … }`) rather than a
    /// declaration: a `{` comes before any `;` or `}`.
    func statementOpensBlock(until limit: Int) -> Bool {
        var cursor = index
        var parens = 0
        while cursor < limit {
            let unit = text[cursor]
            if unit == Self.quote || unit == Self.apostrophe {
                cursor += 1
                while cursor < limit, text[cursor] != unit, text[cursor] != Self.newline {
                    cursor += text[cursor] == Self.backslash ? 2 : 1
                }
            } else if unit == Self.slash, cursor + 1 < limit, text[cursor + 1] == Self.star {
                cursor += 2
                while cursor + 1 < limit, !(text[cursor] == Self.star && text[cursor + 1] == Self.slash) { cursor += 1 }
                cursor += 1
            } else if unit == Self.openParen {
                parens += 1
            } else if unit == Self.closeParen {
                parens -= 1
            } else if parens <= 0 {
                if unit == Self.openBrace { return true }
                if unit == Self.semicolon || unit == Self.closeBrace { return false }
            }
            cursor += 1
        }
        return false
    }

    /// A selector list up to `{` (left at `index`), `;` or `}`.
    mutating func cssSelector(until limit: Int) {
        var runStart: Int?
        var lastSignificant = index
        func flush(_ scanner: inout Scanner) {
            if let start = runStart { scanner.add(.selector, start, lastSignificant) }
            runStart = nil
        }
        while index < limit {
            let unit = text[index]
            if unit == Self.openBrace || unit == Self.semicolon || unit == Self.closeBrace { break }
            if unit == Self.slash, index + 1 < limit, text[index + 1] == Self.star {
                flush(&self)
                _ = blockComment(until: limit)
                continue
            }
            if unit == Self.quote || unit == Self.apostrophe {
                // Attribute selector values: [lang="it"].
                flush(&self)
                quoted(until: limit)
                continue
            }
            if !Self.isWhitespace(unit) {
                if runStart == nil { runStart = index }
                lastSignificant = index + 1
            }
            index += 1
        }
        flush(&self)
    }

    /// An at-rule's name and prelude. Returns the block it opens, if any.
    mutating func cssAtRule(until limit: Int) -> [Block] {
        let start = index
        index += 1
        while index < limit, Self.isNameUnit(text[index]) { index += 1 }
        add(.atRule, start, index)
        let name = String(decoding: text[(start + 1)..<index], as: UTF16.self).lowercased()
        cssValue(until: limit, stopAtBrace: true)
        guard index < limit else { return [] }
        if text[index] == Self.openBrace {
            index += 1
            let declarationBlocks: Set<String> = ["font-face", "page", "property", "counter-style", "font-palette-values", "viewport", "-ms-viewport"]
            return [declarationBlocks.contains(name) ? .declarations : .rules]
        }
        if text[index] == Self.semicolon { index += 1 }
        return []
    }

    /// `property: value;` inside a declaration block.
    mutating func cssDeclaration(until limit: Int) {
        let start = index
        while index < limit, text[index] != Self.colon, text[index] != Self.semicolon,
              text[index] != Self.closeBrace, !Self.isWhitespace(text[index]) {
            if text[index] == Self.slash, index + 1 < limit, text[index + 1] == Self.star { break }
            index += 1
        }
        add(.property, start, index)
        skipWhitespaceAndComments(until: limit)
        guard index < limit, text[index] == Self.colon else {
            // Not a declaration (a typo or a stray word): skip to the end of the statement.
            while index < limit, text[index] != Self.semicolon, text[index] != Self.closeBrace { index += 1 }
            return
        }
        index += 1
        cssValue(until: limit, stopAtBrace: false)
        if index < limit, text[index] == Self.semicolon { index += 1 }
    }

    /// Values: strings, numbers with units, colours, functions, keywords and `!important`.
    /// Stops at `;` or `}` (left at `index`), or at `{` for at-rule preludes.
    mutating func cssValue(until limit: Int, stopAtBrace: Bool) {
        var parens = 0
        while index < limit {
            let unit = text[index]
            if unit == Self.semicolon || unit == Self.closeBrace { if parens <= 0 { return } }
            if unit == Self.openBrace, stopAtBrace { return }
            if blockComment(until: limit) { continue }
            if unit == Self.quote || unit == Self.apostrophe { quoted(until: limit); continue }
            if unit == Self.openParen { parens += 1; index += 1; continue }
            if unit == Self.closeParen { parens -= 1; index += 1; continue }
            if unit == Self.hash, let next = at(index + 1), Self.isHex(next) {
                let start = index
                index += 1
                while index < limit, Self.isNameUnit(text[index]) { index += 1 }
                add(.color, start, index)
                continue
            }
            if unit == Self.bang {
                let start = index
                index += 1
                while index < limit, Self.isWhitespace(text[index]) { index += 1 }
                if matches("important", at: index, caseInsensitive: true) {
                    index += 9
                    add(.important, start, index)
                }
                continue
            }
            if startsNumber(at: index) {
                let start = index
                if text[index] == Self.minus || text[index] == Self.plus { index += 1 }
                while index < limit, Self.isDigit(text[index]) || text[index] == Self.dot { index += 1 }
                if index < limit, text[index] == Self.percent {
                    index += 1
                } else {
                    while index < limit, Self.isLetter(text[index]) { index += 1 }
                }
                add(.number, start, index)
                continue
            }
            if Self.isLetter(unit) || unit == Self.minus || unit == Self.underscore || unit >= 0x80 {
                let start = index
                while index < limit, Self.isNameUnit(text[index]) { index += 1 }
                let isURL = index < limit && text[index] == Self.openParen
                    && String(decoding: text[start..<index], as: UTF16.self).lowercased() == "url"
                add(.keyword, start, index)
                if isURL { cssUnquotedURL(until: limit) }
                continue
            }
            index += 1
        }
    }

    /// `url(…)` with an unquoted address, coloured as a string.
    mutating func cssUnquotedURL(until limit: Int) {
        var cursor = index + 1
        while cursor < limit, Self.isWhitespace(text[cursor]) { cursor += 1 }
        guard cursor < limit, text[cursor] != Self.quote, text[cursor] != Self.apostrophe else { return }
        let start = cursor
        while cursor < limit, text[cursor] != Self.closeParen, text[cursor] != Self.newline { cursor += 1 }
        add(.string, start, cursor)
        index = cursor
    }

    func startsNumber(at position: Int) -> Bool {
        guard let unit = at(position) else { return false }
        if Self.isDigit(unit) { return true }
        if unit == Self.dot, let next = at(position + 1) { return Self.isDigit(next) }
        if unit == Self.minus || unit == Self.plus, let next = at(position + 1) {
            return Self.isDigit(next) || (next == Self.dot && at(position + 2).map(Self.isDigit) == true)
        }
        return false
    }

    // MARK: HTML

    mutating func scanHTML() {
        let limit = text.count
        while index < limit {
            let unit = text[index]
            if unit == Self.less {
                if matches("<!--", at: index) {
                    let start = index
                    index += 4
                    while index < limit, !matches("-->", at: index) { index += 1 }
                    index = min(limit, index + 3)
                    add(.comment, start, index)
                } else if matches("<!", at: index) || matches("<?", at: index) {
                    let start = index
                    while index < limit, text[index] != Self.greater { index += 1 }
                    index = min(limit, index + 1)
                    add(.atRule, start, index)
                } else if let next = at(index + 1), Self.isLetter(next) || next == Self.slash {
                    if let name = htmlTag(until: limit), ["style", "script"].contains(name) {
                        embedded(name)
                    }
                } else {
                    index += 1
                }
            } else if unit == Self.ampersand {
                let start = index
                var cursor = index + 1
                while cursor < limit, cursor - start < 32, Self.isNameUnit(text[cursor]) || text[cursor] == Self.hash { cursor += 1 }
                if cursor < limit, text[cursor] == Self.semicolon, cursor > start + 1 {
                    index = cursor + 1
                    add(.entity, start, index)
                } else {
                    index += 1
                }
            } else {
                index += 1
            }
        }
    }

    /// A start or end tag at `index`. Returns the lowercased name of a start tag.
    mutating func htmlTag(until limit: Int) -> String? {
        let start = index
        index += 1
        let isEnd = text[index] == Self.slash
        if isEnd { index += 1 }
        let nameStart = index
        while index < limit, !Self.isWhitespace(text[index]), text[index] != Self.greater, text[index] != Self.slash { index += 1 }
        let name = String(decoding: text[nameStart..<index], as: UTF16.self).lowercased()
        add(.tag, start, index)
        while index < limit {
            let unit = text[index]
            if unit == Self.greater {
                add(.tag, index, index + 1)
                index += 1
                break
            }
            if unit == Self.slash, at(index + 1) == Self.greater {
                add(.tag, index, index + 2)
                index += 2
                break
            }
            if unit == Self.quote || unit == Self.apostrophe {
                quoted(until: limit, multiline: true)
                continue
            }
            if unit == Self.equals {
                index += 1
                while index < limit, Self.isWhitespace(text[index]) { index += 1 }
                if index < limit, text[index] != Self.quote, text[index] != Self.apostrophe, text[index] != Self.greater {
                    let valueStart = index
                    while index < limit, !Self.isWhitespace(text[index]), text[index] != Self.greater { index += 1 }
                    add(.string, valueStart, index)
                }
                continue
            }
            if Self.isWhitespace(unit) { index += 1; continue }
            let attributeStart = index
            while index < limit, !Self.isWhitespace(text[index]), text[index] != Self.equals,
                  text[index] != Self.greater, text[index] != Self.slash {
                index += 1
            }
            if index == attributeStart { index += 1 } else { add(.attribute, attributeStart, index) }
        }
        return isEnd ? nil : name
    }

    /// The content of `<style>` or `<script>`, up to its end tag.
    mutating func embedded(_ name: String) {
        var end = index
        while end < text.count, !matches("</\(name)", at: end, caseInsensitive: true) { end += 1 }
        if name == "style" { scanCSS(until: end) } else { scanJavaScript(until: end) }
        index = end
    }

    // MARK: JavaScript

    static let scriptKeywords: Set<String> = [
        "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
        "do", "else", "export", "extends", "false", "finally", "for", "from", "function", "if", "import", "in",
        "instanceof", "let", "new", "null", "of", "return", "static", "super", "switch", "this", "throw", "true",
        "try", "typeof", "undefined", "var", "void", "while", "with", "yield",
    ]

    mutating func scanJavaScript(until limit: Int) {
        while index < limit {
            let unit = text[index]
            if unit == Self.slash, let next = at(index + 1), next == Self.slash {
                let start = index
                while index < limit, text[index] != Self.newline { index += 1 }
                add(.comment, start, index)
            } else if blockComment(until: limit) {
                continue
            } else if unit == Self.quote || unit == Self.apostrophe {
                quoted(until: limit)
            } else if unit == Self.backtick {
                quoted(until: limit, multiline: true)
            } else if Self.isDigit(unit) || (unit == Self.dot && at(index + 1).map(Self.isDigit) == true) {
                let start = index
                while index < limit, Self.isNameUnit(text[index]) || text[index] == Self.dot { index += 1 }
                add(.number, start, index)
            } else if Self.isScriptName(unit), !Self.isDigit(unit) {
                let start = index
                while index < limit, Self.isScriptName(text[index]) { index += 1 }
                if Self.scriptKeywords.contains(String(decoding: text[start..<index], as: UTF16.self)) {
                    add(.keyword, start, index)
                }
            } else {
                index += 1
            }
        }
    }
}
