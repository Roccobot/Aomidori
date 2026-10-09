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
/// Every chapter remembers where it was left: coming back to it (arrows, table of contents,
/// links without a fragment) lands there. Pushing past either end of a chapter offers the
/// next or previous one in a toast; see `ChapterEdgeDetector`.
@MainActor
final class ReaderViewController: NSViewController, WKNavigationDelegate {
    weak var delegate: ReaderViewControllerDelegate?

    let publication: EPUBPublication
    let bookKey: String
    private let renderer: PageRenderer
    private let environment = ReaderEnvironment.shared
    private(set) var currentSpineIndex: Int?
    /// Where the document being loaded should land; `nil` for navigations the page started
    /// itself (links), which land where the chapter was left unless they carry a fragment.
    private var pendingLanding: Landing?
    /// Applied once the document has loaded.
    private var pendingRestore: ChapterPosition?
    /// A search hit to reveal once its chapter has loaded.
    private var pendingFind: (hit: SearchHit, query: String)?
    private var findTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var edges = ChapterEdgeDetector()
    private let toast = ChapterToastView()
    private var toastTimer: Task<Void, Never>?
    private var isPointerOverToast = false
    /// How long the toast stays when left alone.
    private static let toastDuration: Duration = .seconds(3)

    var book: EPUBBook { publication.book }
    var webView: WKWebView { renderer.webView }

