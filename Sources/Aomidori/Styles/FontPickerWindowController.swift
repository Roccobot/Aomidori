import AppKit
import UniformTypeIdentifiers

/// The custom font panel: every family, each shown in its own face, with a filter; picking one
/// turns the custom font on at once. *Load Font…* adds TTF/OTF files to the fonts folder.
@MainActor
final class FontPickerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let environment = ReaderEnvironment.shared
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let enabledCheckbox = NSButton(checkboxWithTitle: L10n.string("font.enabled"), target: nil, action: nil)
    private var allFamilies: [String] = []
    private var families: [String] = []
    private var loaded: Set<String> = []
    private var observer: (any NSObjectProtocol)?
    private var isUpdatingSelection = false

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        panel.title = L10n.string("font.title")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.minSize = NSSize(width: 260, height: 300)
        panel.setFrameAutosaveName("AomidoriFontPicker")
        super.init(window: panel)
        buildContent(in: panel)
        observer = NotificationCenter.default.addObserver(forName: .readerEnvironmentDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncWithEnvironment() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        reloadFamilies()
        if window?.isVisible != true { window?.center() }
        super.showWindow(sender)
        window?.makeFirstResponder(searchField)
    }

    private func buildContent(in panel: NSPanel) {
        searchField.placeholderString = L10n.string("font.search")
        searchField.delegate = self
        let column = NSTableColumn(identifier: .init("family"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel(L10n.string("font.title"))
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        enabledCheckbox.target = self
        enabledCheckbox.action = #selector(enabledChanged(_:))
        enabledCheckbox.toolTip = L10n.string("font.enabled.help")
        let loadButton = NSButton(title: L10n.string("font.load"), target: nil, action: #selector(AppDelegate.loadFontFile(_:)))
        let footer = NSStackView(views: [enabledCheckbox, NSView(), loadButton])
        footer.orientation = .horizontal

        let stack = NSStackView(views: [searchField, scrollView, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 12, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
        ])
        panel.contentView = content
    }

    private func reloadFamilies() {
        allFamilies = environment.fonts.families
        loaded = environment.fonts.loadedFamilies
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        families = query.isEmpty ? allFamilies : allFamilies.filter {
            $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        tableView.reloadData()
        syncWithEnvironment()
    }

    private func syncWithEnvironment() {
        enabledCheckbox.state = environment.customFontEnabled ? .on : .off
        enabledCheckbox.isEnabled = environment.customFontFamily != nil
        guard let family = environment.customFontFamily, let row = families.firstIndex(of: family) else {
            tableView.deselectAll(nil)
            return
        }
        guard tableView.selectedRow != row else { return }
        isUpdatingSelection = true
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        isUpdatingSelection = false
    }

    /// Called after font files are loaded: lists them and selects the first new family.
    func didLoad(families newFamilies: [String]) {
        reloadFamilies()
        if let first = newFamilies.first { environment.setCustomFont(family: first) }
    }

    @objc private func enabledChanged(_ sender: NSButton) {
        environment.setCustomFontEnabled(sender.state == .on)
    }

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { families.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let family = families[row]
        let identifier = NSUserInterfaceItemIdentifier("FontCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let title = loaded.contains(family) ? L10n.format("font.loadedFamily", family) : family
        cell.textField?.stringValue = title
        cell.textField?.font = CustomFonts.previewFont(family: family, size: 15) ?? .systemFont(ofSize: 15)
        cell.textField?.toolTip = family
        cell.setAccessibilityLabel(family)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, families.indices.contains(tableView.selectedRow) else { return }
        let family = families[tableView.selectedRow]
        if family != environment.customFontFamily || !environment.customFontEnabled {
            environment.setCustomFont(family: family)
        }
    }

    // MARK: Loading files

    /// Asks for font files and copies them into the fonts folder.
    static func runLoadPanel(attachedTo window: NSWindow?, completion: @escaping @MainActor ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.title = L10n.string("font.load.title")
        panel.prompt = L10n.string("font.load.prompt")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = CustomFonts.fileExtensions.compactMap { UTType(filenameExtension: $0) }
        let handler: @MainActor (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            do {
                completion(try ReaderEnvironment.shared.installFonts(panel.urls))
            } catch {
                let alert = NSAlert()
                alert.messageText = L10n.string("font.load.error")
                alert.informativeText = L10n.string("font.load.error.detail")
                alert.runModal()
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { handler(panel.runModal()) }
    }
}
