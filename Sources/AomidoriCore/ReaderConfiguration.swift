import Foundation

/// Everything the page-side script needs to present a document. Sent to the web view as JSON,
/// both at document start and whenever a setting changes (no reload needed).
///
/// The same layer is meant to drive the CSS Playground preview.
public struct ReaderConfiguration: Codable, Equatable, Sendable {
    /// When `true` the document's own style sheets and inline styles are disabled and the
    /// user style applies; when `false` only the book's CSS applies.
    public var overrideEnabled: Bool
    /// URL of the user style sheet, relative to the document's origin. `nil` if there is none.
    public var styleHref: String?
    /// Whether the user style handles `prefers-color-scheme` itself.
    public var styleHandlesColorScheme: Bool
    /// Night appearance requested.
    public var night: Bool
    /// Color-only rules applied in Night when the active CSS has no color-scheme rules.
    public var nightPaletteCSS: String
    /// Text size multiplier; 1 = the active CSS's own size. Applied as CSS `zoom` on the body,
    /// so it wins over any size the CSS sets (see `ReaderScript`).
    public var scale: Double
    /// `font-family` value of the app's custom font for all text, or `nil` when it is off.
    public var fontFamily: String?
    /// `@font-face` rules the custom font needs (see `CustomFontCSS`).
    public var fontFaceCSS: String
    /// Custom font: CSS weight of regular text, or `nil` to keep the CSS's weights.
    public var fontWeight: Double?
    /// Custom font: CSS weight of text the CSS makes bold (600 or more); see `CustomFontChoice`.
    public var fontBoldWeight: Double?
    /// Custom font: regular text in italic, italic text upright.
    public var fontItalic: Bool
    /// Custom font: `font-stretch` percentage, or `nil` to keep the CSS's.
    public var fontStretch: Double?
    /// Custom font: `font-feature-settings` and `font-variation-settings` values, empty for none.
    public var fontFeatureSettings: String
    public var fontVariationSettings: String
    /// Running text justified (`true`) or flush left (`false`, the default); either way it wins
    /// over the book's and the user style's alignment. Centred and right-aligned text is kept.
    public var justified: Bool

    public init(overrideEnabled: Bool = false, styleHref: String? = nil, styleHandlesColorScheme: Bool = false,
                night: Bool = false, nightPaletteCSS: String = "", scale: Double = 1,
                fontFamily: String? = nil, fontFaceCSS: String = "", fontWeight: Double? = nil,
                fontBoldWeight: Double? = nil, fontItalic: Bool = false, fontStretch: Double? = nil,
                fontFeatureSettings: String = "", fontVariationSettings: String = "", justified: Bool = false) {
        self.overrideEnabled = overrideEnabled
        self.styleHref = styleHref
        self.styleHandlesColorScheme = styleHandlesColorScheme
        self.night = night
        self.nightPaletteCSS = nightPaletteCSS
        self.scale = scale
        self.fontFamily = fontFamily
        self.fontFaceCSS = fontFaceCSS
        self.fontWeight = fontWeight
        self.fontBoldWeight = fontBoldWeight
        self.fontItalic = fontItalic
        self.fontStretch = fontStretch
        self.fontFeatureSettings = fontFeatureSettings
        self.fontVariationSettings = fontVariationSettings
        self.justified = justified
    }

    /// Turns the custom font on with a choice and its `@font-face` rules, or off with `nil`.
    public mutating func setCustomFont(_ choice: CustomFontChoice?, faceCSS: String) {
        fontFamily = choice.map { CustomFontCSS.familyList($0.family) }
        fontFaceCSS = choice == nil ? "" : faceCSS
        fontWeight = choice?.weight
        fontBoldWeight = choice?.boldWeight
        fontItalic = choice?.italic ?? false
        fontStretch = choice?.stretch
        fontFeatureSettings = choice?.featureSettingsCSS ?? ""
        fontVariationSettings = choice?.variationSettingsCSS ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case overrideEnabled, styleHref, styleHandlesColorScheme, night, nightPaletteCSS, scale, fontFamily, fontFaceCSS
        case fontWeight, fontBoldWeight, fontItalic, fontStretch, fontFeatureSettings, fontVariationSettings, justified
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            overrideEnabled: try container.decode(Bool.self, forKey: .overrideEnabled),
            styleHref: try container.decodeIfPresent(String.self, forKey: .styleHref),
            styleHandlesColorScheme: try container.decode(Bool.self, forKey: .styleHandlesColorScheme),
            night: try container.decode(Bool.self, forKey: .night),
            nightPaletteCSS: try container.decode(String.self, forKey: .nightPaletteCSS),
            scale: try container.decode(Double.self, forKey: .scale),
            fontFamily: try container.decodeIfPresent(String.self, forKey: .fontFamily),
            fontFaceCSS: try container.decode(String.self, forKey: .fontFaceCSS),
            fontWeight: try container.decodeIfPresent(Double.self, forKey: .fontWeight),
            fontBoldWeight: try container.decodeIfPresent(Double.self, forKey: .fontBoldWeight),
            fontItalic: try container.decodeIfPresent(Bool.self, forKey: .fontItalic) ?? false,
            fontStretch: try container.decodeIfPresent(Double.self, forKey: .fontStretch),
            fontFeatureSettings: try container.decodeIfPresent(String.self, forKey: .fontFeatureSettings) ?? "",
            fontVariationSettings: try container.decodeIfPresent(String.self, forKey: .fontVariationSettings) ?? "",
            justified: try container.decodeIfPresent(Bool.self, forKey: .justified) ?? false
        )
    }

    /// Absent values are written as `null`: the page merges each configuration into the previous
    /// one, so an omitted key would keep a stale value (a style or font that was turned off).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(overrideEnabled, forKey: .overrideEnabled)
        try container.encode(styleHref, forKey: .styleHref)
        try container.encode(styleHandlesColorScheme, forKey: .styleHandlesColorScheme)
        try container.encode(night, forKey: .night)
        try container.encode(nightPaletteCSS, forKey: .nightPaletteCSS)
        try container.encode(scale, forKey: .scale)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontFaceCSS, forKey: .fontFaceCSS)
        try container.encode(fontWeight, forKey: .fontWeight)
        try container.encode(fontBoldWeight, forKey: .fontBoldWeight)
        try container.encode(fontItalic, forKey: .fontItalic)
        try container.encode(fontStretch, forKey: .fontStretch)
        try container.encode(fontFeatureSettings, forKey: .fontFeatureSettings)
        try container.encode(fontVariationSettings, forKey: .fontVariationSettings)
        try container.encode(justified, forKey: .justified)
    }

    /// JSON text, which is also a valid JavaScript expression.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
