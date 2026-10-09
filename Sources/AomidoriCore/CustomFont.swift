import Foundation

/// One face of the app's custom font family, as the page will load it.
public struct FontFaceSource: Equatable, Sendable {
    /// PostScript name, tried first with `local()` (fonts installed in the system).
    public var postScriptName: String?
    /// Origin-relative URL of the font file served by the app, tried next (or only).
    public var url: String?
    /// CSS weight, 100...900.
    public var weight: Int
    public var italic: Bool

    public init(postScriptName: String? = nil, url: String? = nil, weight: Int = 400, italic: Bool = false) {
        self.postScriptName = postScriptName
        self.url = url
        self.weight = weight
        self.italic = italic
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
            return "@font-face { font-family: \(quoted(alias)); src: \(sources.joined(separator: ", ")); "
                + "font-weight: \(face.weight); font-style: \(face.italic ? "italic" : "normal"); font-display: block; }"
        }.joined(separator: "\n")
    }

    /// The `font-family` value applied to the text.
    public static func familyList(_ family: String) -> String {
        "\(quoted(alias)), \(quoted(family))"
    }

    /// Maps a Core Text weight trait (-1...1, as `NSFont.Weight`) to the nearest CSS weight.
    public static func cssWeight(fromTrait trait: Double) -> Int {
        let table: [(Double, Int)] = [
            (-0.8, 100), (-0.6, 200), (-0.4, 300), (0, 400), (0.23, 500), (0.3, 600), (0.4, 700), (0.56, 800), (0.62, 900),
        ]
        return table.min { abs($0.0 - trait) < abs($1.0 - trait) }!.1
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
