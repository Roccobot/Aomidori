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

    public init(overrideEnabled: Bool = false, styleHref: String? = nil, styleHandlesColorScheme: Bool = false,
                night: Bool = false, nightPaletteCSS: String = "", scale: Double = 1,
                fontFamily: String? = nil, fontFaceCSS: String = "") {
        self.overrideEnabled = overrideEnabled
        self.styleHref = styleHref
        self.styleHandlesColorScheme = styleHandlesColorScheme
        self.night = night
        self.nightPaletteCSS = nightPaletteCSS
        self.scale = scale
        self.fontFamily = fontFamily
        self.fontFaceCSS = fontFaceCSS
    }

    private enum CodingKeys: String, CodingKey {
        case overrideEnabled, styleHref, styleHandlesColorScheme, night, nightPaletteCSS, scale, fontFamily, fontFaceCSS
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
    }

    /// JSON text, which is also a valid JavaScript expression.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
