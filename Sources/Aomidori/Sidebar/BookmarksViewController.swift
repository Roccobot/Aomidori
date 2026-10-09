import AppKit
import AomidoriCore
import EPUBKit

/// The bookmarks pane: the book's bookmarks in reading order.
@MainActor
final class BookmarksViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((Bookmark) -> Void)?
    var onDelete: ((Bookmark) -> Void)?

    /// Set by the window; shown in reading order.
    var bookmarks: [Bookmark] = [] {
        didSet {
            guard isViewLoaded else { return }
            tableView.reloadData()
            updatePlaceholder()
        }
    }

    private let book: EPUBBook
    private let tableView = SidebarTableView()
    private let placeholder = makePlaceholderLabel()

    init(book: EPUBBook) {
        self.book = book
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let scrollView = SidebarTableView.makeScrollView(for: tableView, label: L10n.string("sidebar.pane.bookmarks"))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.onActivate = { [weak self] row in self?.activate(row) }
        tableView.onDelete = { [weak self] row in self?.delete(row) }
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.string("bookmarks.delete"), action: #selector(deleteClicked(_:)), keyEquivalent: "")
        tableView.menu = menu

        placeholder.stringValue = L10n.string("bookmarks.empty")
        scrollView.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            placeholder.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 16),
            placeholder.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -16),
        ])
        view = scrollView
        updatePlaceholder()
    }

    private func updatePlaceholder() {
        placeholder.isHidden = !bookmarks.isEmpty
    }

    @objc private func rowClicked(_ sender: Any?) {
        activate(tableView.clickedRow)
    }

    @objc private func deleteClicked(_ sender: Any?) {
        delete(tableView.clickedRow)
    }

    private func activate(_ row: Int) {
        guard bookmarks.indices.contains(row) else { return }
        onSelect?(bookmarks[row])
    }

    private func delete(_ row: Int) {
        guard bookmarks.indices.contains(row) else { return }
        onDelete?(bookmarks[row])
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { bookmarks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let bookmark = bookmarks[row]
        let cell = SidebarListCell.make(in: tableView)
        cell.titleField.stringValue = bookmark.title
        let chapter = book.tocTitle(forPath: bookmark.spinePath) ?? ""
        let percent = bookmark.fraction.formatted(.percent.precision(.fractionLength(0)))
        cell.detailField.stringValue = chapter.isEmpty ? percent : "\(chapter) · \(percent)"
        cell.toolTip = bookmark.created.formatted(date: .abbreviated, time: .shortened)
        return cell
    }
}
