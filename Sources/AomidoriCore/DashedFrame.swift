import Foundation

/// The dashed frame of the empty window's drop zone, drawn in code at any size (Graphe's rule,
/// October 2026): the dashes are spread evenly over the whole perimeter, so the pattern always
/// closes on itself, and one dash sits centred at the top middle, where the path starts.
///
/// The frame is a rounded rectangle with circular corners, stroked inside the view: the path
/// runs `lineWidth / 2` in from the edges. With round caps each dash grows by half the line
/// width at both ends, so the drawn dash is shortened (and the gap lengthened) by `lineWidth`.
public struct DashedFrame: Equatable, Sendable {
    /// The dash and gap the pattern is fitted around: 10 and 12 with a 2-point line.
    public static let baseDash = 10.0
    public static let baseGap = 12.0
    public static let minimumDashes = 4

    /// The stroked path's rectangle (already inset) and corner radius.
    public let width: Double
    public let height: Double
    public let radius: Double
    public let lineWidth: Double
    public let roundCaps: Bool

    public init(boundsWidth: Double, boundsHeight: Double, radius: Double, lineWidth: Double, roundCaps: Bool = true) {
        width = max(boundsWidth - lineWidth, 0)
        height = max(boundsHeight - lineWidth, 0)
        self.radius = min(max(radius, 0), min(width, height) / 2)
        self.lineWidth = lineWidth
        self.roundCaps = roundCaps
    }

    /// 2(w − 2r) + 2(h − 2r) + 2πr.
    public var perimeter: Double {
        2 * (width - 2 * radius) + 2 * (height - 2 * radius) + 2 * .pi * radius
    }

    /// How many dashes go round the frame.
    public var count: Int {
        max(Self.minimumDashes, Int((perimeter / (Self.baseDash + Self.baseGap)).rounded()))
    }

    /// One dash and one gap.
    public var period: Double { perimeter / Double(count) }

    /// The dash and gap to give the stroke (`setLineDash`), caps accounted for.
    public var dash: Double {
        let dash = period * Self.baseDash / (Self.baseDash + Self.baseGap)
        return roundCaps ? max(dash - lineWidth, 0.01) : dash
    }

    public var gap: Double { period - dash }

    /// The pattern's phase: the path starts halfway through a dash, so that dash is centred
    /// on the starting point (the top middle).
    public var phase: Double { dash / 2 }
}
