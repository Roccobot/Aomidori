import Foundation
import Testing
@testable import AomidoriCore

@Suite("Custom font")
struct CustomFontTests {
    @Test func fontFacesUseThePrivateAlias() {
        let css = CustomFontCSS.fontFaceCSS([
            FontFaceSource(postScriptName: "MiSans-Regular", url: "/.aomidori/SystemFonts/0-MiSans-Regular.ttf", weight: 400),
            FontFaceSource(url: "/.aomidori/Fonts/My \"Font\".otf", weight: 700, italic: true),
            FontFaceSource(weight: 300),
        ])
        let lines = css.split(separator: "\n")
        #expect(lines.count == 2) // a face without sources is dropped
        #expect(lines[0] == #"@font-face { font-family: "aomidori-custom-font"; src: local("MiSans-Regular"), url("/.aomidori/SystemFonts/0-MiSans-Regular.ttf"); font-weight: 400; font-style: normal; font-stretch: 100%; font-display: block; }"#)
        #expect(lines[1].contains(#"src: url("/.aomidori/Fonts/My \"Font\".otf")"#))
        #expect(lines[1].contains("font-weight: 700; font-style: italic"))
        #expect(CustomFontCSS.fontFaceCSS([]).isEmpty)
    }

    @Test func familyListFallsBackToTheRealName() {
        #expect(CustomFontCSS.familyList("Iowan Old Style") == #""aomidori-custom-font", "Iowan Old Style""#)
    }

    @Test func weightsMapToCSS() {
        #expect(CustomFontCSS.cssWeight(fromTrait: 0) == 400)
        #expect(CustomFontCSS.cssWeight(fromTrait: 0.4) == 700)
        #expect(CustomFontCSS.cssWeight(fromTrait: -0.4) == 300)
        #expect(CustomFontCSS.cssWeight(fromTrait: 0.25) == 500)
        #expect(CustomFontCSS.cssWeight(fromTrait: -1) == 100)
        #expect(CustomFontCSS.cssWeight(fromTrait: 1) == 900)
    }

    @Test func configurationCarriesTheFont() throws {
        let configuration = ReaderConfiguration(fontFamily: CustomFontCSS.familyList("A"), fontFaceCSS: "x")
        let json = configuration.json()
        #expect(json.contains(#""fontFaceCSS":"x""#))
        #expect(json.contains("aomidori-custom-font"))
        let off = ReaderConfiguration().json()
        #expect(off.contains(#""fontFamily":null"#) && off.contains(#""styleHref":null"#))
        let decoded = try JSONDecoder().decode(ReaderConfiguration.self, from: Data(json.utf8))
        #expect(decoded == configuration)
    }
}
