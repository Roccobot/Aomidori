import AppKit
import UniformTypeIdentifiers

/// The reader window with no book: shown at launch with nothing to open and when the Dock icon
/// is clicked with no windows, instead of an Open panel. Same chrome as a reader window (the
/// app-wide toolbar items, Night appearance, the reader's frame); in the middle, a placeholder
/// with an Open button. A book opened from it (button, `⌘O`, or dropped on the window), or from
/// anywhere else while it is shown, takes its place: same frame, same tab.
@MainActor
final class EmptyReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    /// The empty window, while there is one. There is never more than one.
    private(set) static var current: EmptyReaderWindowController?

    private let environment = ReaderEnvironment.shared
    private let globalItems = GlobalToolbarItems()
    private var environmentObserver: (any NSObjectProtocol)?
    private let placeholder = EmptyReaderView()

    /// Shows the empty window, creating it if needed.
    static func show() {
        let controller = current ?? EmptyReaderWindowController()
        current = controller
        controller.showWindow(nil)
    }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        super.init(window: window)
        window.title = L10n.string("empty.title")
        window.minSize = NSSize(width: 420, height: 320)
        window.toolbarStyle = .unified
        window.tabbingIdentifier = "AomidoriReader"
        window.isRestorable = false
        window.delegate = self
        window.contentView = placeholder
        placeholder.onOpen = { [weak self] in self?.openDocument(nil) }
        placeholder.onDrop = { [weak self] urls in self?.open(urls) }
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

    /// Opens books through the document controller. The first one replaces this window (see
    /// `handOver(to:)`); a book that is already open is brought to the front instead.
    func open(_ urls: [URL]) {
        for url in urls {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] _, _, error in
                guard let error else { return }
                MainActor.assumeIsolated {
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

    /// Called before a reader window is created: the frame name goes free for it.
    func releaseFrameName() {
        window?.setFrameAutosaveName("")
    }

    /// The new reader window takes this window's frame and tab, then this window closes,
    /// once the reader window is on screen.
    func handOver(to controller: NSWindowController) {
        guard let window, let readerWindow = controller.window else { return }
        Self.current = nil
        readerWindow.setFrame(window.frame, display: false)
        if window.tabbedWindows.map({ $0.count > 1 }) ?? false {
            window.addTabbedWindow(readerWindow, ordered: .above)
        }
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

    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
        if let environmentObserver { NotificationCenter.default.removeObserver(environmentObserver) }
        environmentObserver = nil
    }

    // MARK: Smoke test

    var smokePlaceholderText: String { placeholder.message }
}

/// The empty window's content: a centred message and Open button, and a drop target for EPUB
/// files, outlined while a book is dragged over it.
@MainActor
final class EmptyReaderView: NSView {
    var onOpen: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    let message = L10n.string("empty.message")
    private var isDropTarget = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])

        let icon = NSImageView(image: NSImage(systemSymbolName: "book", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 56, weight: .light)
        icon.contentTintColor = .tertiaryLabelColor
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: NSFont.systemFontSize * 1.4)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let button = NSButton(title: L10n.string("empty.open"), target: self, action: #selector(openClicked(_:)))
        button.bezelStyle = .push
        button.controlSize = .large
        button.keyEquivalent = "o"
        button.keyEquivalentModifierMask = .command
        button.toolTip = L10n.string("empty.open.help")

        let stack = NSStackView(views: [icon, label, button])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.setCustomSpacing(24, after: label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
        ])
        setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func openClicked(_ sender: Any?) { onOpen?() }

    /// The EPUB files on a pasteboard: by type, or by extension when the type is unknown.
    static func epubURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let epub = UTType("org.idpf.epub-container")
        return urls.filter { url in
            if url.pathExtension.lowercased() == "epub" { return true }
            guard let epub, let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
            return type.conforms(to: epub)
        }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        isDropTarget = !Self.epubURLs(on: sender.draggingPasteboard).isEmpty
        return isDropTarget ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        isDropTarget = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        isDropTarget = false
        let urls = Self.epubURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isDropTarget else { return }
        let rect = safeAreaRect.insetBy(dx: 16, dy: 16)
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        path.lineWidth = 3
        path.setLineDash([10, 6], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
