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
    /// Text size multiplier on the root font size; 1 = the style's own size.
    public var scale: Double

    public init(overrideEnabled: Bool = false, styleHref: String? = nil, styleHandlesColorScheme: Bool = false,
                night: Bool = false, nightPaletteCSS: String = "", scale: Double = 1) {
        self.overrideEnabled = overrideEnabled
        self.styleHref = styleHref
        self.styleHandlesColorScheme = styleHandlesColorScheme
        self.night = night
        self.nightPaletteCSS = nightPaletteCSS
        self.scale = scale
    }

    /// JSON text, which is also a valid JavaScript expression.
    public func json() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
