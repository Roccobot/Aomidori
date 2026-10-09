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

    @Test func finalShortcuts() {
        #expect(Shortcuts.shortcut(.newTab).description == "⌘T")
        #expect(Shortcuts.shortcut(.defineFont).description == "⇧⌘T")
        #expect(Shortcuts.shortcut(.customFont).description == "⌘Y")
        #expect(Shortcuts.shortcut(.reload).description == "⌘R")
        #expect(!Shortcuts.all.contains { $0.shortcut == KeyShortcut("f", [.command, .shift]) }, "⇧⌘F is free")
    }

    @Test func commandSIsSaveInThePlaygroundAndFreeInTheReader() {
        let uses = Shortcuts.all.filter { $0.shortcut == KeyShortcut("s") }
        #expect(uses.map(\.name) == ["playgroundSave"], "⌘S is kept free in the reader for Split")
        #expect(Shortcuts.scope(.playgroundSave) == .playground)
        #expect(Shortcuts.scope(.customFont) == .everywhere)
        #expect(Shortcuts.all.filter { $0.shortcut == KeyShortcut("y") }.map(\.name) == ["customFont"])
    }

    @Test func historyIsCommandArrowWithBracketsAsAlternatives() {
        #expect(Shortcuts.shortcut(.back).description == "⌘←")
        #expect(Shortcuts.shortcut(.forward).description == "⌘→")
        #expect(Shortcuts.shortcut(.backAlternate).description == "⌘[")
        #expect(Shortcuts.shortcut(.forwardAlternate).description == "⌘]")
        // Plain arrows stay with the chapters.
        #expect(Shortcuts.shortcut(.previousChapter) == KeyShortcut(KeyShortcut.leftArrow, []))
        #expect(Shortcuts.shortcut(.back) != Shortcuts.shortcut(.previousChapter))
    }

    @Test func findNextAndPreviousAreCommandG() {
        #expect(Shortcuts.shortcut(.findNext).description == "⌘G")
        #expect(Shortcuts.shortcut(.findPrevious).description == "⇧⌘G")
    }

    @Test func overlappingScopesConflict() {
        #expect(Shortcuts.Scope.everywhere.overlaps(.playground))
        #expect(Shortcuts.Scope.everywhere.overlaps(.outsidePlayground))
        #expect(!Shortcuts.Scope.playground.overlaps(.outsidePlayground))
        #expect(Shortcuts.Scope.playground.overlaps(.playground))
    }

    @Test func matchingKeyPresses() {
        #expect(Shortcuts.matches(KeyShortcut("s"), characters: "s", modifiers: .command))
        #expect(Shortcuts.matches(KeyShortcut("t", [.command, .shift]), characters: "T", modifiers: [.command, .shift]))
        #expect(!Shortcuts.matches(KeyShortcut("s"), characters: "s", modifiers: [.command, .shift]))
    }

    @Test func descriptions() {
        #expect(Shortcuts.shortcut(.nextChapter).description == "→")
        #expect(Shortcuts.sidebarPane(2).description == "⌥⌘2")
        #expect(KeyShortcut("m", [.command, .control, .shift, .option]).description == "⌃⌥⇧⌘M")
    }
}
