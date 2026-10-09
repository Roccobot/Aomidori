import AomidoriCore
import AppKit
import UniformTypeIdentifiers

/// The empty window's content, from the top: the drop zone, the invitation with its Open
/// button, and the recent books. The whole view takes dropped EPUB files; the drop zone lights
/// up while one is dragged over it.
@MainActor
final class EmptyReaderView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onOpen: (() -> Void)?
    var onOpenURLs: (([URL]) -> Void)?
    let message = L10n.string("empty.message")

    /// Row height of the recent books, and the rows shown before the list scrolls.
    static let rowHeight: CGFloat = 28
    static let maximumVisibleRows = 8
    /// Rows always visible at the minimum window size.
    static let minimumVisibleRows = 5

    private let dropZone = DropZoneView()
    private let recentsHeader = NSTextField(labelWithString: L10n.string("empty.recents"))
    private let tableView = RecentBooksTableView()
    private let scrollView = NSScrollView()
    private var tableHeight: NSLayoutConstraint?
    private var tableMinimumHeight: NSLayoutConstraint?
    private(set) var recents: [RecentBook] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])

        dropZone.onClick = { [weak self] in self?.onOpen?() }
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: NSFont.systemFontSize + 2)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        let button = NSButton(title: L10n.string("empty.open"), target: self, action: #selector(openClicked(_:)))
        button.bezelStyle = .push
        button.keyEquivalent = "o"
        button.keyEquivalentModifierMask = .command
        button.toolTip = L10n.string("empty.open.help")

        recentsHeader.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        recentsHeader.textColor = .tertiaryLabelColor
        let column = NSTableColumn(identifier: .init("book"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = Self.rowHeight
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = .zero
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.onActivate = { [weak self] row in self?.openRecent(at: row) }
        tableView.setAccessibilityLabel(L10n.string("empty.recents"))
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let stack = NSStackView(views: [dropZone, label, button, recentsHeader, scrollView])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(16, after: dropZone)
        stack.setCustomSpacing(28, after: button)
        stack.setCustomSpacing(4, after: recentsHeader)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let tableHeight = scrollView.heightAnchor.constraint(equalToConstant: 0)
        tableHeight.priority = .defaultLow
        // Five rows fit at the minimum window size; a smaller window (a tab sharing the frame of
        // a smaller reader window) shows fewer rather than overflowing.
        let tableMinimumHeight = scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)
        tableMinimumHeight.priority = .init(740)
        self.tableHeight = tableHeight
        self.tableMinimumHeight = tableMinimumHeight
        let columnWidth = stack.widthAnchor.constraint(equalToConstant: 420)
        columnWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            columnWidth,
            dropZone.widthAnchor.constraint(equalToConstant: DropZoneView.size.width),
            dropZone.heightAnchor.constraint(equalToConstant: DropZoneView.size.height),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recentsHeader.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            tableHeight, tableMinimumHeight,
        ])
        setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The list, when there are recent books: arrows move the selection, Return opens.
    var initialFirstResponder: NSView? { recents.isEmpty ? nil : tableView }

    // MARK: Recent books

    /// Reads the recent documents again: the system's Recent Items count, missing files left out.
    func reloadRecents() {
        let controller = NSDocumentController.shared
        recents = RecentBooks.list(controller.recentDocumentURLs, limit: controller.maximumRecentDocumentCount) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        tableView.reloadData()
        recentsHeader.isHidden = recents.isEmpty
        scrollView.isHidden = recents.isEmpty
        tableHeight?.constant = listHeight(rows: min(recents.count, Self.maximumVisibleRows))
        tableMinimumHeight?.constant = listHeight(rows: min(recents.count, Self.minimumVisibleRows))
    }

    /// The height that shows `rows` whole rows, with the padding the inset table style puts
    /// above the first row and below the last.
    private func listHeight(rows: Int) -> CGFloat {
        guard rows > 0, tableView.numberOfRows >= rows else { return 0 }
        let padding = tableView.rect(ofRow: 0).minY
        return tableView.rect(ofRow: rows - 1).maxY + padding
    }

    func numberOfRows(in tableView: NSTableView) -> Int { recents.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("RecentBook")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: NSFont.systemFontSize + 1)
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let book = recents[row]
        cell.textField?.stringValue = book.title
        cell.toolTip = book.url.path
        cell.setAccessibilityLabel(book.title)
        return cell
    }

    @objc private func rowClicked(_ sender: NSTableView) {
        openRecent(at: sender.clickedRow)
    }

    private func openRecent(at row: Int) {
        guard recents.indices.contains(row) else { return }
        onOpenURLs?([recents[row].url])
    }

    @objc private func openClicked(_ sender: Any?) { onOpen?() }

    // MARK: Dropping books

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
        dropZone.isHighlighted = !Self.epubURLs(on: sender.draggingPasteboard).isEmpty
        return dropZone.isHighlighted ? .copy : []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        dropZone.isHighlighted = false
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        dropZone.isHighlighted = false
        let urls = Self.epubURLs(on: sender.draggingPasteboard)
        guard !urls.isEmpty else { return false }
        onOpenURLs?(urls)
        return true
    }

    // MARK: Smoke test

    var smokeRendersSVG: Bool { dropZone.rendersSVG }
    func smokeHighlight(_ highlighted: Bool) { dropZone.isHighlighted = highlighted }
}

