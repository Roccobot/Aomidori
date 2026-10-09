import Foundation
import Testing
@testable import AomidoriCore

@Suite("Book state")
struct BookStateTests {
    @Test func bookmarksAndPaneRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-books-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = BookStateStore(fileURL: url)
        let late = Bookmark(title: "Fine", spinePath: "b.xhtml", spineIndex: 3, fraction: 0.9)
        let early = Bookmark(title: "Inizio", spinePath: "a.xhtml", spineIndex: 1, fraction: 2)
        store.update(forBook: "libro") { $0.bookmarks += [late, early]; $0.sidebarPane = .bookmarks }
        try store.save()

        let reloaded = BookStateStore(fileURL: url).state(forBook: "libro")
        #expect(reloaded.sidebarPane == .bookmarks)
        #expect(reloaded.sortedBookmarks.map(\.title) == ["Inizio", "Fine"])
        #expect(reloaded.sortedBookmarks.first?.fraction == 1) // clamped
        #expect(BookStateStore(fileURL: url).state(forBook: "altro") == BookState())
    }

    @Test func emptyStatesAreDroppedAndUnknownPanesTolerated() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-books-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"libro":{"bookmarks":[],"sidebarPane":"timeline"}}"#.utf8).write(to: url)
        let store = BookStateStore(fileURL: url)
        #expect(store.state(forBook: "libro") == BookState())
        store.update(forBook: "libro") { $0.sidebarPane = nil }
        try store.save()
        #expect(try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "{\n\n}")
    }

    @Test func panesKeepStableShortcuts() {
        #expect(SidebarPane.allCases.map(\.shortcutDigit) == [1, 2, 3, 4, 5, 6])
        #expect(SidebarPane.available == [.contents, .bookmarks, .search])
        #expect(SidebarPane.search.shortcutDigit == 5)
    }
}
