import AppKit
import AomidoriCore

/// Settings (`⌘;`, also `⌘,`), two tabs: Features (how links open) and Updates (Sparkle's
/// automatic check, and a check now). Changes apply at once; there is nothing to confirm.
/// Author: Rocco Casadei, a.k.a. Roccobot
@MainActor
final class SettingsWindowController: NSWindowController {
    private let tabs = NSTabViewController()
    private let features = FeaturesSettingsViewController()
    private let updates = UpdatesSettingsViewController()

    init() {
        super.init(window: nil)
        tabs.tabStyle = .toolbar
        let pages: [(NSViewController, String, String)] = [
            (features, "settings.features", "switch.2"),
            (updates, "settings.updates", "arrow.triangle.2.circlepath"),
        ]
        for (controller, key, symbol) in pages {
            // The window takes the chosen tab's name as its title, as Settings do on the Mac.
            controller.title = L10n.string(key)
            let item = NSTabViewItem(viewController: controller)
            item.label = L10n.string(key)
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L10n.string(key))
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isRestorable = false
        // The first tab's size, laid out: the window would otherwise keep a default height.
        window.setContentSize(features.preferredContentSize)
        window.center()
        self.window = window
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func showWindow(_ sender: Any?) {
        features.refresh()
        updates.refresh()
        super.showWindow(sender)
    }

    /// For the launch smoke test.
    var smokeTabLabels: [String] { tabs.tabViewItems.map(\.label) }
    func smokeSelectTab(_ index: Int) { tabs.selectedTabViewItemIndex = index }
    var smokeFeatureStates: [String: Bool] { features.smokeStates }
}

/// Settings › Features.
@MainActor
private final class FeaturesSettingsViewController: NSViewController {
    private let environment = ReaderEnvironment.shared
    private let newTabs = NSButton(checkboxWithTitle: L10n.string("settings.features.newTabs"), target: nil, action: nil)
    private let nextToSource = NSButton(checkboxWithTitle: L10n.string("settings.features.nextToSource"), target: nil, action: nil)

    override func loadView() {
        newTabs.target = self
        newTabs.action = #selector(changed(_:))
        nextToSource.target = self
        nextToSource.action = #selector(changed(_:))
        let note = NSTextField(wrappingLabelWithString: L10n.string("settings.features.note"))
        note.font = .preferredFont(forTextStyle: .caption1)
        note.textColor = .secondaryLabelColor

        // The second option depends on the first: indented under it.
        view = SettingsPage.make([(newTabs, 0, 8), (nextToSource, 20, 14), (note, 0, 0)])
        preferredContentSize = view.frame.size
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        newTabs.state = environment.opensLinksInNewTabs ? .on : .off
        nextToSource.state = environment.opensLinksNextToSource ? .on : .off
        nextToSource.isEnabled = environment.opensLinksInNewTabs
    }

    @objc private func changed(_ sender: NSButton) {
        if sender === newTabs { environment.opensLinksInNewTabs = sender.state == .on }
        if sender === nextToSource { environment.opensLinksNextToSource = sender.state == .on }
        refresh()
    }

    var smokeStates: [String: Bool] {
        loadViewIfNeeded()
        return ["newTabs": newTabs.state == .on, "nextToSource": nextToSource.state == .on,
                "nextToSourceEnabled": nextToSource.isEnabled]
    }
}

/// Settings › Updates: Sparkle's automatic daily check, and a check now.
@MainActor
private final class UpdatesSettingsViewController: NSViewController {
    private let automatic = NSButton(checkboxWithTitle: L10n.string("settings.updates.automatic"), target: nil, action: nil)
    private let checkNow = NSButton(title: L10n.string("settings.updates.checkNow"), target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        automatic.target = self
        automatic.action = #selector(automaticChanged(_:))
        checkNow.target = self
        checkNow.action = #selector(checkNowClicked(_:))
        checkNow.bezelStyle = .push
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .secondaryLabelColor

        status.stringValue = Self.statusText
        view = SettingsPage.make([(automatic, 0, 12), (checkNow, 0, 12), (status, 0, 0)])
        preferredContentSize = view.frame.size
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        let updater = Updater.shared
        automatic.state = updater.automaticallyChecksForUpdates ? .on : .off
        automatic.isEnabled = updater.isRunning
        checkNow.isEnabled = updater.canCheckForUpdates
        status.stringValue = Self.statusText
    }

    private static var statusText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return Updater.shared.isRunning
            ? L10n.format("settings.updates.version", version)
            : L10n.string("settings.updates.off")
    }

    @objc private func automaticChanged(_ sender: NSButton) {
        Updater.shared.automaticallyChecksForUpdates = sender.state == .on
        refresh()
    }

    @objc private func checkNowClicked(_ sender: Any?) {
        Updater.shared.checkForUpdates(sender)
    }
}

/// A settings tab's content: its controls one below the other, 460 points wide, as tall as they
/// need. Its size is fixed once laid out, so the window takes it when the tab is chosen.
@MainActor
private enum SettingsPage {
    static let width: CGFloat = 460
    static let margin = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

    /// Each row: the control, its indent, the space after it.
    static func make(_ rows: [(NSView, CGFloat, CGFloat)]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = margin
        for (view, indent, spacing) in rows {
            let available = width - margin.left - margin.right - indent
            if let label = view as? NSTextField { label.preferredMaxLayoutWidth = available }
            view.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(view)
            stack.setCustomSpacing(spacing, after: view)
            view.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: margin.left + indent).isActive = true
            view.widthAnchor.constraint(lessThanOrEqualToConstant: available).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        stack.setFrameSize(stack.fittingSize)
        return stack
    }
}
