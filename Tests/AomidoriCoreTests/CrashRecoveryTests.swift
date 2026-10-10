import Foundation
import Testing
@testable import AomidoriCore

@Suite("Crash recovery")
struct CrashRecoveryTests {
    /// A page that makes WebKit's process fail every time is reloaded twice, then left alone:
    /// reloading it forever would keep the processor busy for nothing.
    @Test func samePageIsReloadedAtMostTwiceAMinute() {
        var recovery = CrashRecovery()
        let start = Date(timeIntervalSince1970: 1000)
        let answers = [
            recovery.shouldReload("a.xhtml", at: start),
            recovery.shouldReload("a.xhtml", at: start.addingTimeInterval(1)),
            recovery.shouldReload("a.xhtml", at: start.addingTimeInterval(2)),
            // Another page has its own attempts; the first one gets new ones after a minute.
            recovery.shouldReload("b.xhtml", at: start.addingTimeInterval(3)),
            recovery.shouldReload("a.xhtml", at: start.addingTimeInterval(62)),
        ]
        #expect(answers == [true, true, false, true, true])
    }
}
