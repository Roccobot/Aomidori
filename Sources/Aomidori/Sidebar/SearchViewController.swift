import AomidoriCore
import AppKit
import EPUBKit

/// The search pane: a search field and every occurrence in the book, in reading order.
/// Searching runs off the main thread; a new query cancels the previous one.
@MainActor
final class SearchViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var onSelect: ((SearchHit, String) -> Void)?

    private let book: EPUBBook
    private let index: EPUBTextIndex
    private let searchField = NSSearchField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let tableView = SidebarTableView()
    private var hits: [SearchHit] = []
    private var query = ""
    private var searchTask: Task<Void, Never>?

    init(publication: EPUBPublication) {
        book = publication.book
        index = EPUBTextIndex(publication: publication)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        searchField.placeholderString = L10n.string("search.placeholder")
        searchField.sendsSearchStringImmediately = false
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let scrollView = SidebarTableView.makeScrollView(for: tableView, label: L10n.string("sidebar.pane.search"))
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.onActivate = { [weak self] row in self?.activate(row) }

        let view = NSView()
        for subview in [searchField, statusLabel, scrollView] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            statusLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        self.view = view
    }

    /// Puts the cursor in the search field, selecting what is there.
    func focusSearchField() {
        loadViewIfNeeded()
        view.window?.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query else { return }
        self.query = query
        searchTask?.cancel()
        hits = []
        tableView.reloadData()
        guard query.count >= 2 else {
            statusLabel.stringValue = ""
            return
        }
        statusLabel.stringValue = L10n.string("search.searching")
        let index = self.index
        searchTask = Task { [weak self] in
            let work = Task.detached(priority: .userInitiated) {
                index.search(query, isCancelled: { Task.isCancelled })
            }
            let hits = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard let self, !Task.isCancelled, query == self.query else { return }
            show(hits)
        }
    }

    private func show(_ hits: [SearchHit]) {
        self.hits = hits
        tableView.reloadData()
        statusLabel.stringValue = switch hits.count {
        case 0: L10n.string("search.noResults")
        case EPUBTextIndex.defaultLimit...: L10n.format("search.resultsLimited", hits.count)
        default: L10n.format("search.results", hits.count)
        }
    }

    /// The down arrow moves from the field to the results.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.moveDown(_:)), !hits.isEmpty else { return false }
        view.window?.makeFirstResponder(tableView)
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        return true
    }

    var hasResults: Bool { !hits.isEmpty }

    /// `⌘G` / `⇧⌘G`: selects and shows the result after (or before) the selected one, wrapping
    /// round. Returns `false` when there are no results.
    func showAdjacentHit(_ step: Int) -> Bool {
        let selected = tableView.selectedRow >= 0 ? tableView.selectedRow : nil
        guard let row = ResultStepping.index(from: selected, count: hits.count, step: step) else { return false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        activate(row)
        return true
    }

    @objc private func rowClicked(_ sender: Any?) {
        activate(tableView.clickedRow)
    }

    private func activate(_ row: Int) {
        guard hits.indices.contains(row) else { return }
        onSelect?(hits[row], query)
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hit = hits[row]
        let cell = SidebarListCell.make(in: tableView)
        let snippet = NSMutableAttributedString(string: hit.snippet, attributes: [.font: NSFont.preferredFont(forTextStyle: .body)])
        let match = NSRange(location: hit.matchLocation, length: hit.matchLength)
        if NSMaxRange(match) <= snippet.length {
            snippet.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize), range: match)
        }
        cell.titleField.attributedStringValue = snippet
        cell.titleField.maximumNumberOfLines = 3
        cell.detailField.stringValue = book.tocTitle(forPath: hit.path) ?? L10n.format("search.item", hit.spineIndex + 1)
        return cell
    }
}
