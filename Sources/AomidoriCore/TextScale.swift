import Foundation

/// The reader's text size multiplier. 1 means "100% of the style": the style decides the size.
public enum TextScale {
    /// Discrete steps, denser around 100% where small changes matter most.
    public static let steps: [Double] = [0.5, 0.6, 0.7, 0.8, 0.85, 0.9, 0.95, 1, 1.05, 1.1, 1.15, 1.2, 1.3, 1.4, 1.5, 1.7, 2, 2.5, 3]
    public static let normal: Double = 1

    public static func larger(than scale: Double) -> Double {
        steps.first { $0 > scale + 0.0001 } ?? steps[steps.count - 1]
    }

    public static func smaller(than scale: Double) -> Double {
        steps.last { $0 < scale - 0.0001 } ?? steps[0]
    }

    /// Clamps a stored value into the supported range (and replaces non-finite values).
    public static func sanitized(_ scale: Double) -> Double {
        guard scale.isFinite else { return normal }
        return min(max(scale, steps[0]), steps[steps.count - 1])
    }
}
