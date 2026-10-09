import Foundation

/// One face of the app's custom font family, as the page will load it.
public struct FontFaceSource: Equatable, Sendable {
    /// PostScript name, tried first with `local()` (fonts installed in the system).
    public var postScriptName: String?
    /// Origin-relative URL of the font file served by the app, tried next (or only).
    public var url: String?
    /// CSS weight, 1...1000. Exact (Medium may be 500, Demi 590), so every face of a family
    /// keeps its own slot and the chosen face is matched exactly.
    public var weight: Double
    public var italic: Bool
    /// CSS `font-stretch` in percent; 100 is normal width, 75 condensed.
    public var stretch: Double
    /// For a variable font: the range of its `wght` axis, used instead of `weight`.
    public var weightRange: ClosedRange<Double>?
    /// For a variable font: the range of its `wdth` axis, used instead of `stretch`.
    public var stretchRange: ClosedRange<Double>?

    public init(postScriptName: String? = nil, url: String? = nil, weight: Double = 400, italic: Bool = false,
                stretch: Double = 100, weightRange: ClosedRange<Double>? = nil, stretchRange: ClosedRange<Double>? = nil) {
        self.postScriptName = postScriptName
        self.url = url
        self.weight = weight
        self.italic = italic
        self.stretch = stretch
        self.weightRange = weightRange
        self.stretchRange = stretchRange
    }
}

/// Everything the reader chose for the custom font: the family and, optionally, one face of
/// it, with its weight, width and style, variable-font axes and OpenType features. Comes from
/// the font chooser or the macOS Font panel; stored as JSON in the preferences.
public struct CustomFontChoice: Codable, Equatable, Sendable {
    public var family: String
    /// PostScript name of the chosen face, for display and to select it in the Font panel.
    public var faceName: String?
    /// CSS weight of regular text. Bold text gets `boldWeight`. `nil` keeps the weights the
    /// book or user style sets (the custom font then only changes the family).
    public var weight: Double?
    /// Regular text in italic; emphasis inside it then goes upright.
    public var italic: Bool
    /// CSS `font-stretch` in percent, or `nil` for the style's own (normally 100).
    public var stretch: Double?
    /// Variable-font axes other than weight and width, by four-letter tag (`opsz`, `GRAD`, …).
    public var variations: [String: Double]
    /// OpenType features by four-letter tag: 1 on (or an alternate's number), 0 off.
    public var features: [String: Int]

    public init(family: String, faceName: String? = nil, weight: Double? = nil, italic: Bool = false, stretch: Double? = nil,
                variations: [String: Double] = [:], features: [String: Int] = [:]) {
        self.family = family
        self.faceName = faceName.flatMap { $0.isEmpty ? nil : $0 }
        self.weight = weight.flatMap { $0.isFinite ? min(max($0, 1), 1000) : nil }
        self.italic = italic
        self.stretch = stretch.flatMap { $0.isFinite ? min(max($0, 25), 400) : nil }
        self.variations = variations.filter { Self.isTag($0.key) && $0.value.isFinite && !["wght", "wdth"].contains($0.key) }
        self.features = features.filter { Self.isTag($0.key) && $0.value >= 0 }
    }

    /// Bold text, relative to the chosen weight: 300 heavier, at most 900 (Light 300 → 600,
    /// Regular 400 → 700, Medium 500 → 800), and never lighter than the regular text.
    public var boldWeight: Double? {
        weight.map { max($0, min($0 + 300, 900)) }
    }

    /// `font-feature-settings` value, sorted by tag; empty for none.
    public var featureSettingsCSS: String {
        features.sorted { $0.key < $1.key }.map { "\(CustomFontCSS.quoted($0.key)) \($0.value)" }.joined(separator: ", ")
    }

    /// `font-variation-settings` value, sorted by tag; empty for none. Weight and width are not
    /// in it: they go through `font-weight` and `font-stretch`, so bold still works.
    public var variationSettingsCSS: String {
        variations.sorted { $0.key < $1.key }.map { "\(CustomFontCSS.quoted($0.key)) \(CustomFontCSS.number($0.value))" }
            .joined(separator: ", ")
    }

