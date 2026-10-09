import Testing
@testable import AomidoriCore

@Suite("Appearance")
struct AppearanceChoiceTests {
    @Test func followsTheSystemWithoutAnOverride() {
        #expect(AppearanceChoice.isDark(override: nil, systemIsDark: true))
        #expect(!AppearanceChoice.isDark(override: nil, systemIsDark: false))
        #expect(AppearanceChoice.isDark(override: true, systemIsDark: false))
    }

    @Test func swappingShowsTheOtherAppearanceAndClearsWhenItIsTheSystems() {
        // Dark Mac: swap to light (an override), swap again: dark again, which is the system's.
        let light = AppearanceChoice.override(afterSwapping: nil, systemIsDark: true)
        #expect(light == false)
        #expect(AppearanceChoice.override(afterSwapping: light, systemIsDark: true) == nil)
        #expect(AppearanceChoice.override(afterSwapping: nil, systemIsDark: false) == true)
        // A stale override equal to the system (from an older version) swaps to the other side.
        #expect(AppearanceChoice.override(afterSwapping: true, systemIsDark: true) == false)
    }

    @Test func macOSCatchingUpDropsTheOverride() {
        #expect(AppearanceChoice.reconciled(true, systemIsDark: true) == nil)
        #expect(AppearanceChoice.reconciled(false, systemIsDark: true) == false)
        #expect(AppearanceChoice.reconciled(nil, systemIsDark: false) == nil)
    }
}
