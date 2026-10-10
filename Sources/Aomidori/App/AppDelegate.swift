import AppKit
import AomidoriCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let environment = ReaderEnvironment.shared
    private let styleMenuUpdater = StyleMenuUpdater()
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(styleMenuUpdater: styleMenuUpdater)
        ScreenshotSession.applyTheme()
        environment.start()
        installKeyMonitor()
    }

    /// Unsaved Playground changes are reviewed before quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let playground, playground.isDirty else { return .terminateNow }
        playground.reviewUnsavedChanges { proceed in
            NSApp.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.saveStateNow()
    }

    /// Shortcuts are designed for the Italian layout (`⌘'`, `⌘ì`): AppKit must not remap them.
    func applicationShouldAutomaticallyLocalizeKeyEquivalents(_ application: NSApplication) -> Bool {
        false
    }

    /// AppKit asks for an untitled file only when nothing else opens: at launch with no book
    /// to open (from Finder or restored), and when the Dock icon is clicked with no windows.
    /// Aomidori has no untitled books: it shows the empty reader window instead.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // `-AomidoriPlayground YES` (or a Playground smoke test) starts with the Playground.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "AomidoriPlayground") || defaults.string(forKey: PlaygroundSmokeTest.defaultsKey) != nil {
            showPlayground(nil)
        } else {
            EmptyReaderWindowController.show()
        }
        return true
    }

    /// `⌘T` with no reader or empty window in front (none open, or the Playground): an empty
    /// window, as a tab of the main reader window if there is one.
    @objc func newWindowForTab(_ sender: Any?) {
        let main = NSApp.mainWindow.flatMap { $0.tabbingIdentifier == ReaderWindowController.tabbingIdentifier ? $0 : nil }
        EmptyReaderWindowController.openNewTab(besides: main)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.start()
        if LaunchSmokeTest.isActive { launchSmokeTest = LaunchSmokeTest() }
        // AppKit does not always ask for the untitled file (a background launch, `open -g`, got
        // no window): once launching is over, the empty window is shown if nothing opened. A book
        // that arrives later takes its place.
        Task { @MainActor in
            guard NSDocumentController.shared.documents.isEmpty, !NSApp.windows.contains(where: \.isVisible) else { return }
            _ = applicationOpenUntitledFile(NSApp)
        }
    }

    private var launchSmokeTest: LaunchSmokeTest?

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Routes keys (and scrolling, for the chapter-edge toast) to the active reader window before
    /// the menu bar and the web view see them.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .scrollWheel]) { event in
            let consumed = MainActor.assumeIsolated {
                (NSApp.keyWindow?.windowController as? ReaderWindowController)?.handle(event) ?? false
            }
            return consumed ? nil : event
        }
    }

    // MARK: Updates

    @objc func checkForUpdates(_ sender: Any?) { Updater.shared.checkForUpdates(sender) }

    // MARK: Global reading actions

    @objc func toggleNight(_ sender: Any?) { environment.toggleNight() }
    @objc func toggleStyleOverride(_ sender: Any?) { environment.toggleOverride() }
    @objc func toggleJustified(_ sender: Any?) { environment.toggleJustified() }
    @objc func previousStyle(_ sender: Any?) { environment.cycleStyle(by: -1) }
    @objc func nextStyle(_ sender: Any?) { environment.cycleStyle(by: 1) }

    @objc func selectStyle(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        environment.selectStyle(named: name)
    }

    @objc func increaseTextSize(_ sender: Any?) { environment.setTextScale(TextScale.larger(than: environment.textScale)) }
    @objc func decreaseTextSize(_ sender: Any?) { environment.setTextScale(TextScale.smaller(than: environment.textScale)) }
    @objc func resetTextSize(_ sender: Any?) { environment.setTextScale(TextScale.normal) }

    @objc func showStylesFolder(_ sender: Any?) {
        NSWorkspace.shared.open(AppPaths.styles)
    }

    /// `⌘R` with no reader window in front (the empty window, the Playground): reads the
    /// styles and fonts from disk again. A reader window also reloads its chapter; see
    /// `ReaderWindowController.reloadPage(_:)`.
    @objc func reloadPage(_ sender: Any?) { environment.reloadStyle() }

    // MARK: CSS Playground

    private var playground: PlaygroundWindowController?

    /// `⇧⌘P`: one Playground window, kept (with its buffer) when closed.
    @objc func showPlayground(_ sender: Any?) {
        let controller = playground ?? PlaygroundWindowController()
        playground = controller
        controller.showWindow(sender)
    }

    // MARK: Custom font

    private lazy var fontPicker = FontPickerWindowController()

    /// `⌘S` (outside the Playground): book or style font ↔ custom font; the first time, the chooser opens to define one.
    @objc func toggleCustomFont(_ sender: Any?) {
        if !environment.toggleCustomFont() { showFontPicker(sender) }
    }

    /// `⇧⌘T`: define the custom font.
    @objc func showFontPicker(_ sender: Any?) {
        fontPicker.showWindow(sender)
    }

    /// `⌘T`: the system Font panel, showing the custom font. What is picked there (family,
    /// face, the axes of a variable font, Typography features) becomes the custom font. Size
    /// and effects are not offered: the style and the text size controls own those.
    @objc func showFontPanel(_ sender: Any?) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        let size = NSFont.systemFontSize * 1.5
        let font = environment.customFontChoice.flatMap { FontChoiceConversion.font(for: $0, size: size) }
            ?? NSFont.systemFont(ofSize: size)
        manager.setSelectedFont(font, isMultiple: false)
        manager.orderFrontFontPanel(sender)
    }

    /// Sent by the Font panel for every change made in it.
    @objc func changeFont(_ sender: Any?) {
        let manager = sender as? NSFontManager ?? NSFontManager.shared
        let current = manager.selectedFont ?? NSFont.systemFont(ofSize: NSFont.systemFontSize * 1.5)
        let font = manager.convert(current)
        manager.setSelectedFont(font, isMultiple: false)
        environment.setCustomFont(FontChoiceConversion.choice(from: font).choice)
    }

    @objc func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.face, .collection]
    }

    @objc func loadFontFile(_ sender: Any?) {
        let window = fontPicker.window?.isVisible == true ? fontPicker.window : NSApp.keyWindow
        FontPickerWindowController.runLoadPanel(attachedTo: window) { [weak self] families in
            guard let self else { return }
            fontPicker.didLoad(families: families)
            fontPicker.showWindow(nil)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)):
            return Updater.shared.canCheckForUpdates
        case #selector(toggleNight(_:)):
            menuItem.state = environment.isNight ? .on : .off
        case #selector(toggleStyleOverride(_:)):
            menuItem.state = environment.overrideEnabled ? .on : .off
        case #selector(toggleJustified(_:)):
            menuItem.state = environment.justified ? .on : .off
        case #selector(toggleCustomFont(_:)):
            menuItem.state = environment.customFontEnabled ? .on : .off
            menuItem.title = environment.customFontChoice.map {
                L10n.format("menu.style.customFont.named", FontChoiceConversion.displayName(of: $0))
            } ?? L10n.string("menu.style.customFont")
        case #selector(previousStyle(_:)), #selector(nextStyle(_:)):
            return environment.styles.count > 0
        case #selector(increaseTextSize(_:)):
            return environment.textScale < TextScale.steps[TextScale.steps.count - 1]
        case #selector(decreaseTextSize(_:)):
            return environment.textScale > TextScale.steps[0]
        case #selector(resetTextSize(_:)):
            return environment.textScale != TextScale.normal
        default:
            break
        }
        return true
    }
}
