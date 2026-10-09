import AppKit

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
        let help = NSMenu(title: "Aiuto")
        main.addItem(submenu(help))
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
        return main
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Aomidori")
        menu.addItem(item("Informazioni su Aomidori", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: "Servizi")
        NSApp.servicesMenu = services
        menu.addItem(submenu(services))
        menu.addItem(.separator())
        menu.addItem(item("Nascondi Aomidori", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Nascondi altre", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Mostra tutte", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Esci da Aomidori", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "Archivio")
        menu.addItem(item("Apri\u{2026}", #selector(NSDocumentController.openDocument(_:)), "o"))
        // AppKit fills the recent documents menu it finds through `clearRecentDocuments:`.
        let recent = NSMenu(title: "Apri recenti")
        recent.addItem(item("Cancella menu", #selector(NSDocumentController.clearRecentDocuments(_:))))
        menu.addItem(submenu(recent))
        menu.addItem(.separator())
        menu.addItem(item("Chiudi", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Composizione")
        menu.addItem(item("Copia", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Seleziona tutto", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "Vista")
        menu.addItem(item("Mostra/nascondi indice", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("Modalit\u{00E0} minimale", #selector(ReaderWindowController.toggleMinimalMode(_:)), "m", [.command, .control]))
        menu.addItem(.separator())
        menu.addItem(item("Notte", #selector(AppDelegate.toggleNight(_:)), "n", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Ingrandisci testo", #selector(AppDelegate.increaseTextSize(_:)), "+"))
        menu.addItem(item("Riduci testo", #selector(AppDelegate.decreaseTextSize(_:)), "-"))
        menu.addItem(item("Dimensione originale", #selector(AppDelegate.resetTextSize(_:)), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Entra in modalit\u{00E0} a tutto schermo", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Vai")
        menu.addItem(item("Capitolo precedente", #selector(ReaderWindowController.goToPreviousChapter(_:)),
                          String(UnicodeScalar(UInt16(NSLeftArrowFunctionKey))!), []))
        menu.addItem(item("Capitolo successivo", #selector(ReaderWindowController.goToNextChapter(_:)),
                          String(UnicodeScalar(UInt16(NSRightArrowFunctionKey))!), []))
        menu.addItem(.separator())
        // WKWebView implements goBack:/goForward: over its history of chapters and links.
        menu.addItem(item("Indietro", Selector(("goBack:")), "["))
        menu.addItem(item("Avanti", Selector(("goForward:")), "]"))
        return menu
    }

    private static func styleMenu(updater: StyleMenuUpdater) -> NSMenu {
        let menu = NSMenu(title: "Stile")
        menu.delegate = updater
        menu.addItem(item("Sovrascrivi stile del libro", #selector(AppDelegate.toggleStyleOverride(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item("Stile precedente", #selector(AppDelegate.previousStyle(_:)), "'"))
        menu.addItem(item("Stile successivo", #selector(AppDelegate.nextStyle(_:)), "\u{00EC}"))
        menu.addItem(item("Elenco stili\u{2026}", #selector(ReaderWindowController.showStyleList(_:)), "1"))
        menu.addItem(.separator())
        StyleMenu.refresh(menu)
        menu.addItem(.separator())
        menu.addItem(item("Mostra cartella stili", #selector(AppDelegate.showStylesFolder(_:))))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Finestra")
        menu.addItem(item("Contrai", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Porta tutto in primo piano", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
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
