import Testing
@testable import AomidoriCore

@Suite("Chapter edges") struct ChapterEdgeTests {
    private func detector(top: Bool = false, bottom: Bool = false, hasPrevious: Bool = true) -> ChapterEdgeDetector {
        var detector = ChapterEdgeDetector()
        detector.hasPrevious = hasPrevious
        _ = detector.update(ScrollEdges(atTop: top, atBottom: bottom))
        return detector
    }

    private func trackpad(_ deltaY: Double, _ phase: EdgeScroll.Phase = .changed, momentum: Bool = false) -> EdgeScroll {
        EdgeScroll(deltaY: deltaY, isPrecise: true, phase: phase, isMomentum: momentum)
    }

    @Test func keysAwayFromTheEdgeScrollNormally() {
        var edge = detector()
        #expect(edge.key(.forward) == .none)
        #expect(edge.key(.backward) == .none)
        #expect(edge.toast == nil)
    }

    @Test func keyAtTheBottomShowsThenActivatesOnlyUnderThePointer() {
        var edge = detector(bottom: true)
        #expect(edge.key(.forward) == .show(.forward))
        #expect(edge.key(.forward) == .show(.forward), "pointer elsewhere: the toast just stays")
        edge.isPointerOverToast = true
        #expect(edge.key(.forward) == .activate(.forward))
        #expect(edge.toast == nil)
    }

    @Test func atTheStartOfTheBookNothingIsOfferedBackward() {
        var edge = detector(top: true, hasPrevious: false)
        #expect(edge.key(.backward) == .none)
        #expect(edge.scroll(EdgeScroll(deltaY: 3, isPrecise: false)) == .none)
        var middle = detector(top: true)
        #expect(middle.key(.backward) == .show(.backward))
    }

    @Test func aPageThatCannotScrollIsAtBothEdges() {
        var edge = detector(top: true, bottom: true)
        #expect(edge.key(.forward) == .show(.forward))
        #expect(edge.key(.backward) == .show(.backward), "the other way replaces the toast")
    }

    @Test func wheelNotchAtTheEdgeShowsAndASecondUnderThePointerActivates() {
        var edge = detector(bottom: true)
        let notch = EdgeScroll(deltaY: -1, isPrecise: false)
        #expect(edge.scroll(notch) == .show(.forward))
        edge.isPointerOverToast = true
        #expect(edge.scroll(notch) == .activate(.forward))
    }

    @Test func wheelNotchBeforeTheEdgeDoesNothing() {
        var edge = detector()
        #expect(edge.scroll(EdgeScroll(deltaY: -1, isPrecise: false)) == .none)
    }

    @Test func trackpadNeedsADeliberatePushAtTheEdge() {
        var edge = detector()
        #expect(edge.scroll(trackpad(-10, .began)) == .none)
        // Scrolling toward the edge before reaching it does not count.
        for _ in 0..<30 { #expect(edge.scroll(trackpad(-40)) == .none) }
        _ = edge.update(ScrollEdges(atTop: false, atBottom: true))
        #expect(edge.scroll(trackpad(-50)) == .none)
        #expect(edge.scroll(trackpad(-50)) == .none)
        #expect(edge.scroll(trackpad(-30)) == .show(.forward), "120 points past the edge")
        // The rest of the same gesture and its momentum never activate, even under the pointer.
        edge.isPointerOverToast = true
        for _ in 0..<10 { #expect(edge.scroll(trackpad(-60)) == .none) }
        #expect(edge.scroll(trackpad(0, .ended)) == .none)
        for _ in 0..<10 { #expect(edge.scroll(trackpad(-80, .none, momentum: true)) == .none) }
        // A new deliberate gesture does.
        #expect(edge.scroll(trackpad(-60, .began)) == .none)
        #expect(edge.scroll(trackpad(-70)) == .activate(.forward))
    }

    @Test func momentumThatReachesTheEdgeNeverShowsTheToast() {
        var edge = detector(bottom: true)
        for _ in 0..<50 { #expect(edge.scroll(trackpad(-90, .none, momentum: true)) == .none) }
        #expect(edge.toast == nil)
    }

    @Test func smallBackAndForthNeverAddsUp() {
        var edge = detector(bottom: true)
        #expect(edge.scroll(trackpad(-5, .began)) == .none)
        for _ in 0..<20 {
            #expect(edge.scroll(trackpad(-100)) == .none)
            _ = edge.update(ScrollEdges(atTop: false, atBottom: false))
            #expect(edge.scroll(trackpad(30)) == .none)
            _ = edge.update(ScrollEdges(atTop: false, atBottom: true))
        }
        #expect(edge.toast == nil)
    }

    @Test func scrollingBackOrLeavingTheEdgeHides() {
        var edge = detector(bottom: true)
        #expect(edge.key(.forward) == .show(.forward))
        #expect(edge.scroll(trackpad(4)) == .hide)
        #expect(edge.toast == nil)

        #expect(edge.key(.forward) == .show(.forward))
        #expect(edge.key(.backward) == .hide, "up arrow away from the top")

        #expect(edge.key(.forward) == .show(.forward))
        #expect(edge.update(ScrollEdges(atTop: false, atBottom: false)) == .hide)
    }

    @Test func aNewDocumentStartsClean() {
        var edge = detector(bottom: true)
        _ = edge.key(.forward)
        edge.reset(hasPrevious: false)
        #expect(edge.toast == nil)
        #expect(edge.edges == .unknown)
        #expect(edge.key(.forward) == .none)
    }

    @Test func precisePhaselessScrollingCanStillActivate() {
        var edge = detector(bottom: true)
        #expect(edge.scroll(trackpad(-130, .none)) == .show(.forward))
        edge.isPointerOverToast = true
        #expect(edge.scroll(trackpad(-130, .none)) == .activate(.forward))
    }
}
