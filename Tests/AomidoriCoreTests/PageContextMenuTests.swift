import Testing
@testable import AomidoriCore

@Suite("Page context menu")
struct PageContextMenuTests {
    @Test func newWindowsAndDownloadsGo() {
        for name in ["OpenImageInNewWindow", "OpenFrameInNewWindow", "OpenMediaInNewWindow",
                     "DownloadImage", "DownloadLinkedFile", "DownloadMedia"] {
            #expect(PageContextMenu.action(for: "WKMenuItemIdentifier" + name, canOpenInNewTab: true) == .remove, "\(name)")
        }
    }

    @Test func aLinkInTheBookOpensInANewTab() {
        #expect(PageContextMenu.action(for: "WKMenuItemIdentifierOpenLinkInNewWindow", canOpenInNewTab: true) == .openInNewTab)
        #expect(PageContextMenu.action(for: "WKMenuItemIdentifierOpenLinkInNewWindow", canOpenInNewTab: false) == .remove,
                "a link to the web, or a page that opens no tabs (the Playground)")
    }

    @Test func everythingElseStays() {
        #expect(PageContextMenu.action(for: "WKMenuItemIdentifierCopyImage", canOpenInNewTab: true) == .keep)
        #expect(PageContextMenu.action(for: "WKMenuItemIdentifierCopyLink", canOpenInNewTab: true) == .keep)
        #expect(PageContextMenu.action(for: nil, canOpenInNewTab: true) == .keep)
    }
}
