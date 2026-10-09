import AppKit
import AomidoriCore

/// The style list HUD (`⌘1` / `⌃⇥`).
///
/// - Quick press: the list stays open; pick with a click, or `↑`/`↓` and `↩`; `esc` cancels.
/// - Hold the modifier: each further press of `1` / `⇥` (with `⇧`: backwards) moves to the next
///   style with a live preview; releasing the modifier keeps the last one (like `⌘⇥`).
@MainActor
final class StylePicker: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private enum Mode: Equatable {
        case holding(NSEvent.ModifierFlags)
        case clicking
    }

    private let environment = ReaderEnvironment.shared
    private var panel: HUDPanel?
    private let tableView = PickerTableView()
    private var styles: [StyleFile] = []
    private var mode: Mode = .clicking
    private var steps = 0
    private var original: (name: String?, overrideEnabled: Bool) = (nil, false)
    private weak var parentWindow: NSWindow?

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Opens the list over `window`. `heldModifier` is the modifier of the opening shortcut,
    /// or `nil` when opened from a menu.
    func show(over window: NSWindow, heldModifier: NSEvent.ModifierFlags?) {
        styles = environment.styles
        guard !styles.isEmpty else { NSSound.beep(); return }
        original = (environment.selectedStyleName, environment.overrideEnabled)
        mode = heldModifier.map(Mode.holding) ?? .clicking
        steps = 0

        let panel = self.panel ?? makePanel()
        self.panel = panel
        tableView.reloadData()
        let current = styles.firstIndex { $0.name == environment.activeStyle?.name } ?? 0
        select(row: current, preview: false)
        layout(panel, over: window)
        parentWindow = window
        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
    }

    /// Handles events while visible. Returns `true` if the event was consumed.
    func handle(_ event: NSEvent) -> Bool {
        guard isVisible else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.type {
        case .flagsChanged:
            if case .holding(let modifier) = mode, !flags.contains(modifier) {
                if steps > 0 { commit() } else { mode = .clicking }
            }
            return false
        case .keyDown:
            let backwards = flags.contains(.shift)
            if Self.isPickerShortcut(event) {
                step(backwards ? -1 : 1)
                return true
            }
            switch event.keyCode {
            case KeyCode.escape: cancel()
            case KeyCode.returnKey, KeyCode.enter: commit()
            case KeyCode.downArrow: step(1)
            case KeyCode.upArrow: step(-1)
            default:
                // Let other ⌘ shortcuts through; swallow plain typing.
                return !flags.contains(.command)
            }
            return true
        case .leftMouseDown, .rightMouseDown:
            if event.window !== panel { commit() }
            return false
        default:
            return false
        }
    }

    /// `⌘1` or `⌃⇥`, with or without `⇧`.
    static func isPickerShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.shift, .capsLock, .function, .numericPad])
        if flags == .control, event.keyCode == KeyCode.tab { return true }
        return flags == .command && event.keyCode == KeyCode.digit1
    }

    private func step(_ delta: Int) {
        guard !styles.isEmpty else { return }
        steps += 1
        let row = ((tableView.selectedRow + delta) % styles.count + styles.count) % styles.count
        select(row: row, preview: true)
    }

    private func select(row: Int, preview: Bool) {
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
        if preview { environment.selectStyle(named: styles[row].name) }
    }

    private func commit() {
        let row = tableView.selectedRow
        if styles.indices.contains(row), environment.activeStyle?.name != styles[row].name || !environment.overrideEnabled {
            environment.selectStyle(named: styles[row].name)
        }
        close()
    }

    private func cancel() {
        if steps > 0 { environment.restoreStyle(named: original.name, overrideEnabled: original.overrideEnabled) }
        close()
    }

    /// Closes the list, keeping whatever is applied.
    func dismiss() {
        close()
    }

    private func close() {
        guard let panel else { return }
        parentWindow?.removeChildWindow(panel)
        panel.orderOut(nil)
        mode = .clicking
        steps = 0
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        guard styles.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        commit()
    }

    // MARK: Panel

    private static let rowHeight: CGFloat = 30
    private static let width: CGFloat = 300

    private func makePanel() -> HUDPanel {
        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let column = NSTableColumn(identifier: .init("style"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked(_:))
        tableView.setAccessibilityLabel(L10n.string("picker.title"))

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let title = NSTextField(labelWithString: L10n.string("picker.title"))
        title.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        title.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 10, bottom: 10, right: 10)
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true

        let glass = NSGlassEffectView()
        glass.cornerRadius = 18
        glass.contentView = stack
        panel.contentView = glass
        return panel
    }

    private func layout(_ panel: HUDPanel, over window: NSWindow) {
        let visibleRows = CGFloat(min(styles.count, 12))
        let height = 12 + 16 + 6 + visibleRows * (Self.rowHeight + 2) + 10
        let frame = window.frame
        let origin = NSPoint(x: frame.midX - Self.width / 2, y: frame.maxY - frame.height * 0.3 - height)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: Self.width, height: height)), display: true)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { styles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("StyleCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let style = styles[row]
        cell.textField?.stringValue = style.displayName
        cell.textField?.font = style.name == environment.defaultStyleName
            ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold) : .systemFont(ofSize: NSFont.systemFontSize)
        return cell
    }
}

/// A floating panel that never takes the keyboard: the reader window stays key and the app's
/// event monitor routes keys to the picker.
private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Rows respond to the first click even though the panel is never key.
private final class PickerTableView: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Virtual key codes (layout-independent physical keys).
enum KeyCode {
    static let digit1: UInt16 = 18
    static let tab: UInt16 = 48
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let escape: UInt16 = 53
    static let delete: UInt16 = 51
    static let forwardDelete: UInt16 = 117
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
}
