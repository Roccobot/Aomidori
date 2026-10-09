import AomidoriCore
import AppKit
import UniformTypeIdentifiers

/// The reader window with no book: shown at launch with nothing to open, when the Dock icon is
/// clicked with no windows, and as a new tab (`⌘T`). Same chrome as a reader window (the
/// app-wide toolbar items, Night appearance, the reader's frame and tabs). From the top: Graphe's
/// drop zone, the invitation with an Open button, and the recent books. A book opened from it
/// (drop, Open button, `⌘O`, a recent book) takes its place: same frame, same tab.
@MainActor
final class EmptyReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// Empty windows on screen or minimised; several when opened as tabs.
    private(set) static var all: [EmptyReaderWindowController] = []
    /// The empty window a book is being opened from, so that this window is the one replaced.
    private static weak var pendingTarget: EmptyReaderWindowController?

    /// Big enough for the drop zone, the invitation and about five recent books. AppKit adds
    /// the toolbar to it: the window frame is at least 440×580 pt.
    static let minimumSize = NSSize(width: 440, height: 560)

    private let environment = ReaderEnvironment.shared
    private let globalItems = GlobalToolbarItems()
    private var environmentObserver: (any NSObjectProtocol)?
    private let content = EmptyReaderView()
    /// Set once a book has taken this window's place; it is closing.
    private var isHandedOver = false

    // MARK: Showing

    /// Shows an empty window: the existing one, or a new one.
    static func show() {
        let controller = all.first { !$0.isHandedOver } ?? make()
        controller.showWindow(nil)
    }

    /// `⌘T`: a new empty window, as a tab of `window` when it is a reader or empty window.
    static func openNewTab(besides window: NSWindow?) {
        let controller = make()
        if let window, let newWindow = controller.window, window.tabbingIdentifier == newWindow.tabbingIdentifier {
            window.addTabbedWindow(newWindow, ordered: .above)
        }
        controller.showWindow(nil)
    }

    private static func make() -> EmptyReaderWindowController {
        let controller = EmptyReaderWindowController()
        all.append(controller)
        return controller
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        super.init(window: window)
        window.title = L10n.string("empty.title")
        window.minSize = Self.minimumSize
        window.toolbarStyle = .unified
        window.tabbingIdentifier = ReaderWindowController.tabbingIdentifier
        window.tabbingMode = .preferred
        window.isRestorable = false
        window.delegate = self
        window.contentView = content
        content.onOpen = { [weak self] in self?.openDocument(nil) }
        content.onOpenURLs = { [weak self] urls in self?.open(urls) }
        window.center()
        if !LaunchSmokeTest.isActive { window.setFrameAutosaveName(ReaderWindowController.frameAutosaveName) }

        let toolbar = NSToolbar(identifier: "AomidoriEmptyToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        environmentObserver = NotificationCenter.default.addObserver(forName: .readerEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentDidChange() }
        }
        environmentDidChange()
        content.reloadRecents()
        window.initialFirstResponder = content.initialFirstResponder
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func environmentDidChange() {
        window?.appearance = environment.windowAppearance
        globalItems.update()
    }

    // MARK: Opening

    /// `⌘O` and the Open button: the Open panel as a sheet; the first book chosen opens here.
    @objc func openDocument(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType("org.idpf.epub-container") ?? .data]
        let handler: @MainActor (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.open(panel.urls)
        }
        panel.beginSheetModal(for: window, completionHandler: handler)
    }

    /// `⌘T` in an empty window: another empty tab.
    override func newWindowForTab(_ sender: Any?) {
        Self.openNewTab(besides: window)
    }

    /// Opens books through the document controller. The first one replaces this window (see
    /// `handOver(to:)`); a book that is already open is brought to the front instead.
    func open(_ urls: [URL]) {
        for (index, url) in urls.enumerated() {
            if index == 0 { Self.pendingTarget = self }
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
                MainActor.assumeIsolated {
                    if index == 0, let self, Self.pendingTarget === self { Self.pendingTarget = nil }
                    guard let error else { return }
                    let nsError = error as NSError
                    guard !(nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError) else { return }
                    if let window = self?.window, window.isVisible {
                        window.presentError(error, modalFor: window, delegate: nil, didPresent: nil, contextInfo: nil)
                    } else {
                        NSApp.presentError(error)
                    }
                }
            }
        }
    }

    // MARK: Handing over to a book

    /// The empty window a book being opened should replace: the one it was opened from; else
    /// the main window if it is empty; else the only empty window. Nil when there is none.
    static func target() -> EmptyReaderWindowController? {
        if let pending = pendingTarget, !pending.isHandedOver {
            pendingTarget = nil
            return pending
        }
        if let main = NSApp.mainWindow?.windowController as? EmptyReaderWindowController, !main.isHandedOver { return main }
        let candidates = all.filter { !$0.isHandedOver }
        return candidates.count == 1 ? candidates[0] : nil
    }

    /// Called before a reader window is created: the frame name goes free for it.
    func releaseFrameName() {
        window?.setFrameAutosaveName("")
    }

    /// The new reader window takes this window's frame and place among the tabs, then this
    /// window closes, once the reader window is on screen.
    func handOver(to controller: NSWindowController) {
        guard let window, let readerWindow = controller.window, !isHandedOver else { return }
        isHandedOver = true
        readerWindow.setFrame(window.frame, display: false)
        if window.isVisible { window.addTabbedWindow(readerWindow, ordered: .above) }
        Task { @MainActor in window.close() }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace] + GlobalToolbarItems.identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        globalItems.item(for: identifier)
    }

    // MARK: Window delegate

    /// The recent books may have changed while another window was in front.
    func windowDidBecomeKey(_ notification: Notification) {
        content.reloadRecents()
    }

    func windowWillClose(_ notification: Notification) {
        Self.all.removeAll { $0 === self }
        if let environmentObserver { NotificationCenter.default.removeObserver(environmentObserver) }
        environmentObserver = nil
    }

    // MARK: Smoke test

    var smokeContent: EmptyReaderView { content }
}