    init(publication: EPUBPublication, bookKey: String) {
        self.publication = publication
        self.bookKey = bookKey
        renderer = PageRenderer(provider: publication, configuration: ReaderEnvironment.shared.configuration())
        super.init(nibName: nil, bundle: nil)
        renderer.onPosition = { [weak self] path, position in self?.record(position, path: path) }
        renderer.onEdges = { [weak self] path, edges in
            guard let self, path == currentPath else { return }
            perform(self.edges.update(edges))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let container = NSView()
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.onClick = { [weak self] in self?.activateToast() }
        toast.onHoverChange = { [weak self] inside in self?.pointerOverToastChanged(inside) }
        container.addSubview(toast)
        NSLayoutConstraint.activate([
            // The page runs under the toolbar (Liquid Glass scroll edge) and starts below it.
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            // The toast floats low and centred over the page.
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
            toast.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -40),
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

    /// Where to land in a chapter.
    enum Landing {
        /// Where the reader left it, or the top.
        case remembered
        case top
        case position(ChapterPosition)
    }

    /// Opens the book where the reader left it, or at the first linear item.
    func start() {
        if let saved = environment.positions.position(forBook: bookKey),
           let index = book.spineIndex(forPath: saved.spinePath) ?? (book.spine.indices.contains(saved.spineIndex) ? saved.spineIndex : nil) {
            showSpineItem(at: index, landing: .position(saved.chapterPosition))
        } else if let first = book.firstReadableIndex {
            showSpineItem(at: first, landing: .top)
        }
    }

    func applyEnvironment() {
        renderer.update(environment.configuration())
        if let path = UserDefaults.standard.string(forKey: Self.snapshotDefaultsKey) {
            writeDiagnosticSnapshot(to: URL(fileURLWithPath: path))
        }
    }

    // MARK: Navigation

    var nextChapterIndex: Int? { currentSpineIndex.flatMap(book.nextReadableIndex(after:)) }
    var previousChapterIndex: Int? { currentSpineIndex.flatMap(book.previousReadableIndex(before:)) }
    var canGoToNextChapter: Bool { nextChapterIndex != nil }
    var canGoToPreviousChapter: Bool { previousChapterIndex != nil }

    /// Lands where the reader left the next chapter (the top, the first time).
    func goToNextChapter() {
        guard let next = nextChapterIndex else { NSSound.beep(); return }
        showSpineItem(at: next, landing: .remembered)
    }

    /// Lands where the reader left the previous chapter.
    func goToPreviousChapter() {
        guard let previous = previousChapterIndex else { NSSound.beep(); return }
        showSpineItem(at: previous, landing: .remembered)
    }

    /// Entries with a fragment go to it; others land where the reader left that chapter.
    func go(to entry: TOCEntry) {
        guard let path = entry.path else { return }
        if entry.fragment == nil, let index = book.spineIndex(forPath: path) {
            showSpineItem(at: index, landing: .remembered)
        } else {
            pendingLanding = .top
            renderer.load(path: path, fragment: entry.fragment)
        }
    }

    func showSpineItem(at index: Int, landing: Landing) {
        guard book.spine.indices.contains(index) else { return }
        pendingLanding = landing
        renderer.load(path: book.spine[index].path)
    }

    /// Reloads the current document from the book and the styles and fonts from disk, then
    /// lands where the reader was. The position is read before anything changes, so neither
    /// the new style nor the new document can move the reading line.
    func reload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            let path = currentPath
            let position = await renderer.currentPosition()
            guard !Task.isCancelled else { return }
            environment.reloadStyle()
            guard let path else { return }
            if let position { record(position, path: path) }
            pendingLanding = .position(position
                ?? environment.positions.chapterPosition(forBook: bookKey, spinePath: path) ?? .top)
            renderer.reload(path: path)
        }
    }

    /// Opens a bookmark's chapter at its scroll position.
    func show(_ bookmark: Bookmark) {
        guard let index = book.spineIndex(forPath: bookmark.spinePath)
                ?? (book.spine.indices.contains(bookmark.spineIndex) ? bookmark.spineIndex : nil) else { NSSound.beep(); return }
        if index == currentSpineIndex {
            renderer.scroll(toFraction: bookmark.fraction)
        } else {
            showSpineItem(at: index, landing: .position(ChapterPosition(fraction: bookmark.fraction)))
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
            showSpineItem(at: hit.spineIndex, landing: .top)
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

    /// A position reported by the page. Reports from a chapter already left only update that
    /// chapter's entry in the map.
    private func record(_ position: ChapterPosition, path: String) {
        guard let index = book.spineIndex(forPath: path) else { return }
        if index == currentSpineIndex, path == currentPath {
            environment.positions.setPosition(
                ReadingPosition(spinePath: path, spineIndex: index, fraction: position.fraction, anchor: position.anchor),
                forBook: bookKey
            )
        } else {
            environment.positions.setChapterPosition(position, spinePath: path, forBook: bookKey)
        }
        environment.saveStateSoon()
    }

    // MARK: Chapter edges

    /// Space, `↓`, Page Down (forward) or Shift-Space, `↑`, Page Up (backward) while reading.
    /// Returns whether the key was used (it took the reader to another chapter).
    func handleEdgeKey(_ direction: EdgeDirection) -> Bool {
        edges.isPointerOverToast = toast.containsPointer
        return perform(edges.key(direction))
    }

    /// A scroll event over the page. Returns whether it was used.
    func handleEdgeScroll(_ event: NSEvent) -> Bool {
        guard abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) else { return false }
        let phase: EdgeScroll.Phase =
            if event.phase.contains(.began) || event.phase.contains(.mayBegin) { .began }
            else if event.phase.contains(.ended) || event.phase.contains(.cancelled) { .ended }
            else if event.phase.contains(.changed) || event.phase.contains(.stationary) { .changed }
            else { .none }
        let scroll = EdgeScroll(deltaY: event.scrollingDeltaY, isPrecise: event.hasPreciseScrollingDeltas,
                                phase: phase, isMomentum: !event.momentumPhase.isEmpty)
        edges.isPointerOverToast = toast.containsPointer
        return perform(edges.scroll(scroll))
    }

    @discardableResult
    private func perform(_ action: EdgeAction) -> Bool {
        switch action {
        case .none:
            return false
        case .show(let direction):
            let kind: ChapterToastView.Kind = direction == .backward ? .previous : (canGoToNextChapter ? .next : .endOfBook)
            toast.show(kind)
            scheduleToastHide()
            return false
        case .hide:
            hideToast()
            return false
        case .activate(let direction):
            hideToast()
            go(past: direction)
            return true
        }
    }

    private func activateToast() {
        guard let direction = edges.toast else { return }
        hideToast()
        go(past: direction)
    }

    /// Forward: the top of the next chapter or, at the end of the book, its table of contents
    /// page (or its start). Backward: where the reader left the previous chapter.
    private func go(past direction: EdgeDirection) {
        switch direction {
        case .forward:
            if let next = nextChapterIndex {
                showSpineItem(at: next, landing: .top)
            } else if let target = book.tableOfContentsIndex ?? (book.spine.isEmpty ? nil : 0) {
                showSpineItem(at: target, landing: .top)
            }
        case .backward:
            if let previous = previousChapterIndex { showSpineItem(at: previous, landing: .remembered) }
        }
    }

    private func hideToast() {
        toastTimer?.cancel()
        toastTimer = nil
        edges.toastDidHide()
        toast.hide()
    }

    private func scheduleToastHide() {
        toastTimer?.cancel()
        toastTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.toastDuration)
            guard !Task.isCancelled, let self else { return }
            // Never pulled away from under the pointer: it goes once the pointer leaves.
            if isPointerOverToast || toast.containsPointer { return }
            hideToast()
        }
    }

