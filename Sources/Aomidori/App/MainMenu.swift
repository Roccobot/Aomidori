import AppKit
import AomidoriCore

/// The menu bar, built in code (no nib). Every reading feature is here with its shortcut;
/// the shortcuts themselves are in `Shortcuts.table` (AomidoriCore).
@MainActor
enum MainMenu {
    static func build(styleMenuUpdater: StyleMenuUpdater) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(goMenu()))
        main.addItem(submenu(styleMenu(updater: styleMenuUpdater)))
        let window = windowMenu()
        main.addItem(submenu(window))
        let help = NSMenu(title: L10n.string("menu.help"))
        main.addItem(submenu(help))
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
        return main
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Aomidori")
        menu.addItem(item(L10n.string("menu.app.about"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        // Sparkle's usual place, with no shortcut, as in other Mac apps.
        menu.addItem(item(L10n.string("menu.app.checkForUpdates"), #selector(AppDelegate.checkForUpdates(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: L10n.string("menu.app.services"))
        NSApp.servicesMenu = services
        menu.addItem(submenu(services))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.app.hide"), #selector(NSApplication.hide(_:)), .hide))
        menu.addItem(item(L10n.string("menu.app.hideOthers"), #selector(NSApplication.hideOtherApplications(_:)), .hideOthers))
        menu.addItem(item(L10n.string("menu.app.showAll"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.app.quit"), #selector(NSApplication.terminate(_:)), .quit))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.file"))
        menu.addItem(item(L10n.string("menu.file.newTab"), #selector(NSResponder.newWindowForTab(_:)), .newTab))
        menu.addItem(item(L10n.string("menu.file.open"), #selector(NSDocumentController.openDocument(_:)), .open))
        // AppKit fills the recent documents menu it finds through `clearRecentDocuments:`.
        let recent = NSMenu(title: L10n.string("menu.file.openRecent"))
        recent.addItem(item(L10n.string("menu.file.clearRecent"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.file.inspector"), #selector(ReaderWindowController.showInspector(_:)), .inspector))
        menu.addItem(.separator())
        // CSS Playground commands: enabled while the Playground window is in front.
        menu.addItem(item(L10n.string("menu.playground.openCSS"), #selector(PlaygroundWindowController.openCSSFile(_:)), .playgroundOpenCSS))
        menu.addItem(item(L10n.string("menu.playground.loadEPUB"), #selector(PlaygroundWindowController.loadPlaygroundEPUB(_:)), .playgroundLoadEPUB))
        menu.addItem(item(L10n.string("menu.playground.sample"), #selector(PlaygroundWindowController.showSampleText(_:)), .playgroundSample))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.file.close"), #selector(NSWindow.performClose(_:)), .close))
        menu.addItem(item(L10n.string("menu.playground.saveToStyles"), #selector(PlaygroundWindowController.saveToStyles(_:)), .playgroundSave))
        menu.addItem(item(L10n.string("menu.playground.saveAs"), #selector(PlaygroundWindowController.saveCSSAs(_:)), .playgroundSaveAs))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.edit"))
        menu.addItem(item(L10n.string("menu.edit.undo"), Selector(("undo:")), .undo))
        menu.addItem(item(L10n.string("menu.edit.redo"), Selector(("redo:")), .redo))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.edit.cut"), #selector(NSText.cut(_:)), .cut))
        menu.addItem(item(L10n.string("menu.edit.copy"), #selector(NSText.copy(_:)), .copy))
        menu.addItem(item(L10n.string("menu.edit.paste"), #selector(NSText.paste(_:)), .paste))
        menu.addItem(item(L10n.string("menu.edit.selectAll"), #selector(NSText.selectAll(_:)), .selectAll))
        menu.addItem(.separator())
        // The reader's search pane, or the Playground editor's find bar.
        menu.addItem(item(L10n.string("menu.edit.find"), #selector(ReaderWindowController.showSearch(_:)), .find))
        let finder: [(String, NSTextFinder.Action, ShortcutCommand)] = [
            ("menu.edit.findNext", .nextMatch, .findNext),
            ("menu.edit.findPrevious", .previousMatch, .findPrevious),
            ("menu.edit.useSelectionForFind", .setSearchString, .useSelectionForFind),
        ]
        for (key, action, command) in finder {
            let finderItem = item(L10n.string(key), #selector(NSTextView.performTextFinderAction(_:)), command)
            finderItem.tag = action.rawValue
            menu.addItem(finderItem)
        }
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.view"))
        menu.addItem(item(L10n.string("menu.view.sidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), .sidebar))
        // Every pane keeps its digit; the ones not built yet are simply not listed.
        for pane in SidebarPane.available {
            let paneItem = item(pane.title, #selector(ReaderWindowController.showSidebarPane(_:)), Shortcuts.sidebarPane(pane.shortcutDigit))
            paneItem.tag = pane.shortcutDigit
            paneItem.indentationLevel = 1
            menu.addItem(paneItem)
        }
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.minimal"), #selector(ReaderWindowController.toggleMinimalMode(_:)), .minimal))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.night"), #selector(AppDelegate.toggleNight(_:)), .night))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.larger"), #selector(AppDelegate.increaseTextSize(_:)), .larger))
        menu.addItem(item(L10n.string("menu.view.smaller"), #selector(AppDelegate.decreaseTextSize(_:)), .smaller))
        menu.addItem(item(L10n.string("menu.view.actualSize"), #selector(AppDelegate.resetTextSize(_:)), .actualSize))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.fullScreen"), #selector(NSWindow.toggleFullScreen(_:)), .fullScreen))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.go"))
        menu.addItem(item(L10n.string("menu.go.previousChapter"), #selector(ReaderWindowController.goToPreviousChapter(_:)), .previousChapter))
        menu.addItem(item(L10n.string("menu.go.nextChapter"), #selector(ReaderWindowController.goToNextChapter(_:)), .nextChapter))
        menu.addItem(.separator())
        // WKWebView implements goBack:/goForward: over its history of chapters and links.
        menu.addItem(item(L10n.string("menu.go.back"), Selector(("goBack:")), .back))
        menu.addItem(item(L10n.string("menu.go.forward"), Selector(("goForward:")), .forward))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.go.addBookmark"), #selector(ReaderWindowController.addBookmark(_:)), .addBookmark))
        return menu
    }

    private static func styleMenu(updater: StyleMenuUpdater) -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.style"))
        menu.delegate = updater
        menu.addItem(item(L10n.string("menu.style.override"), #selector(AppDelegate.toggleStyleOverride(_:)), .override))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.style.previous"), #selector(AppDelegate.previousStyle(_:)), .previousStyle))
        menu.addItem(item(L10n.string("menu.style.next"), #selector(AppDelegate.nextStyle(_:)), .nextStyle))
        menu.addItem(item(L10n.string("menu.style.list"), #selector(ReaderWindowController.showStyleList(_:)), .styleList))
        menu.addItem(.separator())
        StyleMenu.refresh(menu)
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.style.reload"), #selector(AppDelegate.reloadPage(_:)), .reload))
        menu.addItem(item(L10n.string("menu.style.showFolder"), #selector(AppDelegate.showStylesFolder(_:))))
        menu.addItem(item(L10n.string("menu.style.playground"), #selector(AppDelegate.showPlayground(_:)), .playground))
        menu.addItem(.separator())
        for fontItem in fontItems() { menu.addItem(fontItem) }
        return menu
    }

    /// The custom font commands, shared by the Style menu and the toolbar's style menu.
    static func fontItems() -> [NSMenuItem] {
        [
            item(L10n.string("menu.style.customFont"), #selector(AppDelegate.toggleCustomFont(_:)), .customFont),
            item(L10n.string("menu.style.chooseFont"), #selector(AppDelegate.showFontPicker(_:)), .defineFont),
            item(L10n.string("menu.style.fontPanel"), #selector(AppDelegate.showFontPanel(_:))),
            item(L10n.string("menu.style.loadFont"), #selector(AppDelegate.loadFontFile(_:))),
        ]
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.window"))
        menu.addItem(item(L10n.string("menu.window.minimize"), #selector(NSWindow.performMiniaturize(_:)), .minimize))
        menu.addItem(item(L10n.string("menu.window.zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.window.bringAll"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    /// A menu item with the command's shortcut from `Shortcuts.table`.
    static func item(_ title: String, _ action: Selector?, _ command: ShortcutCommand) -> NSMenuItem {
        item(title, action, Shortcuts.shortcut(command))
    }

    static func item(_ title: String, _ action: Selector?, _ shortcut: KeyShortcut? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.key ?? "")
        if let shortcut { item.keyEquivalentModifierMask = modifierFlags(shortcut.modifiers) }
        return item
    }

    static func modifierFlags(_ modifiers: KeyShortcut.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

extension KeyShortcut.Modifiers {
    /// The shortcut modifiers held in an event's flags.
    init(_ flags: NSEvent.ModifierFlags) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}
