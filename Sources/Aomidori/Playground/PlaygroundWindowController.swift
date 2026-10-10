import AppKit
import AomidoriCore
import EPUBKit
import UniformTypeIdentifiers

/// The CSS Playground: a live preview (left half) of the CSS being edited (right half), with
/// the styles folder listed below the editor.
///
/// Styles are never modified on disk by editing: the editor works on a volatile copy that the
/// preview reads from memory (`PlaygroundStyleStore`). Only *Save to Styles* and *Save As…*
/// write files. The preview applies the CSS exactly as a reader window does with the style
/// override on: the book's own CSS is removed and the edited CSS applied, with the reader's
/// text size and Night palette. The custom font is left out, so `font-family` edits show.
@MainActor
final class PlaygroundWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
    NSMenuItemValidation, NSTableViewDataSource, NSTableViewDelegate {

    /// Where the editor's text came from.
    enum Origin: Equatable {
        /// A file in the styles folder, by name.
        case style(String)
        /// A file opened from elsewhere.
        case external(URL)

        var displayName: String {
            switch self {
            case .style(let name): name
            case .external(let url): url.lastPathComponent
            }
        }

        var fileURL: URL {
            switch self {
            case .style(let name): AppPaths.styles.appendingPathComponent(name)
            case .external(let url): url
            }
        }
    }

    private enum ToolbarID {
        static let chapters = NSToolbarItem.Identifier("Aomidori.playground.chapters")
        static let source = NSToolbarItem.Identifier("Aomidori.playground.source")
        static let night = NSToolbarItem.Identifier("Aomidori.playground.night")
        static let save = NSToolbarItem.Identifier("Aomidori.playground.save")
    }

    /// Preview updates wait for a pause in typing.
    static let previewDelay = Duration.milliseconds(100)

    private let environment = ReaderEnvironment.shared
    private let editor = CodeEditor()
    private let preview: PlaygroundPreviewController
    private let styleTable = NSTableView()
    private let originLabel = NSTextField(labelWithString: "")
    private var styles: [StyleFile] = []
    private(set) var origin: Origin?
    /// The text as last loaded or saved: the buffer is dirty when it differs.
    private var savedText = ""
    private(set) var isDirty = false
    private var night: Bool
    private let bufferName = PlaygroundStyleStore.shared.makeFileName()
    private var revision = 0
    private var handlesColorScheme = false
    private var previewTask: Task<Void, Never>?
    private var environmentObserver: (any NSObjectProtocol)?
    private var chaptersItem: NSToolbarItemGroup?
    private var nightItem: NSToolbarItem?
    private var isSelectingProgrammatically = false
    private var isClosingConfirmed = false

    init() {
        night = ReaderEnvironment.shared.isNight
        preview = PlaygroundPreviewController(configuration: ReaderConfiguration(overrideEnabled: true), night: night)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        super.init(window: window)

        window.title = L10n.string("playground.title")
        window.minSize = NSSize(width: 760, height: 480)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.contentView = makeContent()
        window.setFrameAutosaveName("AomidoriPlaygroundWindow")
        if !window.setFrameUsingName("AomidoriPlaygroundWindow") { window.center() }

        let toolbar = NSToolbar(identifier: "AomidoriPlaygroundToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        editor.onChange = { [weak self] in self?.textDidChange() }
        preview.onNavigate = { [weak self] in self?.updateChrome() }
        preview.onLoad = { [weak self] in self?.previewDidLoad() }

        environmentObserver = NotificationCenter.default.addObserver(
            forName: .readerEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.environmentDidChange() }
        }

        reloadStyleList()
        loadDefaultStyle()
        preview.load()
        smokeTest?.log("playground opened, \(styles.count) styles, origin \(origin?.displayName ?? "none")")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Layout

    /// Preview: left half, full height. Editor: right half, 90 % of the height. Style list
    /// and Open button: below the editor.
    private func makeContent() -> NSView {
        let content = NSView()
        let previewView = preview.view
        let editorView = editor.scrollView
        let divider = NSBox()
        divider.boxType = .separator
        let panel = makeStylePanel()
        for view in [previewView, divider, editorView, panel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        let editorHeight = editorView.heightAnchor.constraint(equalTo: content.heightAnchor, multiplier: 0.9)
        editorHeight.priority = .defaultHigh
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            previewView.topAnchor.constraint(equalTo: content.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            previewView.widthAnchor.constraint(equalTo: content.widthAnchor, multiplier: 0.5),

            divider.leadingAnchor.constraint(equalTo: previewView.trailingAnchor),
            divider.topAnchor.constraint(equalTo: content.topAnchor),
            divider.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            editorView.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            editorView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            editorView.topAnchor.constraint(equalTo: content.topAnchor),
            editorHeight,

            panel.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            panel.topAnchor.constraint(equalTo: editorView.bottomAnchor),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            panel.heightAnchor.constraint(greaterThanOrEqualToConstant: 76),
        ])
        return content
    }

    private func makeStylePanel() -> NSView {
        let panel = NSView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("style"))
        column.title = L10n.string("playground.styles")
        styleTable.addTableColumn(column)
        styleTable.headerView = nil
        styleTable.style = .plain
        styleTable.rowSizeStyle = .small
        styleTable.usesAlternatingRowBackgroundColors = false
        styleTable.allowsEmptySelection = true
        styleTable.dataSource = self
        styleTable.delegate = self
        styleTable.target = self
        styleTable.doubleAction = #selector(styleDoubleClicked(_:))
        styleTable.setAccessibilityLabel(L10n.string("playground.styles"))
        styleTable.toolTip = L10n.string("playground.styles.help")

        let scroll = NSScrollView()
        scroll.documentView = styleTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false

        let open = NSButton(title: L10n.string("playground.open"), target: self, action: #selector(openCSSFile(_:)))
        open.bezelStyle = .push
        open.controlSize = .small
        open.toolTip = L10n.string("playground.open.help")

        originLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        originLabel.textColor = .secondaryLabelColor
        originLabel.lineBreakMode = .byTruncatingMiddle
        originLabel.maximumNumberOfLines = 2

        for view in [scroll, open, originLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 6),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -4),
            open.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 10),
            open.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            open.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            open.widthAnchor.constraint(greaterThanOrEqualToConstant: 110),
            originLabel.leadingAnchor.constraint(equalTo: open.leadingAnchor),
            originLabel.trailingAnchor.constraint(equalTo: open.trailingAnchor),
            originLabel.topAnchor.constraint(equalTo: open.bottomAnchor, constant: 4),
        ])
        return panel
    }

    // MARK: Loading styles

    private func loadDefaultStyle() {
        let name = environment.defaultStyleName
        if let style = styles.first(where: { $0.name == name }) ?? styles.first,
           let text = environment.library.contents(of: style) {
            load(text, from: .style(style.name))
        } else if let bundled = AppPaths.bundledStyle, let data = try? Data(contentsOf: bundled), let text = CSSFile.text(from: data) {
            load(text, from: .external(bundled))
        } else {
            load("", from: .style(AppPaths.bundledStyleName))
        }
    }

    private func load(_ text: String, from origin: Origin) {
        self.origin = origin
        savedText = text
        editor.setText(text, fileExtension: origin.fileURL.pathExtension)
        setDirty(false)
        updateStyleSelection()
        updatePreviewNow()
        updateChrome()
    }

    /// Loads a file from the styles folder, asking first if the buffer has changes.
    private func switchToStyle(_ style: StyleFile) {
        guard origin != .style(style.name) || isDirty else { return }
        reviewUnsavedChanges { [weak self] proceed in
            guard proceed, let self else { return }
            guard let text = environment.library.contents(of: style) else {
                presentFileError(L10n.format("playground.error.read", style.name))
                return
            }
            load(text, from: .style(style.name))
        }
    }

    private func reloadStyleList() {
        styles = environment.library.styles()
        isSelectingProgrammatically = true
        styleTable.reloadData()
        isSelectingProgrammatically = false
        updateStyleSelection()
    }

    /// The list always shows the style the editor holds as selected (none for other files).
    private func updateStyleSelection() {
        isSelectingProgrammatically = true
        defer { isSelectingProgrammatically = false }
        if case .style(let name)? = origin, let row = styles.firstIndex(where: { $0.name == name }) {
            styleTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            styleTable.scrollRowToVisible(row)
        } else {
            styleTable.deselectAll(nil)
        }
    }

    // MARK: Editing and preview

    private func textDidChange() {
        setDirty(editor.text != savedText)
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: Self.previewDelay)
            guard !Task.isCancelled else { return }
            self?.updatePreviewNow()
        }
    }

    private func updatePreviewNow() {
        previewTask?.cancel()
        let text = editor.text
        PlaygroundStyleStore.shared.set(text, for: bufferName)
        handlesColorScheme = environment.library.handlesColorScheme(css: text)
        revision += 1
        preview.configuration = configuration()
    }

    private func configuration() -> ReaderConfiguration {
        ReaderConfiguration(
            overrideEnabled: true,
            styleHref: "/\(PageSchemeHandler.userPrefix)Styles/\(bufferName)?v=\(revision)",
            styleHandlesColorScheme: handlesColorScheme,
            night: night,
            nightPaletteCSS: environment.nightPaletteCSS,
            scale: environment.textScale
        )
    }

    private func setDirty(_ dirty: Bool) {
        isDirty = dirty
        window?.isDocumentEdited = dirty
        updateOriginLabel()
    }

    private func environmentDidChange() {
        let names = environment.library.styles().map(\.name)
        if names != styles.map(\.name) { reloadStyleList() }
        // Text size and the Night palette follow the reader; `@import`ed files may have changed.
        updatePreviewNow()
    }

    private func previewDidLoad() {
        updateChrome()
        smokeTest?.previewDidLoad()
    }

    // MARK: Chrome

    private func updateChrome() {
        var parts: [String] = []
        if let origin { parts.append(origin.displayName) }
        switch preview.source {
        case .sample: parts.append(L10n.string("playground.sample"))
        case .book(_, let title): parts.append([title, preview.chapterLabel].compactMap { $0 }.joined(separator: " · "))
        }
        window?.subtitle = parts.joined(separator: " — ")
        window?.representedURL = origin?.fileURL
        chaptersItem?.subitems.first?.isEnabled = preview.canGoToPreviousChapter
        chaptersItem?.subitems.last?.isEnabled = preview.canGoToNextChapter
        nightItem?.image = Self.symbol(night ? "moon.fill" : "sun.max", L10n.string(night ? "a11y.night" : "a11y.day"))
        updateOriginLabel()
    }

    private func updateOriginLabel() {
        var text: String
        switch origin {
        case .external(let url)?: text = L10n.format("playground.origin.external", url.lastPathComponent)
        case .style(let name)?: text = name
        case nil: text = ""
        }
        if isDirty { text = L10n.format("playground.origin.edited", text) }
        originLabel.stringValue = text
        originLabel.toolTip = origin?.fileURL.path
    }

    // MARK: Actions

    /// `⇧⌘O` and the Open button: loads a CSS file from anywhere (it is not modified).
    @objc func openCSSFile(_ sender: Any?) {
        guard let window else { return }
        reviewUnsavedChanges { [weak self] proceed in
            guard proceed, let self else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [Self.cssType]
            panel.allowsMultipleSelection = false
            panel.message = L10n.string("playground.open.message")
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK, let url = panel.url, let self else { return }
                guard let data = try? Data(contentsOf: url), let text = CSSFile.text(from: data) else {
                    presentFileError(L10n.format("playground.error.read", url.lastPathComponent))
                    return
                }
                // A file inside the styles folder is that style.
                let inStyles = url.deletingLastPathComponent().standardizedFileURL.path == AppPaths.styles.standardizedFileURL.path
                load(text, from: inStyles ? .style(url.lastPathComponent) : .external(url))
            }
        }
    }

    /// `⌥⌘O`: previews the chapters of a real book instead of the sample.
    @objc func loadPlaygroundEPUB(_ sender: Any?) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(importedAs: "org.idpf.epub-container")]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.loadEPUB(at: url)
        }
    }

    func loadEPUB(at url: URL) {
        do {
            let publication = try EPUBPublication(contentsOf: url)
            preview.show(.book(publication, title: publication.book.title ?? url.deletingPathExtension().lastPathComponent))
        } catch let error as EPUBError {
            window.map { error.userFacingError(isComic: false).presentAsSheet(on: $0) }
        } catch {
            window.map { (error as NSError).presentAsSheet(on: $0) }
        }
    }

    /// `⇧⌘E`: back to the bundled sample text.
    @objc func showSampleText(_ sender: Any?) {
        preview.show(.sample)
    }

    /// `⇧⌘N` while the Playground is in front: its own Day/Night, independent of the reader's.
    @objc func toggleNight(_ sender: Any?) {
        night.toggle()
        preview.night = night
        updatePreviewNow()
        updateChrome()
    }

    @objc func goToPreviousChapter(_ sender: Any?) { preview.goToPreviousChapter() }
    @objc func goToNextChapter(_ sender: Any?) { preview.goToNextChapter() }

    @objc private func chapterGroupClicked(_ sender: NSToolbarItemGroup) {
        if sender.selectedIndex == 0 { preview.goToPreviousChapter() } else { preview.goToNextChapter() }
    }

    /// `⌘F`: the editor's find bar.
    @objc func showSearch(_ sender: Any?) {
        window?.makeFirstResponder(editor.textView)
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        editor.textView.performTextFinderAction(item)
    }

    /// `⌘G` / `⇧⌘G`: the editor's next or previous match (the reader's selectors, so one menu
    /// item serves both windows).
    @objc func findNextMatch(_ sender: Any?) { performEditorFind(.nextMatch) }
    @objc func findPreviousMatch(_ sender: Any?) { performEditorFind(.previousMatch) }

    private func performEditorFind(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        editor.textView.performTextFinderAction(item)
    }

    @objc private func styleDoubleClicked(_ sender: NSTableView) {
        guard styles.indices.contains(sender.clickedRow) else { return }
        switchToStyle(styles[sender.clickedRow])
    }

    // MARK: Saving

    /// `⌘S`: saves into the styles folder under a name (asking before replacing a file), so the
    /// style is at once in the reader's list and live in reader windows using it.
    @objc func saveToStyles(_ sender: Any?) {
        saveToStyles(completion: nil)
    }

    private func saveToStyles(completion: (@MainActor (Bool) -> Void)?) {
        guard let window else { completion?(false); return }
        let field = NSTextField(string: suggestedName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        let alert = NSAlert()
        alert.messageText = L10n.string("playground.saveToStyles.title")
        alert.informativeText = L10n.string("playground.saveToStyles.message")
        alert.accessoryView = field
        alert.addButton(withTitle: L10n.string("playground.save"))
        alert.addButton(withTitle: L10n.string("playground.cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { completion?(false); return }
            let plan = environment.library.savePlan(forName: field.stringValue)
            guard plan.replacesExisting else {
                completion?(writeToStyles(named: plan.fileName, overwrite: false))
                return
            }
            // The first sheet must be gone before the next one starts.
            Task { @MainActor in
                self.confirmReplace(plan.fileName) { replace in
                    completion?(replace && self.writeToStyles(named: plan.fileName, overwrite: true))
                }
            }
        }
    }

    private var suggestedName: String {
        guard let origin else { return environment.library.availableName(for: L10n.string("playground.untitled")) }
        return (origin.displayName as NSString).deletingPathExtension
    }

    private func confirmReplace(_ fileName: String, completion: @escaping @MainActor (Bool) -> Void) {
        guard let window else { completion(false); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.format("playground.replace.title", fileName)
        alert.informativeText = L10n.string("playground.replace.message")
        alert.addButton(withTitle: L10n.string("playground.replace"))
        alert.addButton(withTitle: L10n.string("playground.cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { completion($0 == .alertFirstButtonReturn) }
    }

    /// Writes the buffer into the styles folder; it becomes the selected, clean style.
    @discardableResult
    func writeToStyles(named name: String, overwrite: Bool) -> Bool {
        let text = editor.text
        do {
            let saved = try environment.library.save(css: text, named: name, overwrite: overwrite)
            origin = .style(saved.name)
            savedText = text
            setDirty(false)
            reloadStyleList()
            updateChrome()
            return true
        } catch {
            window.map { (error as NSError).presentAsSheet(on: $0) }
            return false
        }
    }

    /// `⇧⌘S`: writes a `.css` file anywhere (UTF-8 without BOM, LF, final newline).
    @objc func saveCSSAs(_ sender: Any?) {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.cssType]
        panel.nameFieldStringValue = (suggestedName as NSString).appendingPathExtension("css") ?? "Style.css"
        if case .external(let url)? = origin { panel.directoryURL = url.deletingLastPathComponent() }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let text = editor.text
            do {
                try CSSFile.data(for: text).write(to: url, options: .atomic)
                let inStyles = url.deletingLastPathComponent().standardizedFileURL.path == AppPaths.styles.standardizedFileURL.path
                origin = inStyles ? .style(url.lastPathComponent) : .external(url)
                savedText = text
                setDirty(false)
                reloadStyleList()
                updateChrome()
            } catch {
                (error as NSError).presentAsSheet(on: window)
            }
        }
    }

    // MARK: Unsaved changes

    /// Asks what to do with unsaved changes (save to Styles, discard, cancel) before they would
    /// be lost; calls back with `true` when it is fine to go on. No question if nothing changed.
    func reviewUnsavedChanges(_ completion: @escaping @MainActor (Bool) -> Void) {
        guard isDirty, let window else { completion(true); return }
        showWindow(nil)
        let alert = NSAlert()
        alert.messageText = L10n.format("playground.unsaved.title", origin?.displayName ?? L10n.string("playground.untitled"))
        alert.informativeText = L10n.string("playground.unsaved.message")
        alert.addButton(withTitle: L10n.string("playground.saveToStyles"))
        alert.addButton(withTitle: L10n.string("playground.cancel"))
        let discard = alert.addButton(withTitle: L10n.string("playground.discard"))
        discard.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            switch response {
            case .alertFirstButtonReturn:
                Task { @MainActor in self?.saveToStyles(completion: completion) }
            case .alertThirdButtonReturn:
                completion(true)
            default:
                completion(false)
            }
        }
    }

    // MARK: Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingConfirmed || !isDirty { return true }
        reviewUnsavedChanges { [weak self] proceed in
            guard proceed, let self else { return }
            isClosingConfirmed = true
            window?.close()
            isClosingConfirmed = false
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // Changes were saved or discarded: the next opening starts from the file again.
        if isDirty, let origin { load(savedText, from: origin) }
    }

    // MARK: Validation

    private var isEditingText: Bool { window?.firstResponder is NSText }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goToPreviousChapter(_:)): return preview.canGoToPreviousChapter && !isEditingText
        case #selector(goToNextChapter(_:)): return preview.canGoToNextChapter && !isEditingText
        case #selector(toggleNight(_:)):
            menuItem.state = night ? .on : .off
            return true
        case #selector(showSampleText(_:)):
            if case .sample = preview.source { return false }
            return true
        default:
            return true
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { styles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("StyleCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        cell.textField?.stringValue = styles[row].name
        return cell
    }

    /// Clicks do not move the selection: it marks the style shown in the editor, and a
    /// double-click loads another one.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        isSelectingProgrammatically
    }

    // MARK: Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.chapters, ToolbarID.source, .flexibleSpace, ToolbarID.night, ToolbarID.save]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
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
            updateChrome()
            return group
        case ToolbarID.source:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("playground.toolbar.text")
            item.toolTip = L10n.string("playground.toolbar.text.help")
            item.image = Self.symbol("book", L10n.string("playground.toolbar.text"))
            let menu = NSMenu()
            menu.addItem(withTitle: L10n.string("menu.playground.loadEPUB"), action: #selector(loadPlaygroundEPUB(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L10n.string("menu.playground.sample"), action: #selector(showSampleText(_:)), keyEquivalent: "")
            item.menu = menu
            return item
        case ToolbarID.night:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("toolbar.night")
            item.toolTip = L10n.string("playground.toolbar.night.help")
            item.action = #selector(toggleNight(_:))
            item.target = self
            item.isBordered = true
            nightItem = item
            updateChrome()
            return item
        case ToolbarID.save:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("playground.saveToStyles")
            item.toolTip = L10n.string("playground.toolbar.save.help")
            item.image = Self.symbol("square.and.arrow.down", L10n.string("playground.saveToStyles"))
            item.action = #selector(saveToStyles(_:))
            item.target = self
            item.showsIndicator = true
            let menu = NSMenu()
            menu.addItem(withTitle: L10n.string("menu.playground.saveToStyles"), action: #selector(saveToStyles(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L10n.string("menu.playground.saveAs"), action: #selector(saveCSSAs(_:)), keyEquivalent: "")
            item.menu = menu
            return item
        default:
            return nil
        }
    }

    private static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }

    static let cssType = UTType(filenameExtension: "css") ?? UTType(importedAs: "public.css")

    private func presentFileError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: window)
    }

    // MARK: Smoke test

    /// Launch arguments `-AomidoriPlaygroundSmoke <folder>` (and optionally
    /// `-AomidoriPlaygroundEPUB <book.epub>`): runs a scripted session and writes snapshots and a
    /// report there. Used by `scripts/smoke-playground.sh`.
    private lazy var smokeTest: PlaygroundSmokeTest? = UserDefaults.standard.string(forKey: PlaygroundSmokeTest.defaultsKey)
        .map { PlaygroundSmokeTest(folder: URL(fileURLWithPath: $0), playground: self) }

    var smokeEditor: CodeEditor { editor }
    var smokePreview: PlaygroundPreviewController { preview }
    var smokeStyleSelection: String? { styleTable.selectedRow >= 0 ? styles[styleTable.selectedRow].name : nil }
    func smokeLoadStyle(named name: String) {
        if let style = styles.first(where: { $0.name == name }) { switchToStyle(style) }
    }
}

@MainActor
private extension NSError {
    func presentAsSheet(on window: NSWindow) {
        NSAlert(error: self).beginSheetModal(for: window)
    }
}
