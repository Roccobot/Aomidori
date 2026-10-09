import Foundation
import Testing
@testable import AomidoriCore

@Suite("Chapter positions") struct ChapterPositionTests {
    private func makeStore() -> (ReadingPositionStore, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-chapters-\(UUID().uuidString).json")
        return (ReadingPositionStore(fileURL: url), url)
    }

    @Test func everyChapterKeepsItsOwnPosition() {
        let (store, _) = makeStore()
        store.setPosition(ReadingPosition(spinePath: "c1.xhtml", spineIndex: 1, fraction: 0.4, anchor: "2.1@0.5"), forBook: "b")
        store.setPosition(ReadingPosition(spinePath: "c2.xhtml", spineIndex: 2, fraction: 0.9), forBook: "b")
        store.setPosition(ReadingPosition(spinePath: "c3.xhtml", spineIndex: 3, fraction: 0), forBook: "b")

        #expect(store.chapterPosition(forBook: "b", spinePath: "c1.xhtml") == ChapterPosition(fraction: 0.4, anchor: "2.1@0.5"))
        #expect(store.chapterPosition(forBook: "b", spinePath: "c2.xhtml") == ChapterPosition(fraction: 0.9))
        #expect(store.chapterPosition(forBook: "b", spinePath: "c3.xhtml") == .top)
        #expect(store.chapterPosition(forBook: "b", spinePath: "c4.xhtml") == nil)
        #expect(store.position(forBook: "b")?.spinePath == "c3.xhtml")

        // Back in chapter 1: the map entry follows, the others stay.
        store.setPosition(ReadingPosition(spinePath: "c1.xhtml", spineIndex: 1, fraction: 0.6), forBook: "b")
        #expect(store.chapterPosition(forBook: "b", spinePath: "c1.xhtml") == ChapterPosition(fraction: 0.6))
        #expect(store.chapterPosition(forBook: "b", spinePath: "c2.xhtml") == ChapterPosition(fraction: 0.9))
        #expect(store.chapterPosition(forBook: "other", spinePath: "c1.xhtml") == nil)
    }

    @Test func leavingAChapterDoesNotMoveTheCurrentPosition() {
        let (store, _) = makeStore()
        store.setChapterPosition(ChapterPosition(fraction: 0.5), spinePath: "c1.xhtml", forBook: "b")
        #expect(store.position(forBook: "b") == nil, "nothing to attach to yet")

        store.setPosition(ReadingPosition(spinePath: "c2.xhtml", spineIndex: 2, fraction: 0.2), forBook: "b")
        // A late report from the chapter just left.
        store.setChapterPosition(ChapterPosition(fraction: 0.7, anchor: "5@0"), spinePath: "c1.xhtml", forBook: "b")
        #expect(store.position(forBook: "b")?.spinePath == "c2.xhtml")
        #expect(store.position(forBook: "b")?.fraction == 0.2)
        #expect(store.chapterPosition(forBook: "b", spinePath: "c1.xhtml") == ChapterPosition(fraction: 0.7, anchor: "5@0"))

        // A report for the current chapter updates the current position too.
        store.setChapterPosition(ChapterPosition(fraction: 0.3, anchor: "1@0.1"), spinePath: "c2.xhtml", forBook: "b")
        #expect(store.position(forBook: "b")?.chapterPosition == ChapterPosition(fraction: 0.3, anchor: "1@0.1"))
    }

    @Test func mapSurvivesSaveAndReload() throws {
        let (store, url) = makeStore()
        defer { try? FileManager.default.removeItem(at: url) }
        store.setPosition(ReadingPosition(spinePath: "c1.xhtml", spineIndex: 1, fraction: 0.4, anchor: "3.0.2@0.25"), forBook: "b")
        store.setPosition(ReadingPosition(spinePath: "c2.xhtml", spineIndex: 2, fraction: 0.8), forBook: "b")
        try store.save()

        let reloaded = ReadingPositionStore(fileURL: url)
        #expect(reloaded.chapterPosition(forBook: "b", spinePath: "c1.xhtml") == ChapterPosition(fraction: 0.4, anchor: "3.0.2@0.25"))
        #expect(reloaded.position(forBook: "b")?.chapterPosition == ChapterPosition(fraction: 0.8))
    }

    @Test func readsFilesFromEarlierVersions() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aomidori-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let old = #"{"b":{"fraction":0.5,"spineIndex":3,"spinePath":"c3.xhtml","updated":"2026-10-01T10:00:00Z"}}"#
        try Data(old.utf8).write(to: url)
        let store = ReadingPositionStore(fileURL: url)
        #expect(store.position(forBook: "b")?.fraction == 0.5)
        #expect(store.position(forBook: "b")?.chapters.isEmpty == true)
        #expect(store.chapterPosition(forBook: "b", spinePath: "c3.xhtml") == nil)
    }

    @Test func positionsAreSanitized() {
        #expect(ChapterPosition(fraction: .nan) == .top)
        #expect(ChapterPosition(fraction: 2).fraction == 1)
        #expect(ChapterPosition(fraction: 0.5, anchor: "").anchor == nil)
    }
}
