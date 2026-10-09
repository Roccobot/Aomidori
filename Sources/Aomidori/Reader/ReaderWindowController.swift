import AppKit
import EPUBKit

/// One window per open book: a sidebar with the table of contents and the reading view.
@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSMenuItemValidation, ReaderViewControllerDelegate {

    private enum ToolbarID {
        static let chapters = NSToolbarItem.Identifier("Aomidori.chapters")
        static let night = NSToolbarItem.Identifier("Aomidori.night")
        static let style = NSToolbarItem.Identifier("Aomidori.style")
        static let override = NSToolbarItem.Identifier("Aomidori.override")
    }

    let reader: ReaderViewController
    private let toc: TOCViewController
    private let splitViewController = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let picker = StylePicker()
    private let environment = ReaderEnvironment.shared
    private let styleMenuUpdater = StyleMenuUpdater()
    private var chaptersItem: NSToolbarItemGroup?
    private var nightItem: NSToolbarItem?
    private var overrideItem: NSToolbarItem?
    private var environmentObserver: (any NSObjectProtocol)?
    private var isMinimal = false
    private var sidebarWasCollapsed = true

    init(publication: EPUBPublication, bookKey: String) {
        reader = ReaderViewController(publication: publication, bookKey: bookKey)
        toc = TOCViewController(entries: publication.book.toc)
        sidebarItem = NSSplitViewItem(sidebarWithViewController: toc)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        super.init(window: window)

        sidebarItem.isCollapsed = true
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 420
        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: reader))

        window.contentViewController = splitViewController
        window.setContentSize(NSSize(width: 860, height: 980))
        window.minSize = NSSize(width: 420, height: 320)
        window.toolbarStyle = .unified
        window.tabbingIdentifier = "AomidoriReader"
        window.delegate = self
        window.isRestorable = false
        window.setFrameAutosaveName("AomidoriReaderWindow")

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

        environmentObserver = NotificationCenter.default.addObserver(forName: .readerEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentDidChange() }
        }

        applyAppearance()
        if environment.prefersMinimal { setMinimal(true) }
        reader.start()
        window.makeFirstResponder(reader.webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

    @objc func goToPreviousChapter(_ sender: Any?) { reader.goToPreviousChapter() }
    @objc func goToNextChapter(_ sender: Any?) { reader.goToNextChapter() }

    @objc func showStyleList(_ sender: Any?) {
        guard let window else { return }
        picker.show(over: window, heldModifier: nil)
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

    /// Keys handled outside the menu bar: plain `←` `→` `+` `-` `0` while reading, and the
    /// style list shortcuts, whose hold-to-cycle behaviour needs key-up and modifier tracking.
    func handle(_ event: NSEvent) -> Bool {
        if picker.handle(event) { return true }
        guard event.type == .keyDown, let window else { return false }

        if StylePicker.isPickerShortcut(event) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            picker.show(over: window, heldModifier: flags.contains(.command) ? .command : .control)
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
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

    /// Whether keystrokes are meant for the page (not the table of contents).
    private var isReadingFocused: Bool {
        guard let responder = window?.firstResponder else { return false }
        if responder === window { return true }
        return (responder as? NSView)?.isDescendant(of: reader.webView) ?? false
    }

    // MARK: Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goToPreviousChapter(_:)): return reader.canGoToPreviousChapter
        case #selector(goToNextChapter(_:)): return reader.canGoToNextChapter
        case #selector(toggleMinimalMode(_:)):
            menuItem.state = isMinimal ? .on : .off
            return true
        case #selector(showStyleList(_:)): return !environment.styles.isEmpty
        default: return true
        }
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, ToolbarID.chapters, .flexibleSpace,
         ToolbarID.night, ToolbarID.style, ToolbarID.override]
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
                images: [Self.symbol("chevron.left", "Capitolo precedente"), Self.symbol("chevron.right", "Capitolo successivo")],
                selectionMode: .momentary,
                labels: ["Precedente", "Successivo"],
                target: self,
                action: #selector(chapterGroupClicked(_:))
            )
            group.label = "Capitoli"
            group.toolTip = "Capitolo precedente / successivo (\u{2190} \u{2192})"
            group.isNavigational = true
            group.autovalidates = false
            group.subitems.forEach { $0.autovalidates = false }
            chaptersItem = group
            updateToolbar()
            return group
        case ToolbarID.night:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Giorno/Notte"
            item.toolTip = "Giorno/Notte (\u{21E7}\u{2318}N)"
            item.action = #selector(AppDelegate.toggleNight(_:))
            item.isBordered = true
            nightItem = item
            updateToolbar()
            return item
        case ToolbarID.style:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = "Stile"
            item.toolTip = "Stile"
            item.image = Self.symbol("textformat", "Stile")
            let menu = NSMenu(title: "Stile")
            menu.delegate = styleMenuUpdater
            menu.addItem(withTitle: "Elenco stili\u{2026}", action: #selector(showStyleList(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Mostra cartella stili", action: #selector(AppDelegate.showStylesFolder(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            StyleMenu.refresh(menu)
            item.menu = menu
            return item
        case ToolbarID.override:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Sovrascrivi stile"
            item.toolTip = "Sovrascrivi lo stile del libro (\u{2318}.)"
            item.action = #selector(AppDelegate.toggleStyleOverride(_:))
            item.isBordered = true
            overrideItem = item
            updateToolbar()
            return item
        default:
            return nil
        }
    }

    private func updateToolbar() {
        chaptersItem?.subitems.first?.isEnabled = reader.canGoToPreviousChapter
        chaptersItem?.subitems.last?.isEnabled = reader.canGoToNextChapter
        let night = environment.isNight
        nightItem?.image = Self.symbol(night ? "moon.fill" : "sun.max", night ? "Notte" : "Giorno")
        let overriding = environment.overrideEnabled
        overrideItem?.image = Self.symbol(overriding ? "paintbrush.pointed.fill" : "paintbrush.pointed",
                                          overriding ? "Stile sovrascritto" : "Stile del libro")
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }

    // MARK: Window delegate

    func windowWillClose(_ notification: Notification) {
        picker.dismiss()
        if let environmentObserver { NotificationCenter.default.removeObserver(environmentObserver) }
        environmentObserver = nil
        environment.savePositionsNow()
    }
}
