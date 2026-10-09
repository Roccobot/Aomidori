import AppKit
import AomidoriCore

/// The menu bar, built in code (no nib). Every reading feature is here with its shortcut.
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
        menu.addItem(.separator())
        let services = NSMenu(title: L10n.string("menu.app.services"))
        NSApp.servicesMenu = services
        menu.addItem(submenu(services))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.app.hide"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(L10n.string("menu.app.hideOthers"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(L10n.string("menu.app.showAll"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.app.quit"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.file"))
        menu.addItem(item(L10n.string("menu.file.open"), #selector(NSDocumentController.openDocument(_:)), "o"))
        // AppKit fills the recent documents menu it finds through `clearRecentDocuments:`.
        let recent = NSMenu(title: L10n.string("menu.file.openRecent"))
        recent.addItem(item(L10n.string("menu.file.clearRecent"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.file.inspector"), #selector(ReaderWindowController.showInspector(_:)), "i"))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.file.close"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.edit"))
        menu.addItem(item(L10n.string("menu.edit.copy"), #selector(NSText.copy(_:)), "c"))
        menu.addItem(item(L10n.string("menu.edit.selectAll"), #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.edit.find"), #selector(ReaderWindowController.showSearch(_:)), "f"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.view"))
        menu.addItem(item(L10n.string("menu.view.sidebar"), #selector(NSSplitViewController.toggleSidebar(_:)), "\\"))
        // Every pane keeps its digit; the ones not built yet are simply not listed.
        for pane in SidebarPane.available {
            let paneItem = item(pane.title, #selector(ReaderWindowController.showSidebarPane(_:)), "\(pane.shortcutDigit)", [.command, .option])
            paneItem.tag = pane.shortcutDigit
            paneItem.indentationLevel = 1
            menu.addItem(paneItem)
        }
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.minimal"), #selector(ReaderWindowController.toggleMinimalMode(_:)), "m", [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.night"), #selector(AppDelegate.toggleNight(_:)), "n", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.larger"), #selector(AppDelegate.increaseTextSize(_:)), "+"))
        menu.addItem(item(L10n.string("menu.view.smaller"), #selector(AppDelegate.decreaseTextSize(_:)), "-"))
        menu.addItem(item(L10n.string("menu.view.actualSize"), #selector(AppDelegate.resetTextSize(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.view.fullScreen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.go"))
        menu.addItem(item(L10n.string("menu.go.previousChapter"), #selector(ReaderWindowController.goToPreviousChapter(_:)),
                          String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!), []))
        menu.addItem(item(L10n.string("menu.go.nextChapter"), #selector(ReaderWindowController.goToNextChapter(_:)),
                          String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!), []))
        menu.addItem(.separator())
        // WKWebView implements goBack:/goForward: over its history of chapters and links.
        menu.addItem(item(L10n.string("menu.go.back"), Selector(("goBack:")), "["))
        menu.addItem(item(L10n.string("menu.go.forward"), Selector(("goForward:")), "]"))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.go.addBookmark"), #selector(ReaderWindowController.addBookmark(_:)), "d"))
        return menu
    }

    private static func styleMenu(updater: StyleMenuUpdater) -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.style"))
        menu.delegate = updater
        menu.addItem(item(L10n.string("menu.style.override"), #selector(AppDelegate.toggleStyleOverride(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.style.previous"), #selector(AppDelegate.previousStyle(_:)), "'"))
        menu.addItem(item(L10n.string("menu.style.next"), #selector(AppDelegate.nextStyle(_:)), "\u{00EC}"))
        menu.addItem(item(L10n.string("menu.style.list"), #selector(ReaderWindowController.showStyleList(_:)), "1"))
        menu.addItem(.separator())
        StyleMenu.refresh(menu)
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.style.reload"), #selector(AppDelegate.reloadStyle(_:)), "r"))
        menu.addItem(item(L10n.string("menu.style.showFolder"), #selector(AppDelegate.showStylesFolder(_:))))
        menu.addItem(.separator())
        for fontItem in fontItems() { menu.addItem(fontItem) }
        return menu
    }

    /// The custom font commands, shared by the Style menu and the toolbar's style menu.
    static func fontItems() -> [NSMenuItem] {
        [
            item(L10n.string("menu.style.customFont"), #selector(AppDelegate.toggleCustomFont(_:)), "f", [.command, .shift]),
            item(L10n.string("menu.style.chooseFont"), #selector(AppDelegate.showFontPicker(_:)), "f", [.command, .option]),
            item(L10n.string("menu.style.loadFont"), #selector(AppDelegate.loadFontFile(_:))),
        ]
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L10n.string("menu.window"))
        menu.addItem(item(L10n.string("menu.window.minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(L10n.string("menu.window.zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L10n.string("menu.window.bringAll"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
