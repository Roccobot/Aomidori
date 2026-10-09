import AppKit
import AomidoriCore
import UniformTypeIdentifiers

/// The custom font chooser: every family, each shown in its own face, with a filter; picking one
/// turns the custom font on at once. Below the list, the face (*Automatic* keeps the weights of
/// the book and the style) and a slider for each axis of a variable face. *Font Panel…* opens
/// the system Font panel for features and finer choices; *Load Font…* adds font files to the
/// fonts folder.
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
    private let facePopUp = NSPopUpButton()
    private let axesStack = NSStackView()
    /// The faces listed in the popup, after its *Automatic* item, and the family they belong to.
    private var faceMembers: [CustomFonts.Member] = []
    private var faceFamily: String?
    /// The face and axis values the sliders show, so they are rebuilt only when these change.
    private var shownAxes: (face: String?, axes: [CustomFonts.VariationAxis])?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        panel.title = L10n.string("font.title")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.minSize = NSSize(width: 280, height: 360)
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
        let panelButton = NSButton(title: L10n.string("font.panel"), target: nil, action: #selector(AppDelegate.showFontPanel(_:)))
        panelButton.toolTip = L10n.string("font.panel.help")
        let buttons = NSStackView(views: [panelButton, NSView(), loadButton])
        buttons.orientation = .horizontal

        facePopUp.target = self
        facePopUp.action = #selector(faceChanged(_:))
        facePopUp.setAccessibilityLabel(L10n.string("font.face"))
        let faceLabel = NSTextField(labelWithString: L10n.string("font.face"))
        let faceRow = NSStackView(views: [faceLabel, facePopUp])
        faceRow.orientation = .horizontal
        facePopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        axesStack.orientation = .vertical
        axesStack.alignment = .leading
        axesStack.spacing = 6

        let stack = NSStackView(views: [searchField, scrollView, faceRow, axesStack, enabledCheckbox, buttons])
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
            faceRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            axesStack.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24),
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
        syncFace()
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

    // MARK: Face and axes

    private func syncFace() {
        let choice = environment.customFontChoice
        if faceFamily != choice?.family {
            faceFamily = choice?.family
            faceMembers = choice.map { environment.fonts.faceMembers(ofFamily: $0.family) } ?? []
            facePopUp.removeAllItems()
            facePopUp.addItem(withTitle: L10n.string("font.face.automatic"))
            facePopUp.menu?.addItem(.separator())
            for member in faceMembers {
                facePopUp.addItem(withTitle: member.displayName)
                let item = facePopUp.lastItem
                item?.representedObject = member.postScriptName
                item?.toolTip = member.postScriptName
                if let font = NSFont(name: member.postScriptName, size: NSFont.systemFontSize) {
                    item?.attributedTitle = NSAttributedString(string: member.displayName, attributes: [.font: font])
                }
            }
        }
        facePopUp.isEnabled = choice != nil
        if let face = choice?.faceName, let index = facePopUp.itemArray.firstIndex(where: { $0.representedObject as? String == face }) {
            facePopUp.selectItem(at: index)
        } else if let face = choice?.faceName {
            // A face the family list does not show (chosen in the Font panel): listed as it is.
            facePopUp.addItem(withTitle: choice.map(FontChoiceConversion.displayName) ?? face)
            facePopUp.lastItem?.representedObject = face
            facePopUp.select(facePopUp.lastItem)
        } else {
            facePopUp.selectItem(at: 0)
        }
        syncAxes(choice)
    }

    /// One slider per axis of the chosen face: weight and width drive the CSS weight and width,
    /// the others `font-variation-settings`. Values are applied when the slider is released.
    private func syncAxes(_ choice: CustomFontChoice?) {
        let face = choice?.faceName
        let axes = face.map(CustomFonts.variationAxes(ofFace:)) ?? []
        if shownAxes?.face != face || shownAxes?.axes != axes {
            shownAxes = (face, axes)
            axesStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for (index, axis) in axes.enumerated() {
                let label = NSTextField(labelWithString: axis.name)
                label.toolTip = axis.tag
                label.widthAnchor.constraint(equalToConstant: 80).isActive = true
                label.lineBreakMode = .byTruncatingTail
                let slider = NSSlider(value: axis.defaultValue, minValue: axis.range.lowerBound, maxValue: axis.range.upperBound,
                                      target: self, action: #selector(axisChanged(_:)))
                slider.isContinuous = false
                slider.tag = index
                slider.setAccessibilityLabel(axis.name)
                let value = NSTextField(labelWithString: "")
                value.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
                value.alignment = .right
                value.widthAnchor.constraint(equalToConstant: 40).isActive = true
                let row = NSStackView(views: [label, slider, value])
                row.orientation = .horizontal
                axesStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: axesStack.widthAnchor).isActive = true
            }
        }
        axesStack.isHidden = axes.isEmpty
        for (axis, row) in zip(axes, axesStack.arrangedSubviews) {
            guard let views = (row as? NSStackView)?.arrangedSubviews, let slider = views[1] as? NSSlider,
                  let label = views[2] as? NSTextField else { continue }
            let value = choice.flatMap { Self.value(of: axis, in: $0) } ?? axis.defaultValue
            slider.doubleValue = value
            label.stringValue = CustomFontCSS.number(value)
        }
    }

    private static func value(of axis: CustomFonts.VariationAxis, in choice: CustomFontChoice) -> Double? {
        switch axis.tag {
        case "wght": choice.weight
        case "wdth": choice.stretch
        default: choice.variations[axis.tag]
        }
    }

    @objc private func faceChanged(_ sender: NSPopUpButton) {
        guard let family = environment.customFontFamily else { return }
        let features = environment.customFontChoice?.features ?? [:]
        guard let face = sender.selectedItem?.representedObject as? String,
              let font = NSFont(name: face, size: NSFont.systemFontSize) else {
            environment.setCustomFont(CustomFontChoice(family: family, features: features))
            return
        }
        var choice = FontChoiceConversion.choice(from: font).choice
        choice.family = family
        choice.features = features
        environment.setCustomFont(choice)
    }

    @objc private func axisChanged(_ sender: NSSlider) {
        guard var choice = environment.customFontChoice, let axes = shownAxes?.axes, axes.indices.contains(sender.tag) else { return }
        let axis = axes[sender.tag]
        let value = sender.doubleValue.rounded()
        switch axis.tag {
        case "wght": choice.weight = value
        case "wdth": choice.stretch = value == 100 ? nil : value
        default: choice.variations[axis.tag] = value
        }
        environment.setCustomFont(choice)
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
