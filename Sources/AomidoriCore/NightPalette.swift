import Foundation

/// Derives the Night fallback palette from a style sheet's dark color-scheme rules.
///
/// When the active CSS has no `prefers-color-scheme` rules, Night mode injects only the
/// color declarations of the default style's `@media (prefers-color-scheme: dark)` blocks,
/// so that colors change while fonts, sizes and spacing stay those of the active CSS.
public enum NightPalette {
    /// Builds the palette CSS. Every declaration is marked `!important` so it applies over the
    /// active style regardless of source order. Returns an empty string if `css` has no dark rules.
    public static func css(fromDarkRulesOf css: String) -> String {
        var output: [String] = []
        for rule in CSSScanner.rules(in: css) where isDarkSchemeMedia(rule.prelude) {
            output.append(contentsOf: colorRules(in: rule.block))
        }
        guard !output.isEmpty else { return "" }
        // `color-scheme: dark` darkens what no author rule covers (canvas, scroll bars, form controls).
        return ([":root { color-scheme: dark; }"] + output).joined(separator: "\n")
    }

    /// Whether a declaration only affects color: `color`, `*-color`, `fill`, `stroke`.
    public static func isColorProperty(_ property: String) -> Bool {
        property == "color" || property == "fill" || property == "stroke" || property.hasSuffix("-color")
    }

    static func isDarkSchemeMedia(_ prelude: String) -> Bool {
        let compact = prelude.lowercased().filter { !$0.isWhitespace }
        return compact.hasPrefix("@media") && compact.contains("prefers-color-scheme:dark")
    }

    private static func colorRules(in block: String) -> [String] {
        CSSScanner.rules(in: block).compactMap { rule in
            // Nested at-rules (rare inside a color-scheme block) are not flattened.
            guard !rule.prelude.hasPrefix("@"), !rule.prelude.isEmpty else { return nil }
            let declarations = CSSScanner.declarations(in: rule.block)
                .filter { isColorProperty($0.property) }
                .map { "\($0.property): \(important($0.value));" }
            guard !declarations.isEmpty else { return nil }
            return "\(rule.prelude) { \(declarations.joined(separator: " ")) }"
        }
    }

    private static func important(_ value: String) -> String {
        value.range(of: #"!\s*important\s*$"#, options: [.regularExpression, .caseInsensitive]) == nil
            ? "\(value) !important" : value
    }
}
