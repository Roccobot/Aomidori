import AppKit
import AomidoriCore
import EPUBKit
import WebKit

/// The bundled sample chapter (`Resources/Playground/`): every element a book usually has,
/// marked up with the class names of `ReadingRoccobot.css`.
struct SampleTextProvider: PageResourceProvider {
    static let documentPath = "sample.xhtml"
    let directory: URL?

    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Playground", isDirectory: true)) {
        self.directory = directory
    }

    func resource(at path: String) throws -> EPUBResource {
        let components = path.split(separator: "/")
        guard let directory, !components.isEmpty, !components.contains(where: { $0 == ".." || $0 == "." }) else {
            throw EPUBError.missingResource(path: path)
        }
        let url = components.reduce(directory) { $0.appendingPathComponent(String($1)) }
        return EPUBResource(data: try Data(contentsOf: url), mediaType: MediaType.forPath(path))
    }
}

/// The Playground's preview: the reader's renderer (scheme handler, page script and style
/// layers), showing the sample chapter or the chapters of an EPUB, with `←`/`→` as in the reader.
@MainActor
final class PlaygroundPreviewController: NSViewController, WKNavigationDelegate {
    enum Source {
        case sample
        case book(EPUBPublication, title: String)
    }

    private(set) var source: Source = .sample
    private var renderer: PageRenderer
    private(set) var spineIndex: Int?
    /// Called after a document is shown (chapter changes included).
    var onNavigate: (() -> Void)?
    /// Called after a document has finished loading.
    var onLoad: (() -> Void)?

    var configuration: ReaderConfiguration {
        didSet { renderer.update(configuration) }
    }

    /// Night shows the page with the dark appearance, so `prefers-color-scheme: dark` applies.
    var night: Bool {
        didSet { applyAppearance() }
    }

    var webView: WKWebView { renderer.webView }

    init(configuration: ReaderConfiguration, night: Bool) {
        self.configuration = configuration
        self.night = night
        renderer = PageRenderer(provider: SampleTextProvider(), configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        view = NSView()
        install(renderer.webView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let top = view.safeAreaInsets.top
        if webView.obscuredContentInsets.top != top {
            webView.obscuredContentInsets = NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0)
        }
    }

    /// Shows the sample or a book from its first readable chapter, in a fresh renderer (each
    /// renderer serves one source).
    func show(_ source: Source) {
        self.source = source
        spineIndex = nil
        let previous = renderer.webView
        switch source {
        case .sample:
            renderer = PageRenderer(provider: SampleTextProvider(), configuration: configuration)
        case .book(let publication, _):
            renderer = PageRenderer(provider: publication, configuration: configuration)
        }
        previous.navigationDelegate = nil
        previous.removeFromSuperview()
        install(renderer.webView)
        viewDidLayout()
        load()
    }

    func load() {
        switch source {
        case .sample:
            renderer.load(path: SampleTextProvider.documentPath)
        case .book(let publication, _):
            if let first = publication.book.firstReadableIndex { showSpineItem(at: first) }
        }
    }

    private func install(_ webView: WKWebView) {
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        applyAppearance()
    }

    private func applyAppearance() {
        webView.appearance = NSAppearance(named: night ? .darkAqua : .aqua)
    }

    // MARK: Chapters

    private var book: EPUBBook? {
        if case .book(let publication, _) = source { return publication.book }
        return nil
    }

    var canGoToNextChapter: Bool { spineIndex.flatMap { book?.nextReadableIndex(after: $0) } != nil }
    var canGoToPreviousChapter: Bool { spineIndex.flatMap { book?.previousReadableIndex(before: $0) } != nil }

    func goToNextChapter() {
        guard let next = spineIndex.flatMap({ book?.nextReadableIndex(after: $0) }) else { NSSound.beep(); return }
        showSpineItem(at: next)
    }

    func goToPreviousChapter() {
        guard let previous = spineIndex.flatMap({ book?.previousReadableIndex(before: $0) }) else { NSSound.beep(); return }
        showSpineItem(at: previous)
    }

    private func showSpineItem(at index: Int) {
        guard let book, book.spine.indices.contains(index) else { return }
        renderer.load(path: book.spine[index].path)
    }

    /// "3 / 12" for books, `nil` for the sample.
    var chapterLabel: String? {
        guard let book, let spineIndex else { return nil }
        return "\(spineIndex + 1) / \(book.spine.count)"
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        if renderer.path(for: url) != nil || url?.scheme == "about" { return .allow }
        if navigationAction.navigationType == .linkActivated, let url,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        spineIndex = renderer.path(for: webView.url).flatMap { book?.spineIndex(forPath: $0) }
        onNavigate?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoad?()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if let spineIndex { showSpineItem(at: spineIndex) } else { load() }
    }
}
