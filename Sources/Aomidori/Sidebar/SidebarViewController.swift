import AppKit
import AomidoriCore

/// The window's sidebar: a pane selector in a Liquid Glass capsule, above the selected pane.
@MainActor
final class SidebarViewController: NSViewController {
    /// Called when the reader picks another pane (not when `select(_:)` is called).
    var onPaneChange: ((SidebarPane) -> Void)?

    private(set) var pane: SidebarPane
    private let panes: [SidebarPane: NSViewController]
    private let selectable = SidebarPane.available
    private let selector = NSSegmentedControl()
    private let container = NSView()

    init(initialPane: SidebarPane, panes: [SidebarPane: NSViewController]) {
        self.panes = panes
        self.pane = panes[initialPane] == nil ? .contents : initialPane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        selector.segmentCount = selectable.count
        selector.trackingMode = .selectOne
        selector.segmentDistribution = .fillEqually
        for (index, pane) in selectable.enumerated() {
            selector.setImage(NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title), forSegment: index)
            selector.setToolTip(L10n.format("sidebar.pane.help", pane.title, pane.shortcutDigit), forSegment: index)
        }
        selector.target = self
        selector.action = #selector(selectorChanged(_:))
        selector.setAccessibilityLabel(L10n.string("sidebar.selector"))

        let glass = NSGlassEffectView()
        glass.contentView = selector
        glass.cornerRadius = 16
        glass.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false

        let view = NSView()
        view.addSubview(container)
        view.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            glass.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            glass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            container.topAnchor.constraint(equalTo: glass.bottomAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
        show(pane)
    }

    /// Shows a pane; unavailable panes are ignored.
    func select(_ pane: SidebarPane) {
        guard panes[pane] != nil else { return }
        self.pane = pane
        if isViewLoaded { show(pane) }
    }

    @objc private func selectorChanged(_ sender: NSSegmentedControl) {
        guard selectable.indices.contains(sender.selectedSegment) else { return }
        let pane = selectable[sender.selectedSegment]
        guard pane != self.pane else { return }
        select(pane)
        onPaneChange?(pane)
    }

    private func show(_ pane: SidebarPane) {
        selector.selectedSegment = selectable.firstIndex(of: pane) ?? -1
        guard let controller = panes[pane], controller.view.superview !== container else { return }
        children.forEach { $0.removeFromParent() }
        container.subviews.forEach { $0.removeFromSuperview() }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }
}

extension SidebarPane {
    var title: String { L10n.string("sidebar.pane.\(rawValue)") }

    var symbolName: String {
        switch self {
        case .contents: "list.bullet"
        case .bookmarks: "bookmark"
        case .thumbnails: "square.grid.2x2"
        case .images: "photo.on.rectangle"
        case .search: "magnifyingglass"
        case .notes: "note.text"
        }
    }
}

/// A sidebar row with a title and a secondary line, shared by the list panes.
@MainActor
final class SidebarListCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarListCell")

    let titleField = NSTextField(labelWithString: "")
    let detailField = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 2
        titleField.cell?.truncatesLastVisibleLine = true
        detailField.font = .preferredFont(forTextStyle: .caption1)
        detailField.textColor = .secondaryLabelColor
        detailField.lineBreakMode = .byTruncatingTail
        let stack = NSStackView(views: [titleField, detailField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        textField = titleField
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func make(in tableView: NSTableView) -> SidebarListCell {
        tableView.makeView(withIdentifier: identifier, owner: nil) as? SidebarListCell ?? SidebarListCell()
    }
}

/// A source-list table in a scroll view, with an optional centred placeholder.
@MainActor
final class SidebarTableView: NSTableView {
    /// Called for the Delete and Forward Delete keys on a selected row.
    var onDelete: ((Int) -> Void)?
    /// Called for Return and Enter on a selected row.
    var onActivate: ((Int) -> Void)?

    override func keyDown(with event: NSEvent) {
        let row = selectedRow
        if row >= 0, let onDelete, [KeyCode.delete, KeyCode.forwardDelete].contains(event.keyCode) {
            onDelete(row)
        } else if row >= 0, let onActivate, [KeyCode.returnKey, KeyCode.enter].contains(event.keyCode) {
            onActivate(row)
        } else {
            super.keyDown(with: event)
        }
    }

    static func makeScrollView(for table: NSTableView, label: String) -> NSScrollView {
        let column = NSTableColumn(identifier: .init("main"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.usesAutomaticRowHeights = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.setAccessibilityLabel(label)
        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }
}

/// A secondary-colour message centred in a pane, for empty states.
@MainActor
func makePlaceholderLabel() -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: "")
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.isSelectable = false
    label.translatesAutoresizingMaskIntoConstraints = false
    return label
}
