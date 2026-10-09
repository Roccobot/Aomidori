import AppKit

/// Builds the list of user styles shown in the Style menu and in the toolbar's style menu.
@MainActor
enum StyleMenu {
    static let itemTag = 7_001

    /// One item per style; the active one is checked (with a dash when the override is off).
    static func items() -> [NSMenuItem] {
        let environment = ReaderEnvironment.shared
        let active = environment.activeStyle?.name
        guard !environment.styles.isEmpty else {
            let empty = NSMenuItem(title: "Nessuno stile nella cartella", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.tag = itemTag
            return [empty]
        }
        return environment.styles.map { style in
            let item = NSMenuItem(title: style.displayName, action: #selector(AppDelegate.selectStyle(_:)), keyEquivalent: "")
            item.representedObject = style.name
            item.tag = itemTag
            if style.name == active { item.state = environment.overrideEnabled ? .on : .mixed }
            return item
        }
    }

    /// Replaces the style items of `menu` (identified by tag) in place, or appends them.
    static func refresh(_ menu: NSMenu) {
        let existing = menu.items.enumerated().filter { $0.element.tag == itemTag }
        let insertionIndex = existing.first?.offset ?? menu.numberOfItems
        existing.reversed().forEach { menu.removeItem(at: $0.offset) }
        for (offset, item) in items().enumerated() {
            menu.insertItem(item, at: insertionIndex + offset)
        }
    }
}

/// Keeps a menu's style items current each time it opens.
@MainActor
final class StyleMenuUpdater: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        StyleMenu.refresh(menu)
    }
}