    /// A four-character OpenType tag of printable ASCII.
    public static func isTag(_ tag: String) -> Bool {
        tag.unicodeScalars.count == 4 && tag.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E && $0 != "\"" && $0 != "\\" }
    }

    // Unknown keys from newer versions are ignored; missing ones take their defaults.
    private enum CodingKeys: String, CodingKey { case family, faceName, weight, italic, stretch, variations, features }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            family: try container.decode(String.self, forKey: .family),
            faceName: try container.decodeIfPresent(String.self, forKey: .faceName),
            weight: try container.decodeIfPresent(Double.self, forKey: .weight),
            italic: try container.decodeIfPresent(Bool.self, forKey: .italic) ?? false,
            stretch: try container.decodeIfPresent(Double.self, forKey: .stretch),
            variations: (try? container.decodeIfPresent([String: Double].self, forKey: .variations)) ?? [:],
            features: (try? container.decodeIfPresent([String: Int].self, forKey: .features)) ?? [:]
        )
    }

    /// The stored choice: the JSON record if there is one, else the family name that versions
    /// before 0.4.0 stored alone (which only changed the family, as `weight == nil` does).
    public static func stored(record: Data?, legacyFamily: String?) -> CustomFontChoice? {
        if let record, let choice = try? JSONDecoder().decode(CustomFontChoice.self, from: record), !choice.family.isEmpty {
            return choice
        }
        guard let legacyFamily, !legacyFamily.isEmpty else { return nil }
        return CustomFontChoice(family: legacyFamily)
    }

    /// Variation values read from an AppKit font (the Font panel's, a face picked in the
    /// chooser), minus the axes that follow the text size: an optical size (`opsz`) recorded
    /// at the panel's point size would freeze it, while the page sets it from the rendered size
    /// by itself (`font-optical-sizing: auto`).
    public static func panelVariations(_ values: [String: Double]) -> [String: Double] {
        values.filter { !sizeDrivenAxes.contains($0.key) }
    }

    public static let sizeDrivenAxes: Set<String> = ["opsz"]

    public func record() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

/// CSS for the app's custom font.
///
/// The faces are declared under a private family name, so a book's own `@font-face` can never
/// take over the family the reader picked (a book may well declare a face called "Georgia").
/// The real family name follows in the list, as a fallback if no face can be loaded.
public enum CustomFontCSS {
    public static let alias = "aomidori-custom-font"

    /// `@font-face` rules for the alias; empty when there are no faces.
    public static func fontFaceCSS(_ faces: [FontFaceSource]) -> String {
        faces.compactMap { face -> String? in
            var sources: [String] = []
            if let name = face.postScriptName, !name.isEmpty { sources.append("local(\(quoted(name)))") }
            if let url = face.url, !url.isEmpty { sources.append("url(\(quoted(url)))") }
            guard !sources.isEmpty else { return nil }
            let weight = face.weightRange.map { "\(number($0.lowerBound)) \(number($0.upperBound))" } ?? number(face.weight)
            let stretch = face.stretchRange.map { "\(number($0.lowerBound))% \(number($0.upperBound))%" } ?? "\(number(face.stretch))%"
            return "@font-face { font-family: \(quoted(alias)); src: \(sources.joined(separator: ", ")); "
                + "font-weight: \(weight); font-style: \(face.italic ? "italic" : "normal"); font-stretch: \(stretch); font-display: block; }"
        }.joined(separator: "\n")
    }

    /// The `font-family` value applied to the text.
    public static func familyList(_ family: String) -> String {
        "\(quoted(alias)), \(quoted(family))"
    }

    private static let weightTable: [(trait: Double, css: Double)] = [
        (-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900),
    ]

    /// Maps a Core Text weight trait (-1...1, as `NSFont.Weight`) to the nearest CSS hundred.
    public static func cssWeight(fromTrait trait: Double) -> Int {
        Int(weightTable.min { abs($0.trait - trait) < abs($1.trait - trait) }!.css)
    }

    /// Maps a Core Text weight trait to a CSS weight, interpolating between the standard
    /// weights, so faces between two hundreds keep distinct weights.
    public static func exactWeight(fromTrait trait: Double) -> Double {
        interpolate(trait, in: weightTable).rounded()
    }

    private static let widthTable: [(trait: Double, css: Double)] = [
        (-0.5, 50), (-0.4, 62.5), (-0.2, 75), (-0.1, 87.5), (0, 100), (0.1, 112.5), (0.2, 125), (0.4, 150), (0.8, 200),
    ]

