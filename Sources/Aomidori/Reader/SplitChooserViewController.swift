import AppKit
import AomidoriCore

/// The split view's right half while choosing which tab goes there: the other tabs in tab
/// order, the first ten numbered 1…9, 0. Typing a number, a double click or Return opens a
/// tab; Escape leaves the split.
/// Author: Rocco Casadei, a.k.a. Roccobot
@MainActor
final class SplitChooserViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let tableView = ChooserTableView()
    private let titles: [String]
    private let preselected: Int
    var onPick: ((Int) -> Void)?
    var onCancel: (() -> Void)?

    init(titles: [String], preselected: Int) {
        self.titles = titles
        self.preselected = preselected
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tab"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .inset
        tableView.rowHeight = 28
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openClicked(_:))
        tableView.action = #selector(openClicked(_:))
        tableView.chooser = self

        let heading = NSTextField(labelWithString: L10n.string("split.chooser.heading"))
        heading.font = .preferredFont(forTextStyle: .headline)
        let hint = NSTextField(wrappingLabelWithString: L10n.string("split.chooser.hint"))
        hint.font = .preferredFont(forTextStyle: .caption1)
        hint.textColor = .secondaryLabelColor

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        tableView.backgroundColor = .clear

        let view = NSView()
        for subview in [heading, hint, scroll] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 4),
            hint.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scroll.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        self.view = view
        tableView.reloadData()
        if titles.indices.contains(preselected) {
            tableView.selectRowIndexes(IndexSet(integer: preselected), byExtendingSelection: false)
            tableView.scrollRowToVisible(preselected)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { titles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let number = NSTextField(labelWithString: SplitChooser.label(forRow: row) ?? "")
        number.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        number.textColor = .secondaryLabelColor
        number.alignment = .right
        let title = NSTextField(labelWithString: titles[row])
        title.lineBreakMode = .byTruncatingTail
        let cell = NSTableCellView()
        for subview in [number, title] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            number.widthAnchor.constraint(equalToConstant: 18),
            number.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 10),
            title.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        cell.textField = title
        return cell
    }

    @objc private func openClicked(_ sender: Any?) {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        if row >= 0 { onPick?(row) }
    }

    /// Return, Escape and the digits; anything else goes to the table (arrows move the selection).
    fileprivate func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control])
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case KeyCode.returnKey, KeyCode.enter:
            if tableView.selectedRow >= 0 { onPick?(tableView.selectedRow) }
            return true
        case KeyCode.escape:
            onCancel?()
            return true
        default:
            guard let character = event.characters?.first,
                  let row = SplitChooser.row(forDigit: character, rowCount: titles.count) else { return false }
            onPick?(row)
            return true
        }
    }

    /// For `ReaderSmokeTest`: what the list shows.
    var smokeRows: [String] { titles.indices.map { "\(SplitChooser.label(forRow: $0) ?? "-") \(titles[$0])" } }
    /// For `ReaderSmokeTest`: the choice a click, Return or a digit would make.
    func smokePick(_ row: Int) { onPick?(row) }
}

/// A table that hands Return, Escape and the digits to its chooser.
@MainActor
final class ChooserTableView: NSTableView {
    fileprivate weak var chooser: SplitChooserViewController?

    override func keyDown(with event: NSEvent) {
        if chooser?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }
}
