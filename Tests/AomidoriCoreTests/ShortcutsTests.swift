import Testing
@testable import AomidoriCore

@Suite("Shortcuts")
struct ShortcutsTests {
    @Test func everyCommandHasAShortcut() {
        for command in ShortcutCommand.allCases {
            #expect(Shortcuts.table[command] != nil, "\(command)")
        }
    }

    @Test func noShortcutIsUsedTwice() {
        #expect(Shortcuts.conflicts.isEmpty, "\(Shortcuts.conflicts)")
    }

    @Test func newTabAndFontPanel() {
        #expect(Shortcuts.shortcut(.newTab).description == "⌘T")
        #expect(Shortcuts.shortcut(.fontPanel).description == "⌥⌘T")
        #expect(Shortcuts.shortcut(.chooseFont).description == "⌥⌘F")
    }

    @Test func descriptions() {
        #expect(Shortcuts.shortcut(.nextChapter).description == "→")
        #expect(Shortcuts.sidebarPane(2).description == "⌥⌘2")
        #expect(KeyShortcut("m", [.command, .control, .shift, .option]).description == "⌃⌥⇧⌘M")
    }
}
