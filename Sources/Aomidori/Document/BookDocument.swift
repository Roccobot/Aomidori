import AppKit
import EPUBKit

/// An open EPUB file. Read-only: the reader never writes to the book.
@objc(BookDocument)
final class BookDocument: NSDocument {
    private var publication: EPUBPublication?

    override class var autosavesInPlace: Bool { false }

    /// Opens the archive lazily: only its directory and the package and navigation documents are read.
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        let publication: EPUBPublication
        do {
            publication = try EPUBPublication(contentsOf: url)
        } catch let error as EPUBError {
            throw error.userFacingError
        }
        // Documents are read on the main thread (concurrent reading is not enabled).
        MainActor.assumeIsolated { self.publication = publication }
    }

    /// The book's reader window. If it was opened from an empty window (or one is in front),
    /// the book takes its place.
    override func makeWindowControllers() {
        guard let publication else { return }
        let empty = EmptyReaderWindowController.target()
        empty?.releaseFrameName()
        let controller = ReaderWindowController(publication: publication, bookKey: bookKey(for: publication.book))
        addWindowController(controller)
        empty?.handOver(to: controller)
    }

    /// Reading positions are keyed by the package identifier and title, so the same book is
    /// recognised even if the file moves; books without an identifier fall back to their path.
    private func bookKey(for book: EPUBBook) -> String {
        guard !book.identifier.isEmpty else { return fileURL?.standardizedFileURL.path ?? book.packagePath }
        return "\(book.identifier)|\(book.title ?? "")"
    }

    override func data(ofType typeName: String) throws -> Data {
        throw CocoaError(.featureUnsupported)
    }
}

extension EPUBError {
    /// An `NSError` whose texts the document architecture shows in its alert.
    var userFacingError: NSError {
        let reason: String
        switch self {
        case .unreadableArchive: reason = L10n.string("error.unreadableArchive")
        case .missingContainer: reason = L10n.string("error.missingContainer")
        case .missingPackage(let path): reason = L10n.format("error.missingPackage", path)
        case .malformedXML(let path): reason = L10n.format("error.malformedXML", path)
        case .missingResource(let path): reason = L10n.format("error.missingResource", path)
        case .oversizedResource(let path): reason = L10n.format("error.oversizedResource", path)
        case .emptySpine: reason = L10n.string("error.emptySpine")
        case .drmProtected: reason = L10n.string("error.drmProtected")
        }
        return NSError(domain: "Aomidori", code: 1, userInfo: [
            NSLocalizedDescriptionKey: L10n.string("error.open"),
            NSLocalizedRecoverySuggestionErrorKey: reason,
        ])
    }
}
