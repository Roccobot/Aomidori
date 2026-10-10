import Testing
@testable import AomidoriCore

@Suite("Split chooser")
struct SplitChooserTests {
    private func tabs(_ titles: String...) -> [SplitChooser.Tab] { titles.map { SplitChooser.Tab(title: $0) } }

    @Test func noOtherTabMeansASecondViewOfTheBook() {
        let chooser = SplitChooser(tabs: tabs("A"), current: 0)
        #expect(chooser.outcome == .newViewOfCurrentBook)
        #expect(chooser.preselected == nil)
    }

    @Test func oneOtherTabGoesStraightIn() {
        #expect(SplitChooser(tabs: tabs("A", "B"), current: 1).outcome == .tab(0))
        var withEmpty = tabs("A", "B")
        withEmpty.append(SplitChooser.Tab(title: "Empty", isReader: false))
        #expect(SplitChooser(tabs: withEmpty, current: 0).outcome == .tab(1), "empty tabs are not offered")
    }

    @Test func aSecondViewOfTheSameBookIsPreselected() {
        var list = tabs("A", "B", "C", "D")
        list[0].isSameBook = true
        let chooser = SplitChooser(tabs: list, current: 2)
        #expect(chooser.outcome == .chooser)
        #expect(chooser.candidates == [0, 1, 3])
        #expect(chooser.preselected == 0)
    }

    @Test func elseTheTabToTheRightOrTheFirst() {
        let middle = SplitChooser(tabs: tabs("A", "B", "C", "D"), current: 1)
        #expect(middle.candidates == [0, 2, 3])
        #expect(middle.preselected == 1, "C, right of B")
        let last = SplitChooser(tabs: tabs("A", "B", "C"), current: 2)
        #expect(last.preselected == 0, "the last tab wraps to the first")
    }

    @Test func rowsAreNumberedOneToNineThenZero() {
        #expect((0..<11).map(SplitChooser.label(forRow:)) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", nil])
        #expect(SplitChooser.row(forDigit: "1", rowCount: 3) == 0)
        #expect(SplitChooser.row(forDigit: "3", rowCount: 3) == 2)
        #expect(SplitChooser.row(forDigit: "4", rowCount: 3) == nil)
        #expect(SplitChooser.row(forDigit: "0", rowCount: 12) == 9)
        #expect(SplitChooser.row(forDigit: "0", rowCount: 9) == nil)
        #expect(SplitChooser.row(forDigit: "x", rowCount: 12) == nil)
    }
}
