import AppKit
import AomidoriCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private let environment = ReaderEnvironment.shared
    private let styleMenuUpdater = StyleMenuUpdater()
    private var keyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build(styleMenuUpdater: styleMenuUpdater)
        environment.start()
        installKeyMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment.saveStateNow()
    }

    /// Shortcuts are designed for the Italian layout (`⌘'`, `⌘ì`): AppKit must not remap them.
    func applicationShouldAutomaticallyLocalizeKeyEquivalents(_ application: NSApplication) -> Bool {
        false
    }

    /// Launching (or clicking the Dock icon) with no book open shows the Open panel.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Routes keys to the active reader window before the menu bar and the web view see them.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]) { event in
            let consumed = MainActor.assumeIsolated {
                (NSApp.keyWindow?.windowController as? ReaderWindowController)?.handle(event) ?? false
            }
            return consumed ? nil : event
        }
    }

    // MARK: Global reading actions

    @objc func toggleNight(_ sender: Any?) { environment.toggleNight() }
    @objc func toggleStyleOverride(_ sender: Any?) { environment.toggleOverride() }
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

    /// `⌘R`: reads the active style (and the fonts folder) from disk again.
    @objc func reloadStyle(_ sender: Any?) { environment.reloadStyle() }

    // MARK: Custom font

    private lazy var fontPicker = FontPickerWindowController()

    /// `⇧⌘F`: the custom font on or off; the first time, the font panel opens to choose one.
    @objc func toggleCustomFont(_ sender: Any?) {
        if !environment.toggleCustomFont() { showFontPicker(sender) }
    }

    /// `⌥⌘F`
    @objc func showFontPicker(_ sender: Any?) {
        fontPicker.showWindow(sender)
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
        case #selector(toggleNight(_:)):
            menuItem.state = environment.isNight ? .on : .off
        case #selector(toggleStyleOverride(_:)):
            menuItem.state = environment.overrideEnabled ? .on : .off
        case #selector(toggleCustomFont(_:)):
            menuItem.state = environment.customFontEnabled ? .on : .off
            menuItem.title = environment.customFontFamily.map { L10n.format("menu.style.customFont.named", $0) }
                ?? L10n.string("menu.style.customFont")
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
