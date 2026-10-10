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
        static let split = NSToolbarItem.Identifier("Aomidori.split")
    }

    let reader: ReaderViewController
    private let toc: TOCViewController
    private let bookmarks: BookmarksViewController
    private let search: SearchViewController
    private let sidebar: SidebarViewController
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let readerItem: NSSplitViewItem
    private var splitToolbarItem: NSToolbarItem?

    // Split view: the right half shows another tab's reader (`splitGuest`, whose own window is
    // hidden meanwhile), or the chooser when several tabs could go there.
    private var splitItem: NSSplitViewItem?
    private var splitGuest: ReaderWindowController?
    /// The right half is a view made for the split (no other tab to show): it closes with it.
    private var splitGuestIsOwned = false
    private var chooser: SplitChooserViewController?
    private var chooserTabs: [NSWindow] = []
    /// Set while this window's reader is shown in another window's split.
    private(set) weak var splitHost: ReaderWindowController?
    /// The tabs beside this one when it went into a split, so it goes back to its place.
    private weak var tabBefore: NSWindow?
    private weak var tabAfter: NSWindow?
    private let picker = StylePicker()
    private let environment = ReaderEnvironment.shared
    private let globalItems = GlobalToolbarItems()
    private var chaptersItem: NSToolbarItemGroup?
    private var inspector: InspectorWindowController?
    private var environmentObserver: (any NSObjectProtocol)?
    private var bookStateObserver: (any NSObjectProtocol)?
    private var isMinimal = false
    private var sidebarWasCollapsed = true
    private var smokeTest: ReaderSmokeTest?

    init(publication: EPUBPublication, bookKey: String, opening: ReaderViewController.Opening = .saved) {
        reader = ReaderViewController(publication: publication, bookKey: bookKey, opening: opening)
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
        readerItem = NSSplitViewItem(viewController: reader)

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
        splitViewController.addSplitViewItem(readerItem)

        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 860, height: 980))
        window.minSize = NSSize(width: 420, height: 320)
        window.toolbarStyle = .unified
        window.tabbingIdentifier = Self.tabbingIdentifier
        window.tabbingMode = .preferred
        window.delegate = self
        window.isRestorable = false
        // A smoke session resizes the window: its frame is not remembered.
        if AppPaths.smokeFolder == nil { window.setFrameAutosaveName(Self.frameAutosaveName) }

        let toolbar = NSToolbar(identifier: "AomidoriReaderToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        reader.delegate = self
        // Only weak captures: the sidebar panes live as long as the window, and a strong
        // reference to it here would keep every closed book (web view, ZIP) in memory.
        toc.onSelect = { [weak self] entry in
            guard let self else { return }
            reader.go(to: entry)
            self.window?.makeFirstResponder(reader.webView)
        }
        bookmarks.onSelect = { [weak self] bookmark in self?.reader.show(bookmark) }
        bookmarks.onDelete = { [weak self] bookmark in self?.deleteBookmark(bookmark) }
        // Focus stays in the results, so the next hit is one arrow key away.
        search.onSelect = { [weak self] hit, query in self?.reader.show(hit, query: query) }
        sidebar.onPaneChange = { [weak self] pane in self?.rememberPane(pane) }

        environmentObserver = NotificationCenter.default.addObserver(forName: .readerEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentDidChange() }
        }
        // Another view of the same book changed its bookmarks.
        bookStateObserver = NotificationCenter.default.addObserver(forName: .readerBookStateDidChange, object: nil, queue: .main) { [weak self] note in
            let key = note.userInfo?["bookKey"] as? String
            MainActor.assumeIsolated { self?.bookStateDidChange(forBook: key) }
        }

        applyAppearance()
        if environment.prefersMinimal { setMinimal(true) }
        reader.start()
        window.makeFirstResponder(reader.webView)
        // Scripted sessions run in the book's first window, not in the views opened from it.
        if case .saved = opening {
            if ReaderSmokeTest.isActive { smokeTest = ReaderSmokeTest(windowController: self) }
            ScreenshotSession.prepare(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shared with the empty window, which stands where the next book will open.
    static let frameAutosaveName = "AomidoriReaderWindow"
    /// Reader and empty windows are tabs of each other; books open as tabs.
    static let tabbingIdentifier = "AomidoriReader"

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        BookTitle.display(title: reader.book.title, fileURL: (document as? NSDocument)?.fileURL) ?? displayName
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

    /// A link to open in another tab: a new view of this book, beside this tab (beside the
    /// split's window, when this reader is its right half).
    func reader(_ reader: ReaderViewController, openInNewTab opening: ReaderViewController.Opening, inBackground: Bool) {
        (document as? BookDocument)?.openView(opening, besides: splitHost?.window ?? window,
                                              placement: environment.linkTabPlacement, inBackground: inBackground)
    }

    private func bookStateDidChange(forBook key: String?) {
        guard key == reader.bookKey else { return }
        bookmarks.bookmarks = environment.books.state(forBook: reader.bookKey).sortedBookmarks
    }

    // MARK: Split view

    var isSplit: Bool { splitItem != nil }

    /// `⌘S` and the toolbar button: this tab on the left (with the sidebar) and another on the
    /// right; again, back to one, the other tab back in its place in the tab bar (Rocco's
    /// requests). The only other tab goes straight in; with several, a numbered list chooses,
    /// another view of this book preselected, else the tab to the right; with none, a second
    /// view of this book at the same place.
    @objc func toggleSplit(_ sender: Any?) {
        if isSplit { endSplit() } else { beginSplit() }
    }

    private func beginSplit() {
        guard let window, splitHost == nil, !isMinimal else { NSSound.beep(); return }
        let tabWindows = window.tabbedWindows ?? [window]
        let tabs = tabWindows.map { tab -> SplitChooser.Tab in
            let other = tab.windowController as? ReaderWindowController
            return SplitChooser.Tab(title: tab.title, isReader: other != nil,
                                    isSameBook: other.map { $0.document === document } ?? false)
        }
        let model = SplitChooser(tabs: tabs, current: tabWindows.firstIndex(of: window) ?? 0)
        switch model.outcome {
        case .newViewOfCurrentBook:
            Task { [weak self] in
                guard let self else { return }
                let place = await reader.currentPlace()
                guard !isSplit, let document = document as? BookDocument,
                      let guest = document.makeView(place.map { .place($0) } ?? .saved) else { return }
                showInSplit(guest)
                splitGuestIsOwned = true
            }
        case .tab(let index):
            guard let guest = tabWindows[index].windowController as? ReaderWindowController else { return }
            showInSplit(guest)
        case .chooser:
            showChooser(model.candidates.map { tabWindows[$0] }, preselected: model.preselected ?? 0)
        }
    }

    private func showChooser(_ candidates: [NSWindow], preselected: Int) {
        guard let window else { return }
        chooserTabs = candidates
        let chooser = SplitChooserViewController(titles: candidates.map(\.title), preselected: preselected)
        chooser.onPick = { [weak self] row in self?.pickFromChooser(row) }
        chooser.onCancel = { [weak self] in self?.endSplit() }
        let item = NSSplitViewItem(viewController: chooser)
        item.minimumThickness = 220
        splitViewController.addSplitViewItem(item)
        splitItem = item
        self.chooser = chooser
        equalizeHalves()
        window.makeFirstResponder(chooser.tableView)
        updateToolbar()
    }

    private func pickFromChooser(_ row: Int) {
        guard chooserTabs.indices.contains(row),
              let guest = chooserTabs[row].windowController as? ReaderWindowController, guest !== self else { return }
        showInSplit(guest)
    }

    private func removeChooser() {
        guard chooser != nil, let item = splitItem else { return }
        splitViewController.removeSplitViewItem(item)
        splitItem = nil
        chooser = nil
        chooserTabs = []
    }

    private func showInSplit(_ guest: ReaderWindowController) {
        guard let window, splitGuest == nil else { return }
        removeChooser()
        guest.leaveForSplit(in: self)
        splitGuest = guest
        let item = NSSplitViewItem(viewController: guest.reader)
        item.minimumThickness = 220
        splitViewController.addSplitViewItem(item)
        splitItem = item
        equalizeHalves()
        window.makeFirstResponder(guest.reader.webView)
        updateToolbar()
    }

    private func endSplit() {
        guard let window else { return }
        if chooser != nil {
            removeChooser()
        } else if let guest = splitGuest, let item = splitItem {
            splitViewController.removeSplitViewItem(item)
            splitItem = nil
            splitGuest = nil
            if splitGuestIsOwned {
                splitGuestIsOwned = false
                guest.close()
            } else {
                guest.returnFromSplit(besides: window)
            }
            // This tab stays the one in front.
            window.tabGroup?.selectedWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        window.makeFirstResponder(reader.webView)
        updateToolbar()
    }

    /// The guest side: the reader moves to the host's right half; this window leaves the tab
    /// bar, noting its neighbours.
    private func leaveForSplit(in host: ReaderWindowController) {
        splitHost = host
        picker.dismiss()
        splitViewController.removeSplitViewItem(readerItem)
        guard let window else { return }
        let tabs = window.tabbedWindows ?? []
        if let index = tabs.firstIndex(of: window) {
            tabBefore = index > 0 ? tabs[index - 1] : nil
            tabAfter = index + 1 < tabs.count ? tabs[index + 1] : nil
        }
        window.tabGroup?.removeWindow(window)
        window.orderOut(nil)
    }

    /// The reader comes back, and the window goes back in the tab bar where it was (beside its
    /// old neighbours, else beside `host`), or on its own at `fallbackFrame` when there is no tab
    /// bar to go back to (the split's window is closing alone).
    private func returnFromSplit(besides host: NSWindow?, fallbackFrame: NSRect? = nil) {
        splitHost = nil
        splitViewController.addSplitViewItem(readerItem)
        guard let window else { return }
        // A tab that is not the selected one is not "visible" to AppKit: the group says it is open.
        let group = host?.tabGroup
        if let before = tabBefore, group != nil, before.tabGroup === group {
            before.addTabbedWindow(window, ordered: .above)
        } else if let after = tabAfter, group != nil, after.tabGroup === group {
            after.addTabbedWindow(window, ordered: .below)
        } else if let host, host.isVisible {
            host.addTabbedWindow(window, ordered: .above)
        } else {
            if let frame = fallbackFrame ?? host?.frame { window.setFrame(frame, display: false) }
            window.makeKeyAndOrderFront(nil)
        }
        tabBefore = nil
        tabAfter = nil
        window.makeFirstResponder(reader.webView)
    }

    /// The two halves equal, the sidebar left as it is.
    private func equalizeHalves() {
        let split = splitViewController.splitView
        split.layoutSubtreeIfNeeded()
        let count = splitViewController.splitViewItems.count
        guard count >= 3 else { return }
        let left = sidebarItem.isCollapsed ? 0 : sidebar.view.frame.maxX + split.dividerThickness
        split.setPosition(left + (split.bounds.width - left) / 2, ofDividerAt: count - 2)
    }

    /// The reader the keys act on: the right half's when the focus is there.
    private var focusedReader: ReaderViewController {
        if let guest = splitGuest, let view = window?.firstResponder as? NSView, view.isDescendant(of: guest.reader.view) {
            return guest.reader
        }
        return reader
    }

    /// For `ReaderSmokeTest`.
    var smokeSplit: [String: Any] {
        ["isSplit": isSplit, "items": splitViewController.splitViewItems.count, "chooser": chooser != nil,
         "chooserRows": chooser?.smokeRows ?? [], "chooserSelected": chooser?.tableView.selectedRow ?? -1,
         "guestIsOwned": splitGuestIsOwned, "guestPath": splitGuest?.reader.currentPath ?? "",
         "guestIsSameDocument": splitGuest.map { $0.document === document } ?? false]
    }
    var smokeChooser: SplitChooserViewController? { chooser }

    // MARK: Actions (window-specific; global ones live in AppDelegate)

    /// `⌘T` and the tab bar's + button: an empty tab.
    override func newWindowForTab(_ sender: Any?) {
        EmptyReaderWindowController.openNewTab(besides: window)
    }

    /// `⌘R`: the chapter again from the book and the style from disk, at the same place.
    /// (Not `reload(_:)`: the web view, first in the responder chain, would take that one.)
    @objc func reloadPage(_ sender: Any?) { focusedReader.reload() }

    @objc func goToPreviousChapter(_ sender: Any?) { focusedReader.goToPreviousChapter() }
    @objc func goToNextChapter(_ sender: Any?) { focusedReader.goToNextChapter() }

    /// `⌘←` (`⌘[`): back to where the last link was followed, at the exact position.
    @objc func goBackInHistory(_ sender: Any?) { focusedReader.goBack() }
    /// `⌘→` (`⌘]`).
    @objc func goForwardInHistory(_ sender: Any?) { focusedReader.goForward() }

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
        let inspector = inspector ?? InspectorWindowController(
            publication: reader.publication,
            title: BookTitle.display(title: reader.book.title, fileURL: (document as? NSDocument)?.fileURL)
                ?? (document as? NSDocument)?.displayName ?? "")
        self.inspector = inspector
        inspector.showWindow(nil)
    }

    /// For `ReaderSmokeTest`.
    var smokeInspectorWindow: NSWindow? { inspector?.window }

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

    /// `⌘G` / `⇧⌘G`: the next or previous search result, in whatever chapter it is; with no
    /// results yet, the search pane with the cursor in its field.
    @objc func findNextMatch(_ sender: Any?) { findAdjacentMatch(1) }
    @objc func findPreviousMatch(_ sender: Any?) { findAdjacentMatch(-1) }

    private func findAdjacentMatch(_ step: Int) {
        if search.showAdjacentHit(step) { return }
        showSearch(nil)
    }

    private func show(_ pane: SidebarPane) {
        guard pane.isAvailable, !isMinimal else { NSSound.beep(); return }
        sidebar.select(pane)
        rememberPane(pane)
        if sidebarItem.isCollapsed { sidebarItem.animator().isCollapsed = false }
    }

    /// For `ScreenshotSession`: the page alone, the sidebar closed at once.
    func hideSidebarForScreenshot() {
        sidebarItem.isCollapsed = true
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
        // Every view of the book shows the same bookmarks, this one included.
        NotificationCenter.default.post(name: .readerBookStateDidChange, object: nil, userInfo: ["bookKey": reader.bookKey])
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

    /// Keys handled outside the menu bar: plain `←` `→` `+` `-` `0` `T` while reading, the
    /// style list shortcuts, whose hold-to-cycle behaviour needs key-up and modifier tracking,
    /// and the keys and scrolling that push past the edge of a chapter (seen, not consumed,
    /// unless they take the reader to another chapter).
    func handle(_ event: NSEvent) -> Bool {
        if event.type == .scrollWheel {
            guard event.window === window else { return false }
            let halves = [reader] + (splitGuest.map { [$0.reader] } ?? [])
            guard let target = halves.first(where: { $0.view.bounds.contains($0.view.convert(event.locationInWindow, from: nil)) }) else { return false }
            return target.handleEdgeScroll(event)
        }
        if picker.handle(event) { return true }
        guard event.type == .keyDown, let window else { return false }

        // ⌘S: the split view. The menu has ⌘S twice (Save is the Playground's), so the reader
        // takes it here, before the menu bar; this monitor only sees reader windows.
        if !event.isARepeat, Shortcuts.matches(Shortcuts.shortcut(.split), characters: event.charactersIgnoringModifiers ?? "",
                                               modifiers: KeyShortcut.Modifiers(event.modifierFlags)) {
            toggleSplit(nil)
            return true
        }

        if StylePicker.isPickerShortcut(event) {
            picker.show(over: window, heldModifier: .command)
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if isReadingFocused, !event.isARepeat, let direction = Self.edgeDirection(keyCode: event.keyCode, flags: flags),
           focusedReader.handleEdgeKey(direction) {
            return true
        }
        // `⌘←` `⌘→` while reading: the history, before the web view can take them for the page.
        if flags == [.command], isReadingFocused {
            switch event.keyCode {
            case KeyCode.leftArrow where focusedReader.canGoBack: focusedReader.goBack(); return true
            case KeyCode.rightArrow where focusedReader.canGoForward: focusedReader.goForward(); return true
            default: break
            }
        }
        guard flags.isEmpty, isReadingFocused else { return false }
        switch event.keyCode {
        case KeyCode.leftArrow: focusedReader.goToPreviousChapter(); return true
        case KeyCode.rightArrow: focusedReader.goToNextChapter(); return true
        default: break
        }
        let action: Selector
        switch Shortcuts.readingCommand(characters: event.charactersIgnoringModifiers ?? "") {
        // Held down, T would flicker between light and dark: once per press.
        case .night?: guard !event.isARepeat else { return true }; action = #selector(AppDelegate.toggleNight(_:))
        case .larger?: action = #selector(AppDelegate.increaseTextSize(_:))
        case .smaller?: action = #selector(AppDelegate.decreaseTextSize(_:))
        case .actualSize?: action = #selector(AppDelegate.resetTextSize(_:))
        default: return false
        }
        NSApp.sendAction(action, to: nil, from: self)
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
        guard let view = responder as? NSView else { return false }
        return view.isDescendant(of: reader.webView) || splitGuest.map { view.isDescendant(of: $0.reader.webView) } == true
    }

    private var isEditingText: Bool { window?.firstResponder is NSText }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        // `←` `→` are plain-key shortcuts: disabled while typing, so text fields get them.
        case #selector(goToPreviousChapter(_:)): return focusedReader.canGoToPreviousChapter && !isEditingText
        case #selector(goToNextChapter(_:)): return focusedReader.canGoToNextChapter && !isEditingText
        case #selector(toggleMinimalMode(_:)):
            menuItem.state = isMinimal ? .on : .off
            return true
        case #selector(showStyleList(_:)): return !environment.styles.isEmpty
        case #selector(showSidebarPane(_:)):
            let pane = SidebarPane.allCases.first { $0.shortcutDigit == menuItem.tag }
            menuItem.state = !sidebarItem.isCollapsed && pane == sidebar.pane ? .on : .off
            return pane?.isAvailable == true && !isMinimal
        case #selector(showSearch(_:)): return !isMinimal
        case #selector(findNextMatch(_:)), #selector(findPreviousMatch(_:)): return search.hasResults || !isMinimal
        // `⌘←` `⌘→` move the cursor in text fields: off while typing.
        case #selector(goBackInHistory(_:)): return focusedReader.canGoBack && !isEditingText
        case #selector(goForwardInHistory(_:)): return focusedReader.canGoForward && !isEditingText
        case #selector(addBookmark(_:)): return reader.currentSpineIndex != nil
        case #selector(toggleSplit(_:)):
            menuItem.state = isSplit ? .on : .off
            return isSplit || (splitHost == nil && !isMinimal)
        default: return true
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, ToolbarID.chapters, ToolbarID.info, ToolbarID.split, .flexibleSpace]
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
        case ToolbarID.split:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("toolbar.split")
            item.toolTip = L10n.string("toolbar.split.help")
            item.action = #selector(toggleSplit(_:))
            item.target = self
            item.isBordered = true
            splitToolbarItem = item
            updateToolbar()
            return item
        default:
            return globalItems.item(for: identifier)
        }
    }

    private func updateToolbar() {
        chaptersItem?.subitems.first?.isEnabled = reader.canGoToPreviousChapter
        chaptersItem?.subitems.last?.isEnabled = reader.canGoToNextChapter
        splitToolbarItem?.image = Self.symbol(isSplit ? "rectangle.split.2x1.fill" : "rectangle.split.2x1",
                                              L10n.string(isSplit ? "a11y.split.on" : "a11y.split.off"))
        globalItems.update()
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        GlobalToolbarItems.symbol(name, description)
    }

    // MARK: Window delegate

    func windowWillClose(_ notification: Notification) {
        // The right half's tab stays open: back in the tab bar, or in a window of its own where
        // this one was.
        if let guest = splitGuest, let item = splitItem {
            splitViewController.removeSplitViewItem(item)
            splitItem = nil
            splitGuest = nil
            if splitGuestIsOwned {
                splitGuestIsOwned = false
                guest.close()
            } else {
                let others = window?.tabbedWindows?.filter { $0 !== window && $0.isVisible } ?? []
                guest.returnFromSplit(besides: others.first, fallbackFrame: window?.frame)
            }
        }
        picker.dismiss()
        inspector?.close()
        if let environmentObserver { NotificationCenter.default.removeObserver(environmentObserver) }
        environmentObserver = nil
        if let bookStateObserver { NotificationCenter.default.removeObserver(bookStateObserver) }
        bookStateObserver = nil
        environment.saveStateNow()
    }
}
