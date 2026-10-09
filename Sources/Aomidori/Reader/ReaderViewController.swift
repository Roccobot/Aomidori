import AppKit
import EPUBKit
import AomidoriCore
import WebKit

@MainActor
protocol ReaderViewControllerDelegate: AnyObject {
    func readerDidShowChapter(_ reader: ReaderViewController)
}

/// Shows one spine item at a time as a real web document that scrolls vertically.
/// `←`/`→` move through the reading order; links between chapters are followed in place.
@MainActor
final class ReaderViewController: NSViewController, WKNavigationDelegate {
    weak var delegate: ReaderViewControllerDelegate?

    let publication: EPUBPublication
    let bookKey: String
    private let renderer: PageRenderer
    private let environment = ReaderEnvironment.shared
    private(set) var currentSpineIndex: Int?
    private var pendingFraction: Double?
    /// A search hit to reveal once its chapter has loaded.
    private var pendingFind: (hit: SearchHit, query: String)?
    private var findTask: Task<Void, Never>?

    var book: EPUBBook { publication.book }
    var webView: WKWebView { renderer.webView }

    init(publication: EPUBPublication, bookKey: String) {
        self.publication = publication
        self.bookKey = bookKey
        renderer = PageRenderer(provider: publication, configuration: ReaderEnvironment.shared.configuration())
        super.init(nibName: nil, bundle: nil)
        renderer.onScrollFraction = { [weak self] fraction in self?.recordPosition(fraction: fraction) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        // The page runs under the toolbar (Liquid Glass scroll edge) and starts below it.
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let top = view.safeAreaInsets.top
        if webView.obscuredContentInsets.top != top {
            webView.obscuredContentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        }
    }

    /// Opens the book where the reader left it, or at the first linear item.
    func start() {
        if let saved = environment.positions.position(forBook: bookKey),
           let index = book.spineIndex(forPath: saved.spinePath) ?? (book.spine.indices.contains(saved.spineIndex) ? saved.spineIndex : nil) {
            showSpineItem(at: index, fraction: saved.fraction)
        } else if let first = book.firstReadableIndex {
            showSpineItem(at: first)
        }
    }

    func applyEnvironment() {
        renderer.update(environment.configuration())
    }

    // MARK: Navigation

    var canGoToNextChapter: Bool { currentSpineIndex.flatMap(book.nextReadableIndex(after:)) != nil }
    var canGoToPreviousChapter: Bool { currentSpineIndex.flatMap(book.previousReadableIndex(before:)) != nil }

    func goToNextChapter() {
        guard let next = currentSpineIndex.flatMap(book.nextReadableIndex(after:)) else { NSSound.beep(); return }
        showSpineItem(at: next)
    }

    /// Lands at the top of the previous chapter.
    func goToPreviousChapter() {
        guard let previous = currentSpineIndex.flatMap(book.previousReadableIndex(before:)) else { NSSound.beep(); return }
        showSpineItem(at: previous)
    }

    func go(to entry: TOCEntry) {
        guard let path = entry.path else { return }
        renderer.load(path: path, fragment: entry.fragment)
    }

    func showSpineItem(at index: Int, fraction: Double? = nil) {
        guard book.spine.indices.contains(index) else { return }
        pendingFraction = fraction.flatMap { $0 > 0 ? $0 : nil }
        renderer.load(path: book.spine[index].path)
    }

    /// Opens a bookmark's chapter at its scroll position.
    func show(_ bookmark: Bookmark) {
        guard let index = book.spineIndex(forPath: bookmark.spinePath)
                ?? (book.spine.indices.contains(bookmark.spineIndex) ? bookmark.spineIndex : nil) else { NSSound.beep(); return }
        if index == currentSpineIndex {
            renderer.scroll(toFraction: bookmark.fraction)
        } else {
            showSpineItem(at: index, fraction: bookmark.fraction)
        }
    }

    /// Opens a search hit's chapter and selects the occurrence with WebKit's find, which also
    /// scrolls to it. If WebKit counts occurrences differently (hidden text, diacritics), the
    /// page scrolls to the hit's approximate position instead.
    func show(_ hit: SearchHit, query: String) {
        guard book.spine.indices.contains(hit.spineIndex) else { return }
        if hit.spineIndex == currentSpineIndex, !webView.isLoading {
            reveal(hit, query: query)
        } else {
            pendingFind = (hit, query)
            showSpineItem(at: hit.spineIndex)
        }
    }

    private func reveal(_ hit: SearchHit, query: String) {
        findTask?.cancel()
        findTask = Task { [weak self] in
            guard let webView = self?.webView else { return }
            // Find continues from the current selection: start from the top of the document.
            webView.evaluateJavaScript("window.getSelection().removeAllRanges()", in: nil, in: .defaultClient)
            let configuration = WKFindConfiguration()
            configuration.caseSensitive = false
            configuration.wraps = false
            var found = false
            for _ in 0...hit.occurrence {
                guard !Task.isCancelled, let result = try? await webView.find(query, configuration: configuration) else { return }
                found = result.matchFound
                if !found { break }
            }
            if !found, !Task.isCancelled { self?.renderer.scroll(toFraction: hit.fraction) }
        }
    }

    /// Scroll position in the current chapter, 0...1, as last reported by the page.
    var currentFraction: Double {
        guard let index = currentSpineIndex, let saved = environment.positions.position(forBook: bookKey),
              saved.spinePath == book.spine[index].path else { return 0 }
        return saved.fraction
    }

    /// Title of the TOC entry for the current chapter, if any.
    var currentChapterTitle: String? {
        currentSpineIndex.flatMap { book.tocTitle(forPath: book.spine[$0].path) }
    }

    var currentPath: String? { renderer.path(for: webView.url) }

    private func recordPosition(fraction: Double) {
        guard let index = currentSpineIndex else { return }
        environment.positions.setPosition(
            ReadingPosition(spinePath: book.spine[index].path, spineIndex: index, fraction: fraction),
            forBook: bookKey
        )
        environment.saveStateSoon()
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        if renderer.path(for: url) != nil || url?.scheme == "about" {
            return .allow
        }
        // Links that leave the book open in the default browser or mail client.
        if navigationAction.navigationType == .linkActivated, let url,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let index = currentPath.flatMap(book.spineIndex(forPath:))
        currentSpineIndex = index
        if index != nil, pendingFraction == nil, webView.url?.fragment == nil {
            recordPosition(fraction: 0)
        }
        delegate?.readerDidShowChapter(self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let fraction = pendingFraction {
            pendingFraction = nil
            renderer.scroll(toFraction: fraction)
        }
        if let find = pendingFind {
            pendingFind = nil
            if find.hit.spineIndex == currentSpineIndex { reveal(find.hit, query: find.query) }
        }
        if let path = UserDefaults.standard.string(forKey: Self.snapshotDefaultsKey) {
            writeDiagnosticSnapshot(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: Diagnostics

    /// Launch argument `-AomidoriSnapshotPath <file.png>`: after each chapter loads, the page is
    /// saved there (and the window chrome next to it, as `<file>-window.png`). Used by
    /// `scripts/smoke.sh`, because a command-line process may not capture other apps' windows.
    static let snapshotDefaultsKey = "AomidoriSnapshotPath"

    private func writeDiagnosticSnapshot(to url: URL) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, let image = try? await webView.takeSnapshot(configuration: nil) else { return }
            Self.writePNG(image.cgImage(forProposedRect: nil, context: nil, hints: nil), to: url)
            if let frameView = view.window?.contentView?.superview,
               let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
                Self.writePNG(rep.cgImage, to: url.deletingPathExtension().appendingPathExtension("window.png"))
            }
        }
    }

    private static func writePNG(_ image: CGImage?, to url: URL) {
        guard let image else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Recover from a crashed web process where the reader was.
        if let index = currentSpineIndex {
            showSpineItem(at: index, fraction: environment.positions.position(forBook: bookKey)?.fraction)
        }
    }
}
