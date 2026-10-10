import Testing
@testable import AomidoriCore

@Suite("Link opening")
struct LinkOpeningTests {
    @Test func settingOffFollowsInPlaceUnlessShiftOrOption() {
        #expect(LinkOpening.decide(newTabsSetting: false, modifiers: []) == .here)
        #expect(LinkOpening.decide(newTabsSetting: false, modifiers: [.shift]) == .newTab(inBackground: false))
        #expect(LinkOpening.decide(newTabsSetting: false, modifiers: [.option]) == .newTab(inBackground: true))
        #expect(LinkOpening.decide(newTabsSetting: false, modifiers: [.command]) == .here)
    }

    @Test func settingOnOpensEveryLinkInANewTab() {
        #expect(LinkOpening.decide(newTabsSetting: true, modifiers: []) == .newTab(inBackground: false))
        #expect(LinkOpening.decide(newTabsSetting: true, modifiers: [.shift]) == .newTab(inBackground: false))
        #expect(LinkOpening.decide(newTabsSetting: true, modifiers: [.option]) == .newTab(inBackground: true))
        #expect(LinkOpening.decide(newTabsSetting: true, modifiers: [.shift, .option]) == .newTab(inBackground: true))
    }

    @Test func nextToSourceDependsOnNewTabs() {
        #expect(LinkOpening.placement(newTabsSetting: true, nextToSourceSetting: true) == .nextToSource)
        #expect(LinkOpening.placement(newTabsSetting: true, nextToSourceSetting: false) == .end)
        #expect(LinkOpening.placement(newTabsSetting: false, nextToSourceSetting: false) == .nextToSource)
    }
}
