import Foundation

/// What becomes of the items WebKit puts in a page's context menu. Aomidori opens no web windows
/// and handles no downloads, so the items that would do either did nothing (Rocco's report,
/// 1.01): they go. On a link inside the book, "Open Link in New Window" becomes "Open Link in New
/// Tab", which opens a tab in Aomidori as a ⇧-click does. Everything else stays as WebKit made it.
/// The identifiers are the values of WebKit's `_WKMenuItemIdentifier…` constants.
/// Author: Rocco Casadei, a.k.a. Roccobot
public enum PageContextMenu {
    public enum Action: Equatable, Sendable {
        case keep
        case remove
        case openInNewTab
    }

    static let newWindowLink = "WKMenuItemIdentifierOpenLinkInNewWindow"
    static let unavailable: Set<String> = [
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierOpenFrameInNewWindow",
        "WKMenuItemIdentifierOpenMediaInNewWindow",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierDownloadMedia",
    ]

    /// - Parameter canOpenInNewTab: the item is on a link inside the book, and the page can open tabs.
    public static func action(for identifier: String?, canOpenInNewTab: Bool) -> Action {
        guard let identifier else { return .keep }
        if identifier == newWindowLink { return canOpenInNewTab ? .openInNewTab : .remove }
        return unavailable.contains(identifier) ? .remove : .keep
    }
}
