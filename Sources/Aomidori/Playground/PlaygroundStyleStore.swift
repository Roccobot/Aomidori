import Foundation
import EPUBKit

/// The Playground's unsaved CSS, served to its preview as if it were a file in the styles
/// folder (`/.aomidori/Styles/.playground-<id>.css`), so its relative URLs (`../Fonts/…`,
/// `@import "other.css"`) resolve exactly as they will once the style is saved there.
/// Nothing is written to disk. The leading dot keeps the name out of the way of real files,
/// which the style list never shows hidden.
final class PlaygroundStyleStore: @unchecked Sendable {
    static let shared = PlaygroundStyleStore()
    static let filePrefix = ".playground-"

    private let lock = NSLock()
    private var sheets: [String: Data] = [:]

    /// A new file name for one Playground window's buffer.
    func makeFileName() -> String {
        Self.filePrefix + UUID().uuidString.lowercased() + ".css"
    }

    func set(_ css: String, for fileName: String) {
        let data = Data(css.utf8)
        lock.withLock { sheets[fileName] = data }
    }

    func remove(_ fileName: String) {
        _ = lock.withLock { sheets.removeValue(forKey: fileName) }
    }

    func resource(for fileName: String) -> EPUBResource? {
        lock.withLock { sheets[fileName] }.map { EPUBResource(data: $0, mediaType: "text/css") }
    }
}