    private func pointerOverToastChanged(_ inside: Bool) {
        isPointerOverToast = inside
        if !inside, toast.isShown { scheduleToastHide() }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let url = navigationAction.request.url
        if let path = renderer.path(for: url) {
            // Leaving a chapter: note exactly where, since the last scroll report may be pending.
            if let current = currentPath, current != path, navigationAction.targetFrame?.isMainFrame != false,
               let position = await renderer.currentPosition() {
                record(position, path: current)
            }
            return .allow
        }
        if url?.scheme == "about" { return .allow }
        // Links that leave the book open in the default browser or mail client.
        if navigationAction.navigationType == .linkActivated, let url,
           ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let path = currentPath
        let index = path.flatMap(book.spineIndex(forPath:))
        currentSpineIndex = index
        hideToast()
        edges.reset(hasPrevious: previousChapterIndex != nil)
        let landing: Landing? = pendingLanding ?? (webView.url?.fragment == nil ? .remembered : nil)
        pendingLanding = nil
        pendingRestore = nil
        if let index, let path, webView.url?.fragment == nil, let landing {
            let target: ChapterPosition = switch landing {
            case .top: .top
            case .position(let position): position
            case .remembered: environment.positions.chapterPosition(forBook: bookKey, spinePath: path) ?? .top
            }
            if target.fraction > 0 { pendingRestore = target }
            // The page reports positions only when it scrolls: the top is recorded now.
            record(target, path: book.spine[index].path)
        }
        delegate?.readerDidShowChapter(self)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let position = pendingRestore {
            pendingRestore = nil
            renderer.restore(position)
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

    /// For `ReaderSmokeTest`: renders with a changed configuration without touching the
    /// reader's saved settings; `nil` goes back to them.
    func smokeConfigure(_ change: ((inout ReaderConfiguration) -> Void)?) {
        var configuration = environment.configuration()
        change?(&configuration)
        renderer.update(configuration)
    }

    func smokeCurrentPosition() async -> ChapterPosition? { await renderer.currentPosition() }
    func smokeScroll(toFraction fraction: Double) { renderer.scroll(toFraction: fraction) }
    var smokeToast: ChapterToastView.Kind? { toast.isShown ? toast.kind : nil }
    var smokeEdges: ScrollEdges { edges.edges }
    func smokeClickToast() { activateToast() }

    /// Launch argument `-AomidoriFontProbe "Family A,Family B"` (with a snapshot path): writes
    /// `<file>.fonts.json`, telling for each family whether the web view can draw it by name
    /// (canvas text width differs from every generic fallback), and the load status of the
    /// custom font's faces.
    static let fontProbeDefaultsKey = "AomidoriFontProbe"

    private func writeFontProbe(families: String, to url: URL) {
        let names = families.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let data = try? JSONEncoder().encode(names), let list = String(data: data, encoding: .utf8) else { return }
        let script = """
        (async () => {
          await new Promise(r => setTimeout(r, 800)); await document.fonts.ready;
          const c = document.createElement('canvas').getContext('2d');
          const text = 'mmmmmmmmmmlli WWW 0123 Aomidori';
          const width = (font) => { c.font = `72px ${font}`; return c.measureText(text).width; };
          const byName = {};
          for (const family of \(list)) {
            byName[family] = ['monospace', 'serif', 'sans-serif'].every(g => width(`"${family}", ${g}`) !== width(g));
          }
          const faces = [];
          document.fonts.forEach(f => faces.push(`${f.family} ${f.weight} ${f.style}: ${f.status}`));
          const body = document.body ? getComputedStyle(document.body).fontFamily : '';
          return JSON.stringify({ byName, faces, bodyFontFamily: body }, null, 1);
        })()
        """
        webView.callAsyncJavaScript("return await \(script);", arguments: [:], in: nil, in: .defaultClient) { result in
            guard case .success(let value) = result, let text = value as? String else { return }
            try? Data(text.utf8).write(to: url)
        }
    }


    /// Launch argument `-AomidoriSnapshotPath <file.png>`: after each chapter loads and after each
    /// settings or style change, the page is saved there and as `<file>-<n>.png` (n = 1, 2, …),
    /// with the window chrome as `<file>.window.png`. Used by `scripts/smoke.sh`, because a
    /// command-line process may not capture other apps' windows.
    static let snapshotDefaultsKey = "AomidoriSnapshotPath"
    private static var snapshotCount = 0

    private func writeDiagnosticSnapshot(to url: URL) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, let image = try? await webView.takeSnapshot(configuration: nil) else { return }
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            Self.snapshotCount += 1
            Self.writePNG(cgImage, to: URL(fileURLWithPath: url.deletingPathExtension().path + "-\(Self.snapshotCount).png"))
            Self.writePNG(cgImage, to: url)
            if let families = UserDefaults.standard.string(forKey: Self.fontProbeDefaultsKey) {
                writeFontProbe(families: families, to: url.deletingPathExtension().appendingPathExtension("fonts.json"))
            }
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
            showSpineItem(at: index, landing: .remembered)
        }
    }
}
