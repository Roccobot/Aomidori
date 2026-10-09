import AomidoriCore
import AppKit
import UniformTypeIdentifiers

/// The empty window's content, from the top: the drop zone, the invitation with its Open
/// button, and the recent files. The drop zone grows with the window, up to half its width and
/// 30% of its height. The whole view takes dropped EPUB files; the drop zone lights
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
    private var dropZoneWidth: NSLayoutConstraint?
    private var dropZoneHeight: NSLayoutConstraint?
    private var recentsHeaderLeading: NSLayoutConstraint?
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
        stack.setCustomSpacing(24, after: dropZone)
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
        // The list keeps its column; the drop zone may be wider.
        let listWidth = scrollView.widthAnchor.constraint(equalToConstant: Self.listWidth)
        listWidth.priority = .defaultHigh
        let dropZoneWidth = dropZone.widthAnchor.constraint(equalToConstant: DropZoneView.minimumSize.width)
        let dropZoneHeight = dropZone.heightAnchor.constraint(equalToConstant: DropZoneView.minimumSize.height)
        let recentsHeaderLeading = recentsHeader.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16)
        self.dropZoneWidth = dropZoneWidth
        self.dropZoneHeight = dropZoneHeight
        self.recentsHeaderLeading = recentsHeaderLeading
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24),
            listWidth,
            scrollView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -20),
            dropZoneWidth, dropZoneHeight,
            recentsHeaderLeading,
            tableHeight, tableMinimumHeight,
        ])
        setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The column of the recent files.
    static let listWidth: CGFloat = 420

    override func layout() {
        let size = DropZoneView.size(inWindowContent: bounds.size)
        if dropZoneWidth?.constant != size.width { dropZoneWidth?.constant = size.width }
        if dropZoneHeight?.constant != size.height { dropZoneHeight?.constant = size.height }
        super.layout()
        alignRecentsHeader()
    }

    /// The heading starts exactly where the file names start: both are labels, so their text
    /// sits at the same distance from their frames, and the frames are lined up.
    private func alignRecentsHeader() {
        guard !recents.isEmpty, let constraint = recentsHeaderLeading,
              let field = (tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NSTableCellView)?.textField else { return }
        let offset = field.convert(NSPoint.zero, to: self).x - recentsHeader.convert(NSPoint.zero, to: self).x
        guard abs(offset) > 0.25 else { return }
        constraint.constant += offset
        needsLayout = true
    }

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

    /// The drop zone's size against the window's, and the heading's text start against the
    /// first file name's (window coordinates).
    var smokeLayout: [String: Double] {
        // Twice: lining up the heading can ask for one more pass.
        layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        var result: [String: Double] = [
            "dropZoneWidth": Double(dropZone.frame.width), "dropZoneHeight": Double(dropZone.frame.height),
            "contentWidth": Double(bounds.width), "contentHeight": Double(bounds.height),
        ]
        if !recents.isEmpty, let field = (tableView.view(atColumn: 0, row: 0, makeIfNecessary: false) as? NSTableCellView)?.textField {
            result["headerTextX"] = Double(recentsHeader.convert(NSPoint.zero, to: nil).x)
            result["firstTitleTextX"] = Double(field.convert(NSPoint.zero, to: nil).x)
        }
        return result
    }
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

/// The drop zone: Graphe's line-drawn book inside a dashed frame, both drawn at the zone's
/// size. The frame is drawn in code (`DashedFrame`: dashes spread evenly over the perimeter,
/// one centred at the top middle) in the window's appearance colour (`#43B59E`, `#5FD4BC` in
/// Night or dark mode); the book comes from Graphe's SVG, recoloured, with the 0.5x PNG art as
/// fallback. While a book is dragged over the window the frame is solid, stronger and filled.
/// Clicking it opens the Open panel.
@MainActor
final class DropZoneView: NSView {
    /// The frame of Graphe's 240 × 160 art: the smallest the zone gets, and its proportions.
    static let minimumSize = NSSize(width: 184, height: 128)
    /// Corner radius at the minimum size; it grows with the zone.
    static let minimumRadius: CGFloat = 20
    static let lineWidth: CGFloat = 2
    static let highlightedLineWidth: CGFloat = 2.5
    /// The book's box in Graphe's art (viewBox 80 42 80 72 inside the 240 × 160 canvas, whose
    /// frame starts at 28, 16): its size and its centre's offset from the frame's centre, in
    /// units of the minimum size.
    private static let bookSize = NSSize(width: 80, height: 72)
    private static let bookCentreOffset = NSPoint(x: 0, y: (42 + 36) - (16 + 64))

