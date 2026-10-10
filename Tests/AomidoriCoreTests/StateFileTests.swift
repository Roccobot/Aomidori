import Foundation
import Testing
@testable import AomidoriCore

@Suite("State files")
struct StateFileTests {
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A file the store cannot read (damaged, or written by a later version) is set aside
    /// before anything is saved: starting empty and saving would erase every bookmark.
    @Test func unreadableBookStateIsSetAsideNotOverwritten() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Books.json")
        let original = Data(#"{"book": {"bookmarks": "#.utf8)
        try original.write(to: file)

        let store = BookStateStore(fileURL: file)
        store.update(forBook: "other") { $0.sidebarPane = .search }
        try store.save()

        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("Books.json.unreadable") }
        let name = try #require(kept.count == 1 ? kept.first : nil)
        #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == original)
    }

    @Test func unreadablePositionsAreSetAsideNotOverwritten() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("Positions.json")
        let original = Data("not json".utf8)
        try original.write(to: file)

        let store = ReadingPositionStore(fileURL: file)
        store.setPosition(ReadingPosition(spinePath: "a.xhtml", spineIndex: 0, fraction: 0.5), forBook: "book")
        try store.save()

        let kept = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("Positions.json.unreadable") }
        let name = try #require(kept.count == 1 ? kept.first : nil)
        #expect(try Data(contentsOf: folder.appendingPathComponent(name)) == original)
    }

    /// A missing file is a fresh start, with nothing set aside.
    @Test func missingFileStartsEmpty() throws {
        let folder = try Self.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BookStateStore(fileURL: folder.appendingPathComponent("Books.json"))
        #expect(store.state(forBook: "x") == BookState())
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}
