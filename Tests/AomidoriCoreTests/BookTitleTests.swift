import Foundation
import Testing
@testable import AomidoriCore

@Suite("Book title")
struct BookTitleTests {
    private let file = URL(fileURLWithPath: "/Books/Una-descrizione-di-Terramare.epub")

    @Test func theBookTitleComesFirst() {
        #expect(BookTitle.display(title: "Una descrizione di Terramare", fileURL: file) == "Una descrizione di Terramare")
        #expect(BookTitle.display(title: "  Terramare\n", fileURL: file) == "Terramare")
    }

    @Test func withoutATitleTheFileNameWithoutExtension() {
        #expect(BookTitle.display(title: nil, fileURL: file) == "Una-descrizione-di-Terramare")
        #expect(BookTitle.display(title: " ", fileURL: file) == "Una-descrizione-di-Terramare")
        #expect(BookTitle.display(title: nil, fileURL: URL(fileURLWithPath: "/Books/libro.v2.EPUB")) == "libro.v2")
    }

    @Test func nothingToGoBy() {
        #expect(BookTitle.display(title: nil, fileURL: nil) == nil)
        #expect(BookTitle.display(title: "", fileURL: nil) == nil)
    }
}