/// The recent books list: Return and Enter open the selected book.
@MainActor
final class RecentBooksTableView: NSTableView {
    var onActivate: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if flags.isEmpty, [KeyCode.returnKey, KeyCode.enter].contains(event.keyCode), selectedRow >= 0 {
            onActivate?(selectedRow)
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Graphe's empty-state art (240 × 160 pt): a dashed frame round a line-drawn book. Drawn from
/// the SVG in the window's appearance colour (`#43B59E`, `#5FD4BC` in Night or dark mode), with
/// the PNGs as fallback; a solid, stronger frame while a book is dragged over the window.
/// Clicking it opens the Open panel.
@MainActor
final class DropZoneView: NSView {
    static let size = NSSize(width: 240, height: 160)
    var onClick: (() -> Void)?
    var isHighlighted = false { didSet { if isHighlighted != oldValue { needsDisplay = true } } }
    /// Whether the art comes from the SVG (else from the PNG fallback).
    private(set) var rendersSVG = false

    private static let template: String? = Bundle.main.url(forResource: "aomidori-empty", withExtension: "svg", subdirectory: "EmptyState")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    private var cache: [String: NSImage] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L10n.string("empty.open.help"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { Self.size }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let image = art(dark: isDark, highlighted: isHighlighted)
        image?.draw(in: bounds)
        // The PNG fallback has no highlighted variant: the frame is stroked over it.
        if isHighlighted, !rendersSVG {
            let frame = NSRect(x: 28, y: 16, width: 184, height: 128)
            let path = NSBezierPath(roundedRect: frame, xRadius: 20, yRadius: 20)
            path.lineWidth = 2.25
            NSColor(hex: isDark ? EmptyStateArt.darkTint : EmptyStateArt.lightTint).setStroke()
            path.stroke()
        }
    }

    private func art(dark: Bool, highlighted: Bool) -> NSImage? {
        let key = "\(dark) \(highlighted)"
        if let image = cache[key] { return image }
        var image: NSImage?
        if let template = Self.template {
            let svg = EmptyStateArt.svg(template, color: dark ? EmptyStateArt.darkTint : EmptyStateArt.lightTint, highlighted: highlighted)
            image = NSImage(data: Data(svg.utf8))
            rendersSVG = image != nil
        }
        if image == nil { image = Self.png(dark: dark) }
        image?.size = Self.size
        cache[key] = image
        return image
    }

    /// The PNGs at 1×, 2× and 3× in one image.
    private static func png(dark: Bool) -> NSImage? {
        let base = dark ? "aomidori-empty-dark" : "aomidori-empty"
        let image = NSImage(size: size)
        for suffix in ["", "@2x", "@3x"] {
            guard let url = Bundle.main.url(forResource: base + suffix, withExtension: "png", subdirectory: "EmptyState"),
                  let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = size
            image.addRepresentation(rep)
        }
        return image.representations.isEmpty ? nil : image
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}

private extension NSColor {
    /// `#RRGGBB`.
    convenience init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
