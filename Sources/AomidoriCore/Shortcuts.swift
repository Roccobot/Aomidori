import Foundation

/// A key equivalent: the key (as AppKit's `keyEquivalent` string) and its modifiers.
public struct KeyShortcut: Hashable, Sendable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public let key: String
    public let modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = .command) {
        self.key = key
        self.modifiers = modifiers
    }

    /// `NSLeftArrowFunctionKey` and `NSRightArrowFunctionKey` as key equivalents.
    public static let leftArrow = String(UnicodeScalar(0xF702)!)
    public static let rightArrow = String(UnicodeScalar(0xF703)!)

    /// "⇧⌘T", for messages and tests.
    public var description: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let keyName = switch key {
        case Self.leftArrow: "←"
        case Self.rightArrow: "→"
        default: key.uppercased()
        }
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }
}

/// Every menu command that has a shortcut. The keys live in `Shortcuts.table`, in one place,
/// so a shortcut is moved with a one-line change and conflicts are caught by a test.
public enum ShortcutCommand: String, CaseIterable, Sendable {
    // App
    case hide, hideOthers, quit
    // File
    case open, newTab, inspector, playgroundOpenCSS, playgroundLoadEPUB, playgroundSample, close
    case playgroundSave, playgroundSaveAs
    // Edit
    case undo, redo, cut, copy, paste, selectAll, find, findNext, findPrevious, useSelectionForFind
    // View
    case sidebar, minimal, night, larger, smaller, actualSize, fullScreen
    // Go
    case previousChapter, nextChapter, back, forward, backAlternate, forwardAlternate, addBookmark
    // Style
    case override, previousStyle, nextStyle, styleList, reload, playground
    case customFont, defineFont
    // Window
    case minimize
}

public enum Shortcuts {
    /// The shortcuts, designed for the Italian keyboard layout (`⌘'`, `⌘ì`).
    public static let table: [ShortcutCommand: KeyShortcut] = [
        .hide: KeyShortcut("h"),
        .hideOthers: KeyShortcut("h", [.command, .option]),
        .quit: KeyShortcut("q"),

        .open: KeyShortcut("o"),
        // ⌘T was the Font panel's in 0.4: New Tab takes it, as in Safari and Finder.
        .newTab: KeyShortcut("t"),
        .inspector: KeyShortcut("i"),
        .playgroundOpenCSS: KeyShortcut("o", [.command, .shift]),
        .playgroundLoadEPUB: KeyShortcut("o", [.command, .option]),
        .playgroundSample: KeyShortcut("e", [.command, .shift]),
        .close: KeyShortcut("w"),
        .playgroundSave: KeyShortcut("s"),
        .playgroundSaveAs: KeyShortcut("s", [.command, .shift]),

        .undo: KeyShortcut("z"),
        .redo: KeyShortcut("z", [.command, .shift]),
        .cut: KeyShortcut("x"),
        .copy: KeyShortcut("c"),
        .paste: KeyShortcut("v"),
        .selectAll: KeyShortcut("a"),
        .find: KeyShortcut("f"),
        .findNext: KeyShortcut("g"),
        .findPrevious: KeyShortcut("g", [.command, .shift]),
        .useSelectionForFind: KeyShortcut("e"),

        .sidebar: KeyShortcut("\\"),
        .minimal: KeyShortcut("m", [.command, .control]),
        .night: KeyShortcut("n", [.command, .shift]),
        .larger: KeyShortcut("+"),
        .smaller: KeyShortcut("-"),
        .actualSize: KeyShortcut("0"),
        .fullScreen: KeyShortcut("f", [.command, .control]),

        .previousChapter: KeyShortcut(KeyShortcut.leftArrow, []),
        .nextChapter: KeyShortcut(KeyShortcut.rightArrow, []),
        // The reader's own history of links followed (notes, chapters, anchors), since 0.53;
        // `⌘[` `⌘]` (0.5x) stay as hidden alternatives. Off while typing, so text fields and
        // the Playground editor keep `⌘←` `⌘→` for the cursor.
        .back: KeyShortcut(KeyShortcut.leftArrow),
        .forward: KeyShortcut(KeyShortcut.rightArrow),
        .backAlternate: KeyShortcut("["),
        .forwardAlternate: KeyShortcut("]"),
        .addBookmark: KeyShortcut("d"),

        .override: KeyShortcut("."),
        .previousStyle: KeyShortcut("'"),
        .nextStyle: KeyShortcut("\u{00EC}"),
        .styleList: KeyShortcut("1"),
        // The chapter from the book and the style from disk, keeping the reading position.
        .reload: KeyShortcut("r"),
        .playground: KeyShortcut("p", [.command, .shift]),
        // Book or style font ↔ custom font. ⌘S until 0.52; since 0.53 ⌘S is left free in the
        // reader (for Split) and is Save only in the Playground.
        .customFont: KeyShortcut("y"),
        // The custom font chooser, with a button for the system Font panel.
        .defineFont: KeyShortcut("t", [.command, .shift]),

        .minimize: KeyShortcut("m"),
    ]

