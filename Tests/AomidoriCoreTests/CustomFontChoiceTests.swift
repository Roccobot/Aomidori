import Foundation
import Testing
@testable import AomidoriCore

@Suite("Custom font choice")
struct CustomFontChoiceTests {
    @Test func boldIsThreeHundredHeavierUpToNineHundred() {
        #expect(CustomFontChoice(family: "A", weight: 300).boldWeight == 600)
        #expect(CustomFontChoice(family: "A", weight: 400).boldWeight == 700)
        #expect(CustomFontChoice(family: "A", weight: 500).boldWeight == 800)
        #expect(CustomFontChoice(family: "A", weight: 650).boldWeight == 900)
        #expect(CustomFontChoice(family: "A", weight: 950).boldWeight == 950, "never lighter than the text")
        #expect(CustomFontChoice(family: "A").boldWeight == nil, "the style's own weights")
    }

    @Test func featuresAndVariationsBecomeCSS() {
        let choice = CustomFontChoice(family: "A", variations: ["opsz": 18, "GRAD": -12.5, "wght": 700, "wdth": 80, "bad": 1],
                                      features: ["smcp": 1, "liga": 0, "ss03": 1, "toolong": 1])
        #expect(choice.featureSettingsCSS == #""liga" 0, "smcp" 1, "ss03" 1"#)
        #expect(choice.variationSettingsCSS == #""GRAD" -12.5, "opsz" 18"#, "weight and width go through font-weight and font-stretch")
        #expect(CustomFontChoice(family: "A").featureSettingsCSS.isEmpty)
    }

    @Test func valuesAreSanitized() {
        let choice = CustomFontChoice(family: "A", faceName: "", weight: 5000, stretch: .nan)
        #expect(choice.faceName == nil)
        #expect(choice.weight == 1000)
        #expect(choice.stretch == nil)
        #expect(CustomFontChoice.isTag("ss01") && !CustomFontChoice.isTag("ss1") && !CustomFontChoice.isTag("a\"bc"))
    }

