import AomidoriCore
import AppKit
import EPUBKit

/// An open EPUB or comic (CBZ, CBR) file. Read-only: the reader never writes to the book.
@objc(BookDocument)
final class BookDocument: NSDocument {
    private var publication: EPUBPublication?

    override class var autosavesInPlace: Bool { false }

    /// Opens the archive lazily: only its directory and the package and navigation documents are read.
    override nonisolated func read(from url: URL, ofType typeName: String) throws {
        let publication: EPUBPublication
        let isComic = BookFormat(url: url)?.isComic == true
        do {
            publication = isComic ? try EPUBPublication(comicAt: url) : try EPUBPublication(contentsOf: url)
        } catch let error as EPUBError {
            throw error.userFacingError(isComic: isComic)
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

    /// A new tab with another view of this book (a link opened in a new tab), next to `source`
    /// or at the end of its tabs, in front or behind. Every view keeps its own place and
    /// history; the book's saved position is the one last moved, and bookmarks are shared.
    @discardableResult
    func openView(_ opening: ReaderViewController.Opening, besides source: NSWindow?,
                  placement: LinkOpening.Placement, inBackground: Bool) -> ReaderWindowController? {
        guard let publication else { return nil }
        let controller = ReaderWindowController(publication: publication, bookKey: bookKey(for: publication.book), opening: opening)
        addWindowController(controller)
        guard let window = controller.window else { return nil }
        if let source, source.isVisible {
            let anchor = placement == .end ? (source.tabbedWindows?.last ?? source) : source
            anchor.addTabbedWindow(window, ordered: .above)
        }
        if inBackground, let source, source.isVisible {
            source.tabGroup?.selectedWindow = source
            source.makeKeyAndOrderFront(nil)
        } else {
            controller.showWindow(nil)
        }
        return controller
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
    /// An `NSError` whose texts the document architecture shows in its alert; a comic has its own
    /// words where an EPUB's would be wrong (no ZIP to speak of, no chapters).
    func userFacingError(isComic: Bool) -> NSError {
        let reason: String
        switch self {
        case .unreadableArchive: reason = L10n.string(isComic ? "error.unreadableComic" : "error.unreadableArchive")
        case .passwordProtected: reason = L10n.string("error.passwordProtected")
        case .emptySpine where isComic: reason = L10n.string("error.noPages")
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
