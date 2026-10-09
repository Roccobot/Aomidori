import Foundation

/// Toward the end of the book (`forward`: Space, `↓`, Page Down, scrolling down) or its start.
public enum EdgeDirection: Equatable, Sendable {
    case forward
    case backward

    public var opposite: EdgeDirection { self == .forward ? .backward : .forward }
}

/// Whether the page can scroll further up or down. A page that cannot scroll is at both edges.
public struct ScrollEdges: Equatable, Sendable {
    public var atTop: Bool
    public var atBottom: Bool

    public init(atTop: Bool, atBottom: Bool) {
        self.atTop = atTop
        self.atBottom = atBottom
    }

    /// Until the page reports, no edge is assumed.
    public static let unknown = ScrollEdges(atTop: false, atBottom: false)

    public func isAtEdge(_ direction: EdgeDirection) -> Bool {
        direction == .forward ? atBottom : atTop
    }
}

/// A scroll event as far as edge detection cares.
public struct EdgeScroll: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// A mouse wheel, or a device that reports no gesture phases.
        case none
        case began
        case changed
        case ended
    }

    /// Positive scrolls toward the top of the page (AppKit's `scrollingDeltaY`).
    public var deltaY: Double
    /// Trackpads and Magic Mice report precise deltas, in points; wheels report lines.
    public var isPrecise: Bool
    public var phase: Phase
    /// Inertia after the fingers have left the trackpad: never a deliberate push.
    public var isMomentum: Bool

    public init(deltaY: Double, isPrecise: Bool, phase: Phase = .none, isMomentum: Bool = false) {
        self.deltaY = deltaY
        self.isPrecise = isPrecise
        self.phase = phase
        self.isMomentum = isMomentum
    }

    public var direction: EdgeDirection? {
        deltaY < 0 ? .forward : deltaY > 0 ? .backward : nil
    }
}

/// What the reader should do with the chapter-edge toast.
public enum EdgeAction: Equatable, Sendable {
    case none
    /// Show (or keep showing, restarting its timer) the toast for a direction.
    case show(EdgeDirection)
    /// Go where the visible toast leads.
    case activate(EdgeDirection)
    case hide
}

/// Decides when pushing past the top or bottom of a chapter offers the previous or next one,
/// as a toast, and when a second push takes the reader there.
///
/// - A key (Space, arrows, Page Up/Down) pressed while the page is already at that edge shows
///   the toast. With the pointer over the toast, the same key again activates it.
/// - A wheel notch toward an edge the page is already at shows it.
/// - On a trackpad the push must be deliberate: scrolling toward the edge accumulates only once
///   the page is there, momentum never counts, and `preciseThreshold` points are needed. With
///   the pointer over the toast, a new gesture past the threshold activates it.
/// - Scrolling or pressing the other way, or the page leaving the edge, hides it.
public struct ChapterEdgeDetector: Sendable {
    /// Points of deliberate trackpad overscroll needed at an edge.
    public static let preciseThreshold: Double = 120

    public var edges: ScrollEdges = .unknown
    /// Whether there is a previous chapter. At the very start of the book nothing is offered
    /// backward; forward always is (next chapter, or the end of the book).
    public var hasPrevious = false
    public var isPointerOverToast = false
    /// The toast on screen, if any.
    public private(set) var toast: EdgeDirection?

    private var accumulated: Double = 0
    private var accumulatedDirection: EdgeDirection?
    /// A trackpad gesture has already shown or activated the toast: the rest of it is ignored.
    private var gestureSpent = false

    public init() {}

    public mutating func key(_ direction: EdgeDirection) -> EdgeAction {
        guard edges.isAtEdge(direction) else {
            return toast == direction.opposite ? hideToast() : .none
        }
        return push(direction)
    }

    public mutating func scroll(_ event: EdgeScroll) -> EdgeAction {
        if event.phase == .began {
            accumulated = 0
            gestureSpent = false
        }
        guard !event.isMomentum, let direction = event.direction else { return .none }
        if toast == direction.opposite { resetAccumulation(); return hideToast() }
        guard edges.isAtEdge(direction) else { resetAccumulation(); return .none }
        guard event.isPrecise else { return push(direction) }

        if gestureSpent { return .none }
        if accumulatedDirection != direction {
            accumulatedDirection = direction
            accumulated = 0
        }
        accumulated += abs(event.deltaY)
        guard accumulated >= Self.preciseThreshold else { return .none }
        resetAccumulation()
        gestureSpent = event.phase != .none
        return push(direction)
    }

    /// The page reported new edges; a toast whose edge was left goes away.
    public mutating func update(_ edges: ScrollEdges) -> EdgeAction {
        self.edges = edges
        if let toast, !edges.isAtEdge(toast) { return hideToast() }
        return .none
    }

    /// The toast was hidden (timer, click, new chapter).
    public mutating func toastDidHide() {
        toast = nil
        isPointerOverToast = false
    }

    /// A new document: nothing is known about its edges yet.
    public mutating func reset(hasPrevious: Bool) {
        self = ChapterEdgeDetector()
        self.hasPrevious = hasPrevious
    }

    private mutating func push(_ direction: EdgeDirection) -> EdgeAction {
        if toast == direction {
            if isPointerOverToast {
                toast = nil
                isPointerOverToast = false
                return .activate(direction)
            }
            return .show(direction)
        }
        guard direction == .forward || hasPrevious else { return .none }
        toast = direction
        return .show(direction)
    }

    private mutating func hideToast() -> EdgeAction {
        toast = nil
        isPointerOverToast = false
        return .hide
    }

    private mutating func resetAccumulation() {
        accumulated = 0
        accumulatedDirection = nil
    }
}