    /// Maps a Core Text width trait (-1...1) to a CSS `font-stretch` percentage.
    public static func stretch(fromWidthTrait trait: Double) -> Double {
        (interpolate(trait, in: widthTable) * 10).rounded() / 10
    }

    /// The CSS width of a named instance whose font has a width axis off the CSS percent scale
    /// (older Apple fonts such as Skia: `wdth` 0.62–1.3, 1 being normal). Core Text's width
    /// trait is unreliable for those (Skia's Extended reads as narrow as Condensed). A ratio
    /// scale (within 0.25–4) is read as a fraction of normal width, between 50% and 200%;
    /// anything else as normal width.
    public static func stretch(fromWidthAxisValue value: Double, range: ClosedRange<Double>) -> Double {
        guard value.isFinite, range.lowerBound >= 0.25, range.upperBound <= 4 else { return 100 }
        return (min(max(value * 100, 50), 200) * 10).rounded() / 10
    }

    /// Whether a width axis range is on the percent scale that `font-stretch` drives. Not only
    /// 50–200%: the system font's axis runs 30–150.
    public static func isCSSWidthAxis(_ range: ClosedRange<Double>) -> Bool {
        range.lowerBound >= 10 && range.upperBound <= 1000
    }

    private static func interpolate(_ value: Double, in table: [(trait: Double, css: Double)]) -> Double {
        guard value.isFinite else { return 400 }
        if value <= table[0].trait { return table[0].css }
        for (low, high) in zip(table, table.dropFirst()) where value <= high.trait {
            return low.css + (value - low.trait) / (high.trait - low.trait) * (high.css - low.css)
        }
        return table[table.count - 1].css
    }

    /// A CSS number: no exponent, no trailing zeros.
    public static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e9 { return String(Int(value)) }
        return String(format: "%.3f", value).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    /// A CSS string literal.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }
}

/// Apple's font-feature selectors (what the Font panel's Typography pane sets) as OpenType
/// feature tags, which CSS understands. Covers the features fonts commonly offer; others are
/// reported as unknown.
public enum OpenTypeFeatures {
    /// The OpenType tag and value for an AAT feature type and selector, or `nil` if unknown.
    public static func tag(type: Int, selector: Int) -> (tag: String, value: Int)? {
        switch (type, selector) {
        // Ligatures
        case (1, 2): ("liga", 1)
        case (1, 3): ("liga", 0)
        case (1, 4): ("dlig", 1)
        case (1, 5): ("dlig", 0)
        case (1, 18): ("clig", 1)
        case (1, 19): ("clig", 0)
        case (1, 20): ("hlig", 1)
        case (1, 21): ("hlig", 0)
        // Letter case (deprecated type): small caps
        case (3, 3): ("smcp", 1)
        // Number spacing
        case (6, 0): ("tnum", 1)
        case (6, 1): ("pnum", 1)
        // Vertical position
        case (10, 1): ("sups", 1)
        case (10, 2): ("subs", 1)
        case (10, 3): ("ordn", 1)
        case (10, 4): ("sinf", 1)
        // Fractions
        case (11, 1): ("afrc", 1)
        case (11, 2): ("frac", 1)
        // Typographic extras: slashed zero
        case (14, 4): ("zero", 1)
        case (14, 5): ("zero", 0)
        // Ornament sets
        case (16, 1): ("ornm", 1)
        // Character alternatives: the n-th alternate
        case (17, let n) where n > 0: ("salt", n)
        // Number case
        case (21, 0): ("onum", 1)
        case (21, 1): ("lnum", 1)
        // Case-sensitive layout
        case (33, 0): ("case", 1)
        case (33, 1): ("case", 0)
        // Stylistic sets: selector 2n turns set n on, 2n + 1 off
        case (35, let s) where (2...41).contains(s):
            (String(format: "ss%02d", s / 2), s % 2 == 0 ? 1 : 0)
        // Contextual alternates and swashes
        case (36, 0): ("calt", 1)
        case (36, 1): ("calt", 0)
        case (36, 2): ("swsh", 1)
        case (36, 3): ("swsh", 0)
        case (36, 4): ("cswh", 1)
        case (36, 5): ("cswh", 0)
        // Lower and upper case: small and petite capitals
        case (37, 1): ("smcp", 1)
        case (37, 2): ("pcap", 1)
        case (38, 1): ("c2sc", 1)
        case (38, 2): ("c2pc", 1)
        default: nil
        }
    }
}
