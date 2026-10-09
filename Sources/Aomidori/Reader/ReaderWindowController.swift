import AppKit
import AomidoriCore
import EPUBKit

/// One window per open book: a sidebar (contents, bookmarks, search) and the reading view.
@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSMenuItemValidation, ReaderViewControllerDelegate {

    private enum ToolbarID {
        static let chapters = NSToolbarItem.Identifier("Aomidori.chapters")
        static let info = NSToolbarItem.Identifier("Aomidori.info")
    }

    let reader: ReaderViewController
    private let toc: TOCViewController
    private let bookmarks: BookmarksViewController
    private let search: SearchViewController
    private let sidebar: SidebarViewController
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let picker = StylePicker()
    private let environment = ReaderEnvironment.shared
    private let globalItems = GlobalToolbarItems()
    private var chaptersItem: NSToolbarItemGroup?
    private var inspector: InspectorWindowController?
    private var environmentObserver: (any NSObjectProtocol)?
    private var isMinimal = false
    private var sidebarWasCollapsed = true
    private var smokeTest: ReaderSmokeTest?

    init(publication: EPUBPublication, bookKey: String) {
        reader = ReaderViewController(publication: publication, bookKey: bookKey)
        toc = TOCViewController(entries: publication.book.toc)
        bookmarks = BookmarksViewController(book: publication.book)
        search = SearchViewController(publication: publication)
        let state = ReaderEnvironment.shared.books.state(forBook: bookKey)
        sidebar = SidebarViewController(
            initialPane: state.sidebarPane ?? .contents,
            panes: [.contents: toc, .bookmarks: bookmarks, .search: search]
        )
        bookmarks.bookmarks = state.sortedBookmarks
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        super.init(window: window)

        sidebarItem.isCollapsed = true
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 420
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: reader))

        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 860, height: 980))
        window.minSize = NSSize(width: 420, height: 320)
        window.toolbarStyle = .unified
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .preferred
        window.delegate = self
        window.isRestorable = false
        // A smoke session resizes the window: its frame is not remembered.
        if !ReaderSmokeTest.isActive && !LaunchSmokeTest.isActive { window.setFrameAutosaveName(Self.frameAutosaveName) }

        let toolbar = NSToolbar(identifier: "AomidoriReaderToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        reader.delegate = self
        toc.onSelect = { [weak self] entry in
            guard let self else { return }
            reader.go(to: entry)
            window.makeFirstResponder(reader.webView)
        }
        bookmarks.onSelect = { [weak self] bookmark in self?.reader.show(bookmark) }
        bookmarks.onDelete = { [weak self] bookmark in self?.deleteBookmark(bookmark) }
        // Focus stays in the results, so the next hit is one arrow key away.
        search.onSelect = { [weak self] hit, query in self?.reader.show(hit, query: query) }
        sidebar.onPaneChange = { [weak self] pane in self?.rememberPane(pane) }

        environmentObserver = NotificationCenter.default.addObserver(forName: .readerEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentDidChange() }
        }

        applyAppearance()
        if environment.prefersMinimal { setMinimal(true) }
        reader.start()
        window.makeFirstResponder(reader.webView)
        if ReaderSmokeTest.isActive { smokeTest = ReaderSmokeTest(windowController: self) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shared with the empty window, which stands where the next book will open.
    static let frameAutosaveName = "AomidoriReaderWindow"
    /// Reader and empty windows are tabs of each other; books open as tabs.
    static let tabbingIdentifier = "AomidoriReader"

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        reader.book.title ?? displayName
    }

    private func environmentDidChange() {
        applyAppearance()
        reader.applyEnvironment()
        updateToolbar()
    }

    private func applyAppearance() {
        window?.appearance = environment.windowAppearance
    }

    // MARK: Reader delegate

    func readerDidShowChapter(_ reader: ReaderViewController) {
        window?.subtitle = reader.currentChapterTitle ?? ""
        if let path = reader.currentPath { toc.reveal(path: path) }
        updateToolbar()
    }

    // MARK: Actions (window-specific; global ones live in AppDelegate)

    /// `⌘T` and the tab bar's + button: an empty tab.
    override func newWindowForTab(_ sender: Any?) {
        EmptyReaderWindowController.openNewTab(besides: window)
    }

    @objc func goToPreviousChapter(_ sender: Any?) { reader.goToPreviousChapter() }
    @objc func goToNextChapter(_ sender: Any?) { reader.goToNextChapter() }

    @objc func showStyleList(_ sender: Any?) {
        guard let window else { return }
        picker.show(over: window, heldModifier: nil)
    }

    /// Shows the book information window, or closes it if it is in front.
    @objc func showInspector(_ sender: Any?) {
        if let window = inspector?.window, window.isKeyWindow {
            window.performClose(nil)
            return
        }
        let inspector = inspector ?? InspectorWindowController(publication: reader.publication)
        self.inspector = inspector
        inspector.showWindow(nil)
    }

    // MARK: Sidebar

    /// `⌥⌘1`…`⌥⌘6`: opens the sidebar on a pane (the menu item's tag is the pane's digit).
    @objc func showSidebarPane(_ sender: NSMenuItem) {
        guard let pane = SidebarPane.allCases.first(where: { $0.shortcutDigit == sender.tag }) else { return }
        show(pane)
    }

    /// `⌘F`: the search pane, with the cursor in its field.
    @objc func showSearch(_ sender: Any?) {
        show(.search)
        search.focusSearchField()
    }

    private func show(_ pane: SidebarPane) {
        guard pane.isAvailable, !isMinimal else { NSSound.beep(); return }
        sidebar.select(pane)
        rememberPane(pane)
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
    }

    private func rememberPane(_ pane: SidebarPane) {
        environment.books.update(forBook: reader.bookKey) { $0.sidebarPane = pane }
        environment.saveStateSoon()
    }

    // MARK: Bookmarks

    /// `⌘D`: asks for a title (the chapter's, by default) and bookmarks the current place.
    @objc func addBookmark(_ sender: Any?) {
        guard let window, let index = reader.currentSpineIndex else { NSSound.beep(); return }
        let path = reader.book.spine[index].path
        let fraction = reader.currentFraction

        let alert = NSAlert()
        alert.messageText = L10n.string("bookmarks.add.title")
        alert.informativeText = L10n.string("bookmarks.add.message")
        let field = NSTextField(string: reader.currentChapterTitle ?? reader.book.title ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.string("bookmarks.add.confirm"))
        alert.addButton(withTitle: L10n.string("common.cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let bookmark = Bookmark(title: title.isEmpty ? L10n.string("bookmarks.untitled") : title,
                                    spinePath: path, spineIndex: index, fraction: fraction)
            updateBookmarks { $0.append(bookmark) }
            show(.bookmarks)
        }
    }

    private func deleteBookmark(_ bookmark: Bookmark) {
        updateBookmarks { $0.removeAll { $0.id == bookmark.id } }
    }

    private func updateBookmarks(_ change: (inout [Bookmark]) -> Void) {
        environment.books.update(forBook: reader.bookKey) { change(&$0.bookmarks) }
        bookmarks.bookmarks = environment.books.state(forBook: reader.bookKey).sortedBookmarks
        environment.saveStateSoon()
    }

    @objc func toggleMinimalMode(_ sender: Any?) {
        setMinimal(!isMinimal)
        environment.prefersMinimal = isMinimal
    }

    @objc private func chapterGroupClicked(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { reader.goToPreviousChapter() } else { reader.goToNextChapter() }
    }

    /// Minimal mode leaves only the text: no toolbar, no title, no window buttons, no sidebar.
    private func setMinimal(_ minimal: Bool) {
        guard let window, minimal != isMinimal else { return }
        isMinimal = minimal
        if minimal {
            sidebarWasCollapsed = sidebarItem.isCollapsed
            sidebarItem.isCollapsed = true
        } else {
            sidebarItem.isCollapsed = sidebarWasCollapsed
        }
        window.toolbar?.isVisible = !minimal
        window.titleVisibility = minimal ? .hidden : .visible
        window.titlebarAppearsTransparent = minimal
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(button)?.isHidden = minimal
        }
    }

    // MARK: Keyboard

    /// Keys handled outside the menu bar: plain `←` `→` `+` `-` `0` while reading, the
    /// style list shortcuts, whose hold-to-cycle behaviour needs key-up and modifier tracking,
    /// and the keys and scrolling that push past the edge of a chapter (seen, not consumed,
    /// unless they take the reader to another chapter).
    func handle(_ event: NSEvent) -> Bool {
        if event.type == .scrollWheel {
            guard event.window === window, reader.view.bounds.contains(reader.view.convert(event.locationInWindow, from: nil)) else { return false }
            return reader.handleEdgeScroll(event)
        }
        if picker.handle(event) { return true }
        guard event.type == .keyDown, let window else { return false }

        if StylePicker.isPickerShortcut(event) {
            picker.show(over: window, heldModifier: .command)
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if isReadingFocused, !event.isARepeat, let direction = Self.edgeDirection(keyCode: event.keyCode, flags: flags),
           reader.handleEdgeKey(direction) {
            return true
        }
        guard flags.isEmpty, isReadingFocused else { return false }
        switch event.keyCode {
        case KeyCode.leftArrow: reader.goToPreviousChapter(); return true
        case KeyCode.rightArrow: reader.goToNextChapter(); return true
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case "+", "=": NSApp.sendAction(#selector(AppDelegate.increaseTextSize(_:)), to: nil, from: self)
        case "-": NSApp.sendAction(#selector(AppDelegate.decreaseTextSize(_:)), to: nil, from: self)
        case "0": NSApp.sendAction(#selector(AppDelegate.resetTextSize(_:)), to: nil, from: self)
        default: return false
        }
        return true
    }

    /// The page-scrolling keys that can push past the edge of a chapter. They still scroll the
    /// page; the reader only acts on them at an edge.
    private static func edgeDirection(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> EdgeDirection? {
        if flags == [.shift] { return keyCode == KeyCode.space ? .backward : nil }
        guard flags.isEmpty else { return nil }
        switch keyCode {
        case KeyCode.space, KeyCode.downArrow, KeyCode.pageDown: return .forward
        case KeyCode.upArrow, KeyCode.pageUp: return .backward
        default: return nil
        }
    }

    /// Whether keystrokes are meant for the page (not the table of contents).
    private var isReadingFocused: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder === window { return true }
        return (responder as? NSView)?.isDescendant(of: reader.webView) ?? false
    }

    private var isEditingText: Bool { window?.firstResponder is NSText }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        // `←` `→` are plain-key shortcuts: disabled while typing, so text fields get them.
        case #selector(goToPreviousChapter(_:)): return reader.canGoToPreviousChapter && !isEditingText
        case #selector(goToNextChapter(_:)): return reader.canGoToNextChapter && !isEditingText
        case #selector(toggleMinimalMode(_:)):
            menuItem.state = isMinimal ? .on : .off
            return true
        case #selector(showStyleList(_:)): return !environment.styles.isEmpty
        case #selector(showSidebarPane(_:)):
            let pane = SidebarPane.allCases.first { $0.shortcutDigit == menuItem.tag }
            menuItem.state = !sidebarItem.isCollapsed && pane == sidebar.pane ? .on : .off
            return pane?.isAvailable == true && !isMinimal
        case #selector(showSearch(_:)): return !isMinimal
        case #selector(addBookmark(_:)): return reader.currentSpineIndex != nil
        default: return true
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, ToolbarID.chapters, ToolbarID.info, .flexibleSpace]
            + GlobalToolbarItems.identifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case ToolbarID.chapters:
            let group = NSToolbarItemGroup(
                itemIdentifier: identifier,
                images: [Self.symbol("chevron.left", L10n.string("menu.go.previousChapter")),
                         Self.symbol("chevron.right", L10n.string("menu.go.nextChapter"))],
                selectionMode: .momentary,
                labels: [L10n.string("toolbar.previous"), L10n.string("toolbar.next")],
                target: self,
                action: #selector(chapterGroupClicked(_:))
            )
            group.label = L10n.string("toolbar.chapters")
            group.toolTip = L10n.string("toolbar.chapters.help")
            group.isNavigational = true
            group.autovalidates = false
            group.subitems.forEach { $0.autovalidates = false }
            chaptersItem = group
            updateToolbar()
            return group
        case ToolbarID.info:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("menu.file.inspector")
            item.toolTip = L10n.string("toolbar.info.help")
            item.image = Self.symbol("info.circle", L10n.string("menu.file.inspector"))
            item.action = #selector(showInspector(_:))
            item.target = self
            item.isBordered = true
            return item
        default:
            return globalItems.item(for: identifier)
        }
    }

    private func updateToolbar() {
        chaptersItem?.subitems.first?.isEnabled = reader.canGoToPreviousChapter
        chaptersItem?.subitems.last?.isEnabled = reader.canGoToNextChapter
        globalItems.update()
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        GlobalToolbarItems.symbol(name, description)
    }

    // MARK: Window delegate

    func windowWillClose(_ notification: Notification) {
        picker.dismiss()
        inspector?.close()
        if let environmentObserver { NotificationCenter.default.removeObserver(environmentObserver) }
        environmentObserver = nil
        environment.saveStateNow()
    }
}
