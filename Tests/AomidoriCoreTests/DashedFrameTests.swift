import Foundation
import Testing
@testable import AomidoriCore

@Suite("Drop zone frame")
struct DashedFrameTests {
    /// The stretches a stroke with `setLineDash([dash, gap], phase:)` paints along a closed path
    /// of the frame's perimeter, caps included, sampled finely. The path starts at the top
    /// middle; a stretch that runs over the end and on from the start is one dash.
    private func paintedDashes(_ frame: DashedFrame) -> [Double] {
        let samples = 40_000
        let step = frame.perimeter / Double(samples)
        let cap = frame.roundCaps ? frame.lineWidth / 2 : 0
        func isPainted(_ s: Double) -> Bool {
            // Under the dash itself, or within a cap's reach of one of its ends.
            let t = ((s + frame.phase).truncatingRemainder(dividingBy: frame.period) + frame.period)
                .truncatingRemainder(dividingBy: frame.period)
            return t <= frame.dash + cap || t >= frame.period - cap
        }
        var runs: [Double] = []
        var current = 0.0
        for i in 0..<samples {
            if isPainted(Double(i) * step) { current += step } else if current > 0 { runs.append(current); current = 0 }
        }
        if current > 0 {
            // The run open at the end of the path continues the one the path starts with.
            if isPainted(0), !runs.isEmpty { runs[0] += current } else { runs.append(current) }
        }
        return runs
    }

    private static let sizes: [(Double, Double)] = [
        (184, 128), (220, 153), (240, 160), (300, 209), (435, 300), (512, 356), (600, 417),
        (777, 541), (1000, 696), (123.4, 85.9), (90, 60), (40, 30),
    ]

    @Test(arguments: sizes)
    func dashesCloseEvenlyRoundTheFrame(width: Double, height: Double) {
        let frame = DashedFrame(boundsWidth: width, boundsHeight: height, radius: 20 * width / 184, lineWidth: 2)
        let runs = paintedDashes(frame)
        let tolerance = frame.perimeter / 40_000 * 2.5
        #expect(runs.count == frame.count, "every dash whole, none doubled at the seam")
        let drawn = frame.dash + frame.lineWidth
        for run in runs { #expect(abs(run - drawn) <= tolerance, "\(width)x\(height): \(run) vs \(drawn)") }
        #expect(abs(Double(frame.count) * frame.period - frame.perimeter) < 1e-9)
        #expect(frame.count >= DashedFrame.minimumDashes && frame.dash > 0 && frame.gap > frame.lineWidth)
    }

    @Test func oneDashIsCentredOnTheTopMiddle() {
        let frame = DashedFrame(boundsWidth: 435, boundsHeight: 300, radius: 47, lineWidth: 2)
        #expect(frame.phase == frame.dash / 2)
    }

    @Test func thePerimeterIsTheInsetRoundedRectangles() {
        let frame = DashedFrame(boundsWidth: 186, boundsHeight: 130, radius: 20, lineWidth: 2)
        #expect(frame.width == 184 && frame.height == 128)
        #expect(abs(frame.perimeter - (2 * 144 + 2 * 88 + 2 * .pi * 20)) < 1e-9)
        // About the base pattern: 10 + 12 per dash.
        #expect(abs(frame.period - 22) < 22 * 0.1)
        #expect(abs(frame.dash + frame.lineWidth - frame.period * 10 / 22) < 1e-9)
    }

    @Test func squareCapsKeepTheWholeDash() {
        let frame = DashedFrame(boundsWidth: 300, boundsHeight: 200, radius: 30, lineWidth: 2, roundCaps: false)
        #expect(abs(frame.dash - frame.period * 10 / 22) < 1e-9)
        #expect(paintedDashes(frame).count == frame.count)
    }

    @Test func aTooLargeRadiusIsClamped() {
        let frame = DashedFrame(boundsWidth: 102, boundsHeight: 52, radius: 80, lineWidth: 2)
        #expect(frame.radius == 25)
        #expect(frame.perimeter > 0)
    }
}
