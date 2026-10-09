import Foundation

/// The name a book goes by in window titles.
public enum BookTitle {
    /// The book's `dc:title`, or else the EPUB file's name without its extension; `nil` when
    /// neither says anything.
    public static func display(title: String?, fileURL: URL?) -> String? {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        guard let fileURL else { return nil }
        let name = fileURL.deletingPathExtension().lastPathComponent
        return name.isEmpty ? nil : name
    }
}
