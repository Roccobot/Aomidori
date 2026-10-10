import Foundation

/// Where a link in the book opens, from Settings › Features and the modifier keys of the click
/// (Rocco's requests).
///
/// - "Open links in new tabs" off (the default): a click follows the link in place; `⇧`-click
///   opens it in a new tab in front, `⌥`-click in a new tab behind the current one.
/// - On: a click opens a new tab in front; `⌥`-click still opens it behind. New tabs go next to
///   their source tab, or at the end of the tab bar when "Open each link next to its source
///   tab" is off.
///
/// Links that leave the book (web, mail) always go to the browser or the mail client.
/// Author: Rocco Casadei, a.k.a. Roccobot
public enum LinkOpening: Equatable, Sendable {
    case here
    case newTab(inBackground: Bool)

    public static func decide(newTabsSetting: Bool, modifiers: KeyShortcut.Modifiers) -> LinkOpening {
        if modifiers.contains(.option) { return .newTab(inBackground: true) }
        if modifiers.contains(.shift) || newTabsSetting { return .newTab(inBackground: false) }
        return .here
    }

    public enum Placement: Equatable, Sendable {
        case nextToSource
        case end
    }

    /// "Next to its source tab" depends on "Open links in new tabs": with that off, the tabs
    /// opened by `⇧`/`⌥`-click always go next to their source.
    public static func placement(newTabsSetting: Bool, nextToSourceSetting: Bool) -> Placement {
        newTabsSetting && !nextToSourceSetting ? .end : .nextToSource
    }
}
