import Testing
@testable import AomidoriCore

@Suite("Page paths")
struct PagePathTests {
    @Test func bookResourcesAndUserFolders() {
        #expect(PagePath("OEBPS/Text/c1.xhtml") == .book("OEBPS/Text/c1.xhtml"))
        #expect(PagePath(".aomidori/Styles/ReadingRoccobot.css") == .userFile(["Styles", "ReadingRoccobot.css"]))
        #expect(PagePath(".aomidori/Fonts/MiSans/Regular.otf") == .userFile(["Fonts", "MiSans", "Regular.otf"]))
        #expect(PagePath(".aomidori/Styles/.playground-1.css") == .playgroundBuffer(".playground-1.css"))
        #expect(PagePath(".aomidori/SystemFonts/abc") == .systemFont(token: "abc"))
    }

    /// Nothing outside the two user folders can be named: no climbing out, no other folder.
    @Test func nothingElseOnDiskIsReachable() {
        for path in [".aomidori/Styles/../Positions.json", ".aomidori/../../etc/hosts", ".aomidori/./Styles/a.css",
                     ".aomidori/Books.json", ".aomidori/Styles", ".aomidori/Styles//a.css", ".aomidori/",
                     ".aomidori/SystemFonts/a/b", ".aomidori/Library/a"] {
            #expect(PagePath(path) == nil, "\(path)")
        }
    }
}
