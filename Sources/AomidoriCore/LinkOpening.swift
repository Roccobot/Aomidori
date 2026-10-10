import Foundation

/// Where a link in the book opens, from Settings › Features and the modifier keys of the click
/// (Rocco's requests).
///
/// - "Open links in new tabs" off (the default): a click follows the link in place; `⇧`-click
///   opens it in a new tab in front, `⌥`-click in a new tab behind the current one.
/// - On: a click opens a new tab in front; `⌥`-click still opens it behind.
///
/// Every new tab goes next to its source tab, or at the end of the tab bar when "Open each link
/// next to its source tab" is off: that setting holds whichever way the tab was opened, so it
/// does not depend on the first (Rocco's correction, 1.02).
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

    public static func placement(nextToSourceSetting: Bool) -> Placement {
        nextToSourceSetting ? .nextToSource : .end
    }
}
