import Foundation

/// A place in a book: a spine item and an exact position in it.
public struct ReadingPlace: Equatable, Sendable {
    public var path: String
    public var position: ChapterPosition

    public init(path: String, position: ChapterPosition) {
        self.path = path
        self.position = position
    }
}

/// The reader's own back and forward history, as in a browser: following a link (to a note,
/// a chapter, an anchor) leaves the place it started from behind; Back returns there exactly,
/// and Forward goes where Back came from. Following a new link clears Forward.
public struct PositionHistory<Place: Equatable & Sendable>: Sendable {
    public private(set) var backList: [Place] = []
    public private(set) var forwardList: [Place] = []
    /// The places kept in each direction; the oldest go first.
    public let limit: Int

    public init(limit: Int = 100) {
        self.limit = max(limit, 1)
    }

    public var canGoBack: Bool { !backList.isEmpty }
    public var canGoForward: Bool { !forwardList.isEmpty }

    /// A link was followed from `place`.
    public mutating func departed(from place: Place) {
        if backList.last != place { backList.append(place) }
        if backList.count > limit { backList.removeFirst(backList.count - limit) }
        forwardList.removeAll()
    }

    /// Where Back goes from `current`, which becomes the first place forward.
    public mutating func back(from current: Place) -> Place? {
        guard let target = backList.popLast() else { return nil }
        forwardList.append(current)
        if forwardList.count > limit { forwardList.removeFirst(forwardList.count - limit) }
        return target
    }

    /// Where Forward goes from `current`, which becomes the first place back.
    public mutating func forward(from current: Place) -> Place? {
        guard let target = forwardList.popLast() else { return nil }
        backList.append(current)
        if backList.count > limit { backList.removeFirst(backList.count - limit) }
        return target
    }
}

/// `⌘G` / `⇧⌘G` through a list of results: the next or previous one after the selected one,
/// wrapping round at either end; with nothing selected, the first (or the last, going back).
public enum ResultStepping {
    public static func index(from selected: Int?, count: Int, step: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let selected, (0..<count).contains(selected) else { return step < 0 ? count - 1 : 0 }
        return ((selected + step) % count + count) % count
    }
}
