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

    override func makeWindowControllers() {
        guard let publication else { return }
        addWindowController(ReaderWindowController(publication: publication, bookKey: bookKey(for: publication.book)))
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
        case .unreadableArchive: reason = "Il file non \u{00E8} un EPUB valido: l'archivio ZIP non si pu\u{00F2} leggere."
        case .missingContainer: reason = "Manca META-INF/container.xml: il file non sembra un EPUB."
        case .missingPackage(let path): reason = "Manca il documento del pacchetto '\(path)'."
        case .malformedXML(let path): reason = "Il file '\(path)' contiene XML non valido."
        case .missingResource(let path): reason = "Manca il file '\(path)'."
        case .emptySpine: reason = "Il libro non contiene capitoli leggibili."
        case .drmProtected: reason = "Il libro \u{00E8} protetto da DRM e Aomidori non pu\u{00F2} aprirlo."
        }
        return NSError(domain: "Aomidori", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Impossibile aprire il libro.",
            NSLocalizedRecoverySuggestionErrorKey: reason,
        ])
    }
}
