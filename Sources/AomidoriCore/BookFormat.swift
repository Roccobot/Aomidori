import Foundation

/// The kinds of file Aomidori opens, told apart by their extension.
/// Author: Rocco Casadei, a.k.a. Roccobot
public enum BookFormat: String, CaseIterable, Sendable {
    /// An EPUB book.
    case epub
    /// A comic book archive: a ZIP of pictures (CBZ).
    case comic = "cbz"

    public var fileExtension: String { rawValue }

    public init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }
}
