import Testing
@testable import AomidoriCore

@Suite("Position history")
struct PositionHistoryTests {
    private func place(_ path: String, _ fraction: Double) -> ReadingPlace {
        ReadingPlace(path: path, position: ChapterPosition(fraction: fraction))
    }

    @Test func backReturnsWhereTheLinkWasFollowedAndForwardUndoesIt() {
        var history = PositionHistory<ReadingPlace>()
        #expect(!history.canGoBack && !history.canGoForward)
        history.departed(from: place("ch1.xhtml", 0.4))     // a note link in chapter 1
        let note = place("notes.xhtml", 0.7)
        #expect(history.back(from: note) == place("ch1.xhtml", 0.4))
        #expect(history.canGoForward && !history.canGoBack)
        #expect(history.forward(from: place("ch1.xhtml", 0.41)) == note)
        #expect(history.back(from: note) == place("ch1.xhtml", 0.41), "back returns to where forward left")
    }

    @Test func aNewLinkClearsForward() {
        var history = PositionHistory<ReadingPlace>()
        history.departed(from: place("a", 0.1))
        _ = history.back(from: place("b", 0))
        history.departed(from: place("a", 0.2))
        #expect(!history.canGoForward)
        #expect(history.backList == [place("a", 0.2)])
    }

    @Test func emptyDirectionsGiveNothingAndChangeNothing() {
        var history = PositionHistory<ReadingPlace>()
        #expect(history.back(from: place("a", 0)) == nil)
        #expect(history.forward(from: place("a", 0)) == nil)
        #expect(history.backList.isEmpty && history.forwardList.isEmpty)
    }

    @Test func theSamePlaceTwiceIsKeptOnceAndTheListIsCapped() {
        var history = PositionHistory<ReadingPlace>(limit: 3)
        history.departed(from: place("a", 0.5))
        history.departed(from: place("a", 0.5))
        #expect(history.backList.count == 1)
        for i in 0..<5 { history.departed(from: place("c\(i)", 0)) }
        #expect(history.backList.map(\.path) == ["c2", "c3", "c4"])
    }
}

@Suite("Result stepping")
struct ResultSteppingTests {
    @Test func stepsAndWrapsRound() {
        #expect(ResultStepping.index(from: nil, count: 5, step: 1) == 0)
        #expect(ResultStepping.index(from: nil, count: 5, step: -1) == 4)
        #expect(ResultStepping.index(from: 1, count: 5, step: 1) == 2)
        #expect(ResultStepping.index(from: 4, count: 5, step: 1) == 0)
        #expect(ResultStepping.index(from: 0, count: 5, step: -1) == 4)
        #expect(ResultStepping.index(from: 9, count: 5, step: 1) == 0, "a stale selection starts over")
        #expect(ResultStepping.index(from: nil, count: 0, step: 1) == nil)
    }
}
