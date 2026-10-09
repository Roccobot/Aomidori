import AppKit
import EPUBKit

/// The table of contents pane of the window's sidebar.
@MainActor
final class TOCViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// Called when the reader picks an entry that has a target.
    var onSelect: ((TOCEntry) -> Void)?

    private let roots: [TOCNode]
    private let outlineView = NSOutlineView()
    private var isRevealing = false
    /// The chapter to highlight, also when the pane is loaded or shown later.
    private var revealedPath: String?

    init(entries: [TOCEntry]) {
        roots = entries.map { TOCNode($0, parent: nil) }
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let column = NSTableColumn(identifier: .init("title"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .default
        outlineView.floatsGroupRows = false
        outlineView.autoresizesOutlineColumn = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked(_:))
        outlineView.setAccessibilityLabel(L10n.string("toc.title"))

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        if roots.isEmpty {
            let label = NSTextField(labelWithString: L10n.string("toc.empty"))
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            scrollView.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            ])
        }
        view = scrollView
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if let revealedPath { reveal(path: revealedPath) }
    }

    /// Selects the first entry that points at `path`, expanding its ancestors, without navigating.
    func reveal(path: String) {
        revealedPath = path
        guard isViewLoaded, outlineView.dataSource != nil else { return }
        guard let node = TOCNode.first(in: roots, where: { $0.entry.path == path }) else {
            outlineView.deselectAll(nil)
            return
        }
        var ancestors: [TOCNode] = []
        var parent = node.parent
        while let current = parent {
            ancestors.insert(current, at: 0)
            parent = current.parent
        }
        ancestors.forEach { outlineView.expandItem($0) }
        let row = outlineView.row(forItem: node)
        guard row >= 0 else { return }
        isRevealing = true
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        isRevealing = false
    }

    /// Headings without a target expand or collapse on click.
    @objc private func rowClicked(_ sender: Any?) {
        guard let node = outlineView.item(atRow: outlineView.clickedRow) as? TOCNode, node.entry.path == nil else { return }
        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            outlineView.expandItem(node)
        }
    }

    /// Clicks and keyboard selection both navigate.
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRevealing, let node = outlineView.item(atRow: outlineView.selectedRow) as? TOCNode,
              node.entry.path != nil else { return }
        onSelect?(node.entry)
    }

    // MARK: Data source and delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? TOCNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? TOCNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? TOCNode)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TOCNode else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("TOCCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeCell(identifier)
        cell.textField?.stringValue = node.entry.title
        cell.textField?.toolTip = node.entry.title
        cell.textField?.textColor = node.entry.path == nil ? .secondaryLabelColor : .labelColor
        return cell
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}

/// Reference wrapper: `NSOutlineView` identifies items by object identity.
@MainActor
private final class TOCNode: NSObject {
    let entry: TOCEntry
    weak var parent: TOCNode?
    private(set) var children: [TOCNode] = []

    init(_ entry: TOCEntry, parent: TOCNode?) {
        self.entry = entry
        self.parent = parent
        super.init()
        children = entry.children.map { TOCNode($0, parent: self) }
    }

    static func first(in nodes: [TOCNode], where predicate: (TOCNode) -> Bool) -> TOCNode? {
        for node in nodes {
            if predicate(node) { return node }
            if let found = first(in: node.children, where: predicate) { return found }
        }
        return nil
    }
}
