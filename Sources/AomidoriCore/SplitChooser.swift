import Foundation

/// The split view's right half when the window has several other tabs: a list of them in tab
/// order, the first ten numbered 1…9, 0 (typing the number opens that tab), with one preselected:
/// another view of the same book if there is one, else the tab right of the current one (the
/// first tab when the current one is last). Rocco's requests; the model is Techne's.
/// Author: Rocco Casadei, a.k.a. Roccobot
public struct SplitChooser: Equatable, Sendable {
    public struct Tab: Equatable, Sendable {
        public var title: String
        /// A reader tab (empty tabs cannot go in a split).
        public var isReader: Bool
        /// Shows the same book as the current tab.
        public var isSameBook: Bool

        public init(title: String, isReader: Bool = true, isSameBook: Bool = false) {
            self.title = title
            self.isReader = isReader
            self.isSameBook = isSameBook
        }
    }

    /// Indexes into the window's tabs, in tab order, of the tabs offered (the current one and
    /// empty tabs excluded).
    public let candidates: [Int]
    /// Index into `candidates`.
    public let preselected: Int?

    /// `tabs` in tab-bar order; `current` is the index of the tab being split.
    public init(tabs: [Tab], current: Int) {
        let candidates = tabs.indices.filter { $0 != current && tabs[$0].isReader }
        self.candidates = candidates
        if let same = candidates.firstIndex(where: { tabs[$0].isSameBook }) {
            preselected = same
        } else if let right = candidates.firstIndex(where: { $0 > current }) {
            preselected = right
        } else {
            preselected = candidates.isEmpty ? nil : 0
        }
    }

    /// What the split shows on the right: nothing to choose from, one tab, or a list.
    public enum Outcome: Equatable, Sendable {
        /// No other reader tab: a second view of the current book.
        case newViewOfCurrentBook
        case tab(Int)
        case chooser
    }

    public var outcome: Outcome {
        switch candidates.count {
        case 0: .newViewOfCurrentBook
        case 1: .tab(candidates[0])
        default: .chooser
        }
    }

    /// "1"…"9", "0" for the first ten rows, nothing after.
    public static func label(forRow row: Int) -> String? {
        switch row {
        case 0..<9: String(row + 1)
        case 9: "0"
        default: nil
        }
    }

    /// The row a typed digit opens: "1" the first … "0" the tenth; nil if there is no such row.
    public static func row(forDigit digit: Character, rowCount: Int) -> Int? {
        guard let value = digit.wholeNumberValue, digit.isASCII else { return nil }
        let row = value == 0 ? 9 : value - 1
        return row < rowCount ? row : nil
    }
}
