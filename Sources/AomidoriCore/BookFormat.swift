import Foundation

/// The kinds of file Aomidori opens, told apart by their extension.
/// Author: Rocco Casadei, a.k.a. Roccobot
public enum BookFormat: String, CaseIterable, Sendable {
    /// An EPUB book.
    case epub
    /// A comic book archive: a ZIP of pictures.
    case cbz
    /// A comic book archive: a RAR of pictures (or a ZIP or 7z under that name).
    case cbr

    public var fileExtension: String { rawValue }

    /// A comic archive: its pictures make one scrolling page.
    public var isComic: Bool { self != .epub }

    public init?(url: URL) {
        self.init(rawValue: url.pathExtension.lowercased())
    }
}
