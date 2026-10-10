import AppKit

/// The toolbar items for the app-wide reading settings (Night, Style, Justify, Blend, Override), shared
/// by the reader window and the empty window so both have the same chrome.
@MainActor
final class GlobalToolbarItems {
    static let night = NSToolbarItem.Identifier("Aomidori.night")
    static let style = NSToolbarItem.Identifier("Aomidori.style")
    static let justify = NSToolbarItem.Identifier("Aomidori.justify")
    static let blendInk = NSToolbarItem.Identifier("Aomidori.blendInk")
    static let override = NSToolbarItem.Identifier("Aomidori.override")
    static let identifiers = [night, style, justify, blendInk, override]

    private let environment = ReaderEnvironment.shared
    private let styleMenuUpdater = StyleMenuUpdater()
    private weak var nightItem: NSToolbarItem?
    private weak var justifyItem: NSToolbarItem?
    private weak var blendInkItem: NSToolbarItem?
    private weak var overrideItem: NSToolbarItem?

    /// The item for one of `identifiers`, or nil for any other identifier.
    func item(for identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch identifier {
        case Self.night:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("toolbar.night")
            item.toolTip = L10n.string("toolbar.night.help")
            item.action = #selector(AppDelegate.toggleNight(_:))
            item.isBordered = true
            nightItem = item
            update()
            return item
        case Self.style:
            let item = NSMenuToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("menu.style")
            item.toolTip = L10n.string("menu.style")
            item.image = Self.symbol("textformat", L10n.string("menu.style"))
            let menu = NSMenu(title: L10n.string("menu.style"))
            menu.delegate = styleMenuUpdater
            menu.addItem(withTitle: L10n.string("menu.style.list"), action: #selector(ReaderWindowController.showStyleList(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L10n.string("menu.style.reload"), action: #selector(AppDelegate.reloadPage(_:)), keyEquivalent: "")
            menu.addItem(withTitle: L10n.string("menu.style.showFolder"), action: #selector(AppDelegate.showStylesFolder(_:)), keyEquivalent: "")
            menu.addItem(.separator())
            MainMenu.fontItems().forEach { $0.keyEquivalent = ""; menu.addItem($0) }
            menu.addItem(.separator())
            StyleMenu.refresh(menu)
            item.menu = menu
            return item
        case Self.justify:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("toolbar.justify")
            item.toolTip = L10n.string("toolbar.justify.help")
            item.action = #selector(AppDelegate.toggleJustified(_:))
            item.isBordered = true
            justifyItem = item
            update()
            return item
        case Self.blendInk:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("toolbar.blendInk")
            item.toolTip = L10n.string("toolbar.blendInk.help")
            item.action = #selector(AppDelegate.toggleBlendsInk(_:))
            item.isBordered = true
            blendInkItem = item
            update()
            return item
        case Self.override:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = L10n.string("toolbar.override")
            item.toolTip = L10n.string("toolbar.override.help")
            item.action = #selector(AppDelegate.toggleStyleOverride(_:))
            item.isBordered = true
            overrideItem = item
            update()
            return item
        default:
            return nil
        }
    }

    /// Images that show the current state of Night, Justify, Blend and Override.
    func update() {
        let night = environment.isNight
        nightItem?.image = Self.symbol(night ? "moon.fill" : "sun.max", L10n.string(night ? "a11y.night" : "a11y.day"))
        let justified = environment.justified
        justifyItem?.image = Self.symbol(justified ? "text.justify" : "text.alignleft",
                                         L10n.string(justified ? "a11y.justified" : "a11y.flushLeft"))
        let blends = environment.blendsInk
        blendInkItem?.image = Self.symbol(blends ? "circle.lefthalf.filled" : "circle",
                                          L10n.string(blends ? "a11y.blendInk.on" : "a11y.blendInk.off"))
        let overriding = environment.overrideEnabled
        overrideItem?.image = Self.symbol(overriding ? "paintbrush.pointed.fill" : "paintbrush.pointed",
                                          L10n.string(overriding ? "a11y.styleOverridden" : "a11y.bookStyle"))
    }

    static func symbol(_ name: String, _ description: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: description) ?? NSImage()
    }
}
