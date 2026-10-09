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
        #expect(Shortcuts.shortcut(.customFont).description == "⌘S")
        #expect(!Shortcuts.all.contains { $0.shortcut == KeyShortcut("f", [.command, .shift]) }, "⇧⌘F is free")
    }

    @Test func commandSIsSaveOnlyInThePlayground() {
        let uses = Shortcuts.all.filter { $0.shortcut == KeyShortcut("s") }
        #expect(Set(uses.map(\.name)) == ["playgroundSave", "customFont"])
        #expect(Shortcuts.scope(.playgroundSave) == .playground && Shortcuts.scope(.customFont) == .outsidePlayground)
        #expect(Shortcuts.conflicts[KeyShortcut("s")] == nil)
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
