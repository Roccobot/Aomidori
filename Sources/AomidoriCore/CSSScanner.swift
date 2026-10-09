import Foundation

/// Lightweight, tolerant CSS text analysis. It is not a full CSS parser: it understands
/// comments, strings, blocks and at-rules well enough to answer the reader's questions
/// about a style sheet without a rendering engine.
public enum CSSScanner {
    /// The CSS with every comment removed. Strings are preserved, so `"/*"` inside a
    /// string or a `url("…")` is not mistaken for a comment.
    public static func strippingComments(_ css: String) -> String {
        var output = String.UnicodeScalarView()
        let scalars = Array(css.unicodeScalars)
        var index = 0
        var quote: Unicode.Scalar?
        while index < scalars.count {
            let scalar = scalars[index]
            if let open = quote {
                output.append(scalar)
                if scalar == "\\", index + 1 < scalars.count {
                    output.append(scalars[index + 1])
                    index += 2
                    continue
                }
                if scalar == open { quote = nil }
                index += 1
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
                output.append(scalar)
                index += 1
            } else if scalar == "/", index + 1 < scalars.count, scalars[index + 1] == "*" {
                index += 2
                while index < scalars.count, !(scalars[index] == "*" && index + 1 < scalars.count && scalars[index + 1] == "/") {
                    index += 1
                }
                index += 2
                output.append(" ")
            } else {
                output.append(scalar)
                index += 1
            }
        }
        return String(output)
    }

    /// Whether the style sheet itself contains a `prefers-color-scheme` media condition
    /// (in `@media`, `@import … (prefers-color-scheme: …)` or `@custom-media`). Comments do not count.
    public static func mentionsColorScheme(_ css: String) -> Bool {
        strippingComments(css).range(of: "prefers-color-scheme", options: .caseInsensitive) != nil
    }

    /// The targets of `@import` rules, in order: `@import url("a.css")`, `@import 'b.css' screen`.
    public static func importedURLs(_ css: String) -> [String] {
        let pattern = #"@import\s+(?:url\(\s*)?(?:"([^"]*)"|'([^']*)'|([^\s"')]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let text = strippingComments(css)
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            (1...3).lazy.compactMap { group -> String? in
                let range = match.range(at: group)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange])
            }.first
        }
    }

    /// A rule: its prelude (selector list or at-rule prelude) and the raw text of its block.
    public struct Rule: Equatable, Sendable {
        public let prelude: String
        public let block: String
    }

    /// Splits a sequence of rules into prelude/block pairs, honouring nested braces and strings.
    /// Statements without a block (`@import …;`, `@charset …;`) are skipped.
    public static func rules(in css: String) -> [Rule] {
        let scalars = Array(strippingComments(css).unicodeScalars)
        var rules: [Rule] = []
        var index = 0
        var preludeStart = 0
        var quote: Unicode.Scalar?
        while index < scalars.count {
            let scalar = scalars[index]
            if let open = quote {
                if scalar == "\\" { index += 1 } else if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == ";" {
                preludeStart = index + 1
            } else if scalar == "{" {
                let blockStart = index + 1
                let blockEnd = matchingBrace(in: scalars, openingAt: index)
                rules.append(Rule(
                    prelude: string(scalars[preludeStart..<index]).trimmingCharacters(in: .whitespacesAndNewlines),
                    block: string(scalars[blockStart..<min(blockEnd, scalars.count)])
                ))
                index = blockEnd
                preludeStart = index + 1
            }
            index += 1
        }
        return rules
    }

    /// `property: value` pairs of a declaration block (no nested rules expected).
    public static func declarations(in block: String) -> [(property: String, value: String)] {
        var result: [(String, String)] = []
        var current = String.UnicodeScalarView()
        var quote: Unicode.Scalar?
        var depth = 0
        func flush() {
            let declaration = String(current)
            current.removeAll()
            guard let colon = declaration.firstIndex(of: ":") else { return }
            let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !property.isEmpty, !value.isEmpty { result.append((property, value)) }
        }
        for scalar in block.unicodeScalars {
            if let open = quote {
                if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == "(" {
                depth += 1
            } else if scalar == ")" {
                depth = max(0, depth - 1)
            } else if scalar == ";", depth == 0 {
                flush()
                continue
            }
            current.append(scalar)
        }
        flush()
        return result
    }

    private static func matchingBrace(in scalars: [Unicode.Scalar], openingAt start: Int) -> Int {
        var depth = 0
        var quote: Unicode.Scalar?
        var index = start
        while index < scalars.count {
            let scalar = scalars[index]
            if let open = quote {
                if scalar == "\\" { index += 1 } else if scalar == open { quote = nil }
            } else if scalar == "\"" || scalar == "'" {
                quote = scalar
            } else if scalar == "{" {
                depth += 1
            } else if scalar == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return scalars.count
    }

    private static func string(_ slice: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: slice)
        return String(view)
    }
}