    /// Plain keys (no modifiers) that work while reading, besides `←` `→`: only with the page
    /// in focus, never in a text field, the search field or the Playground editor (the reader
    /// window routes them before the page sees them). `T` swaps light and dark like `⇧⌘N`.
    public static let readingKeys: [String: ShortcutCommand] = [
        "t": .night,
        "+": .larger, "=": .larger,
        "-": .smaller,
        "0": .actualSize,
    ]

    /// The command of a plain key pressed while reading (`characters` without modifiers).
    public static func readingCommand(characters: String) -> ShortcutCommand? {
        readingKeys[characters.lowercased()]
    }

    /// The windows a command's shortcut acts in. Two commands may share a shortcut only if
    /// their scopes do not overlap: the key then means one thing per window.
    public enum Scope: Sendable {
        case everywhere
        /// The CSS Playground window.
        case playground
        /// Any window but the Playground (reader windows, the empty window, panels). No command
        /// uses it since `⌘S` left the custom font (0.53); kept for keys that will mean one
        /// thing in the reader and another in the Playground.
        case outsidePlayground

        func overlaps(_ other: Scope) -> Bool {
            switch (self, other) {
            case (.playground, .outsidePlayground), (.outsidePlayground, .playground): false
            default: true
            }
        }
    }

    public static func scope(_ command: ShortcutCommand) -> Scope {
        switch command {
        case .playgroundOpenCSS, .playgroundLoadEPUB, .playgroundSample, .playgroundSave, .playgroundSaveAs: .playground
        default: .everywhere
        }
    }

    /// The shortcut of a command.
    public static func shortcut(_ command: ShortcutCommand) -> KeyShortcut {
        table[command]!
    }

    /// `⌥⌘1`…: the sidebar panes, by digit.
    public static func sidebarPane(_ digit: Int) -> KeyShortcut {
        KeyShortcut("\(digit)", [.command, .option])
    }

    /// Every shortcut in the menus, the sidebar panes' included, with what it does and where.
    public static var all: [(name: String, shortcut: KeyShortcut, scope: Scope)] {
        ShortcutCommand.allCases.map { ($0.rawValue, shortcut($0), scope($0)) }
            + SidebarPane.allCases.map { ("sidebar.\($0)", sidebarPane($0.shortcutDigit), .everywhere) }
    }

    /// Shortcuts used by more than one command in the same window.
    public static var conflicts: [KeyShortcut: [String]] {
        Dictionary(grouping: all, by: \.shortcut).compactMapValues { uses in
            let clashing = uses.enumerated().filter { index, use in
                uses.enumerated().contains { other, otherUse in other != index && use.scope.overlaps(otherUse.scope) }
            }
            return clashing.isEmpty ? nil : clashing.map(\.element.name)
        }
    }

    /// Whether a key press (its characters without modifiers, and its modifiers) is the shortcut.
    public static func matches(_ shortcut: KeyShortcut, characters: String, modifiers: KeyShortcut.Modifiers) -> Bool {
        characters.lowercased() == shortcut.key.lowercased() && modifiers == shortcut.modifiers
    }
}