    @Test func storedRecordWinsAndOldFamilyMigrates() {
        let choice = CustomFontChoice(family: "Avenir Next", faceName: "AvenirNextCondensed-Medium", weight: 500, stretch: 75,
                                      features: ["onum": 1])
        #expect(CustomFontChoice.stored(record: choice.record(), legacyFamily: "Georgia") == choice)
        // Before 0.4.0 only the family was stored: it changes the family and nothing else.
        let migrated = CustomFontChoice.stored(record: nil, legacyFamily: "Georgia")
        #expect(migrated == CustomFontChoice(family: "Georgia"))
        #expect(migrated?.weight == nil && migrated?.stretch == nil && migrated?.italic == false)
        #expect(CustomFontChoice.stored(record: Data("garbage".utf8), legacyFamily: "Georgia")?.family == "Georgia")
        #expect(CustomFontChoice.stored(record: nil, legacyFamily: nil) == nil)
        // A record from a newer version with unknown keys still loads.
        let future = Data(#"{"family":"X","weight":300,"letterSpacing":0.1}"#.utf8)
        #expect(CustomFontChoice.stored(record: future, legacyFamily: nil) == CustomFontChoice(family: "X", weight: 300))
    }

    @Test func facesDeclareExactWeightsWidthsAndRanges() {
        let css = CustomFontCSS.fontFaceCSS([
            FontFaceSource(postScriptName: "AvenirNextCondensed-DemiBold", weight: 590, stretch: 75),
            FontFaceSource(url: "/.aomidori/Fonts/Var.ttf", italic: true, weightRange: 100...900, stretchRange: 62.5...100),
        ])
        let lines = css.split(separator: "\n")
        #expect(lines[0].contains("font-weight: 590; font-style: normal; font-stretch: 75%;"))
        #expect(lines[1].contains("font-weight: 100 900; font-style: italic; font-stretch: 62.5% 100%;"))
    }

    @Test func weightAndWidthTraitsMapToCSS() {
        #expect(CustomFontCSS.exactWeight(fromTrait: 0) == 400)
        #expect(CustomFontCSS.exactWeight(fromTrait: 0.4) == 700)
        #expect(CustomFontCSS.exactWeight(fromTrait: 0.265) == 550)
        #expect(CustomFontCSS.exactWeight(fromTrait: -1) == 100)
        #expect(CustomFontCSS.exactWeight(fromTrait: 1) == 900)
        #expect(CustomFontCSS.stretch(fromWidthTrait: 0) == 100)
        #expect(CustomFontCSS.stretch(fromWidthTrait: -0.2) == 75)
        #expect(CustomFontCSS.stretch(fromWidthTrait: -0.15) == 81.3)
        #expect(CustomFontCSS.stretch(fromWidthTrait: 0.2) == 125)
        #expect(CustomFontCSS.stretch(fromWidthTrait: -1) == 50)
    }

    @Test func widthAxesOffTheCSSScaleAreReadAsRatios() {
        // Skia: wdth 0.62–1.3, 1 = normal.
        #expect(CustomFontCSS.stretch(fromWidthAxisValue: 1.3, range: 0.62...1.3) == 130)
        #expect(CustomFontCSS.stretch(fromWidthAxisValue: 0.62, range: 0.62...1.3) == 62)
        #expect(CustomFontCSS.stretch(fromWidthAxisValue: 1, range: 0.62...1.3) == 100)
        #expect(CustomFontCSS.stretch(fromWidthAxisValue: 0.3, range: 0.25...4) == 50, "clamped to 50%")
        #expect(CustomFontCSS.stretch(fromWidthAxisValue: .nan, range: 0.62...1.3) == 100)
        #expect(CustomFontCSS.stretch(fromWidthAxisValue: 5, range: 0...10) == 100, "unknown scale: normal width")
        #expect(CustomFontCSS.isCSSWidthAxis(62.5...100))
        #expect(CustomFontCSS.isCSSWidthAxis(30...150), "the system font's width axis")
        #expect(!CustomFontCSS.isCSSWidthAxis(0.62...1.3))
    }

    @Test func opticalSizeFromAnAppKitFontIsDropped() {
        let values = CustomFontChoice.panelVariations(["opsz": 17, "GRAD": 500, "wght": 550])
        #expect(values == ["GRAD": 500, "wght": 550])
        let choice = CustomFontChoice(family: "SF", variations: CustomFontChoice.panelVariations(["opsz": 17, "GRAD": 500]))
        #expect(choice.variationSettingsCSS == #""GRAD" 500"#)
    }

    @Test func typographySelectorsMapToOpenTypeTags() {
        #expect(OpenTypeFeatures.tag(type: 37, selector: 1)! == ("smcp", 1))
        #expect(OpenTypeFeatures.tag(type: 1, selector: 3)! == ("liga", 0))
        #expect(OpenTypeFeatures.tag(type: 21, selector: 0)! == ("onum", 1))
        #expect(OpenTypeFeatures.tag(type: 6, selector: 0)! == ("tnum", 1))
        #expect(OpenTypeFeatures.tag(type: 35, selector: 2)! == ("ss01", 1))
        #expect(OpenTypeFeatures.tag(type: 35, selector: 7)! == ("ss03", 0))
        #expect(OpenTypeFeatures.tag(type: 35, selector: 40)! == ("ss20", 1))
        #expect(OpenTypeFeatures.tag(type: 17, selector: 2)! == ("salt", 2))
        #expect(OpenTypeFeatures.tag(type: 999, selector: 0) == nil)
    }

    @Test func numbersAreCSSFriendly() {
        #expect(CustomFontCSS.number(400) == "400")
        #expect(CustomFontCSS.number(62.5) == "62.5")
        #expect(CustomFontCSS.number(-12.25) == "-12.25")
        #expect(CustomFontCSS.number(1.0 / 3) == "0.333")
    }
}

@Suite("Custom font configuration")
struct CustomFontConfigurationTests {
    @Test func choiceTravelsToThePage() throws {
        var configuration = ReaderConfiguration()
        configuration.setCustomFont(CustomFontChoice(family: "Avenir Next", weight: 300, italic: true, stretch: 75,
                                                     variations: ["opsz": 20], features: ["smcp": 1]), faceCSS: "@font-face {}")
        #expect(configuration.fontFamily == #""aomidori-custom-font", "Avenir Next""#)
        #expect(configuration.fontWeight == 300 && configuration.fontBoldWeight == 600)
        #expect(configuration.fontItalic && configuration.fontStretch == 75)
        #expect(configuration.fontFeatureSettings == #""smcp" 1"# && configuration.fontVariationSettings == #""opsz" 20"#)
        let decoded = try JSONDecoder().decode(ReaderConfiguration.self, from: Data(configuration.json().utf8))
        #expect(decoded == configuration)

        configuration.setCustomFont(nil, faceCSS: "ignored")
        #expect(configuration == ReaderConfiguration(), "off resets every font field")
        let json = configuration.json()
        #expect(json.contains(#""fontWeight":null"#) && json.contains(#""fontStretch":null"#), "absent values are sent as null")
    }
}