    /// Half the window's width and 30% of its height at most, in Graphe's proportions, never
    /// smaller than the art was (nor wider than the window).
    static func size(inWindowContent content: NSSize) -> NSSize {
        let aspect = minimumSize.width / minimumSize.height
        var width = min(content.width * 0.5, content.height * 0.3 * aspect)
        width = max(width, minimumSize.width)
        width = min(width, max(content.width - 40, 1))
        return NSSize(width: width.rounded(), height: (width / aspect).rounded())
    }

    var onClick: (() -> Void)?
    var isHighlighted = false { didSet { if isHighlighted != oldValue { needsDisplay = true } } }
    /// Whether the book comes from the SVG (else the whole art from the PNG fallback).
    var rendersSVG: Bool { book(dark: isDark) != nil }

    private static let bookTemplate: String? = Bundle.main.url(forResource: "aomidori-dropzone-book", withExtension: "svg", subdirectory: "EmptyState")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    private var bookCache: [Bool: NSImage] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L10n.string("empty.open.help"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { Self.minimumSize }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let colour = NSColor(hex: isDark ? EmptyStateArt.darkTint : EmptyStateArt.lightTint)
        let scale = bounds.width / Self.minimumSize.width
        guard let book = book(dark: isDark) else {
            // No SVG: Graphe's static art, frame included.
            Self.png(dark: isDark)?.draw(in: bounds.insetBy(dx: -28 * scale, dy: -16 * scale))
            return
        }

        let lineWidth = isHighlighted ? Self.highlightedLineWidth : Self.lineWidth
        let radius = Self.minimumRadius * scale
        let path = Self.framePath(in: bounds, lineWidth: lineWidth, radius: radius)
        colour.withAlphaComponent(isHighlighted ? 0.12 : 0.024).setFill()
        path.fill()
        path.lineWidth = lineWidth
        if isHighlighted {
            colour.setStroke()
        } else {
            let frame = DashedFrame(boundsWidth: Double(bounds.width), boundsHeight: Double(bounds.height),
                                    radius: Double(radius), lineWidth: Double(lineWidth))
            let pattern: [CGFloat] = [CGFloat(frame.dash), CGFloat(frame.gap)]
            path.setLineDash(pattern, count: pattern.count, phase: CGFloat(frame.phase))
            path.lineCapStyle = .round
            colour.withAlphaComponent(0.6).setStroke()
        }
        path.stroke()

        let size = NSSize(width: Self.bookSize.width * scale, height: Self.bookSize.height * scale)
        // Graphe's offset is measured downwards (SVG); AppKit's y goes up.
        let centre = NSPoint(x: bounds.midX + Self.bookCentreOffset.x * scale, y: bounds.midY - Self.bookCentreOffset.y * scale)
        book.draw(in: NSRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height))
    }

    /// The rounded rectangle, `lineWidth / 2` inside the bounds, starting at the top middle and
    /// going clockwise, so the dash pattern starts there (`DashedFrame.phase`).
    static func framePath(in bounds: NSRect, lineWidth: CGFloat, radius: CGFloat) -> NSBezierPath {
        let rect = bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let r = min(radius, rect.width / 2, rect.height / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.maxX - r, y: rect.maxY))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: 90, endAngle: 0, clockwise: true)
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + r))
        path.appendArc(withCenter: NSPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: 0, endAngle: -90, clockwise: true)
        path.line(to: NSPoint(x: rect.minX + r, y: rect.minY))
        path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: -90, endAngle: -180, clockwise: true)
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - r))
        path.appendArc(withCenter: NSPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: 180, endAngle: 90, clockwise: true)
        path.close()
        return path
    }

    private func book(dark: Bool) -> NSImage? {
        if let image = bookCache[dark] { return image }
        guard let template = Self.bookTemplate,
              let image = NSImage(data: Data(EmptyStateArt.svg(template, color: dark ? EmptyStateArt.darkTint : EmptyStateArt.lightTint).utf8))
        else { return nil }
        bookCache[dark] = image
        return image
    }

    /// The 0.5x art (240 × 160, frame included) at 1×, 2× and 3× in one image.
    private static func png(dark: Bool) -> NSImage? {
        let size = NSSize(width: 240, height: 160)
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
