import AppKit
import AomidoriCore

/// The Playground's source editor: a native text view (undo, find bar, services) with a
/// monospaced font, line numbers, two-space indentation and syntax colouring.
///
/// Colouring is incremental: after each edit the whole text is tokenized again (about 2 ms
/// for 4,000 lines of CSS) and only the span whose tokens changed gets new attributes (see
/// `SyntaxHighlighter.restyleRange`), so typing stays cheap in long files.
@MainActor
final class CodeEditor: NSObject, NSTextStorageDelegate, NSTextViewDelegate {
    let scrollView = NSScrollView()
    let textView: CodeTextView
    private let ruler: LineNumberRuler

    /// Called after every change of the text by the user (not by `setText`).
    var onChange: (() -> Void)?

    private(set) var language: SyntaxLanguage = .css
    private var tokens: [SyntaxToken] = []
    private var fileExtension: String?
    private var isReplacingText = false

    static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    override init() {
        // TextKit 1: line numbers need line fragment geometry, which NSLayoutManager gives cheaply.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        textView = CodeTextView(frame: .zero, textContainer: container)
        ruler = LineNumberRuler(textView: textView)
        super.init()

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.font = Self.font
        textView.textColor = .textColor
        textView.typingAttributes = Self.baseAttributes
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel(L10n.string("playground.editor"))
        textView.delegate = self
        storage.delegate = self

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.findBarPosition = .aboveContent
    }

    var text: String { textView.string }

    /// Replaces the whole text (a style was loaded): colours everything, clears undo, puts
    /// the caret at the top.
    func setText(_ text: String, fileExtension: String?) {
        self.fileExtension = fileExtension
        language = SyntaxLanguage.detect(text: text, fileExtension: fileExtension)
        tokens = []
        isReplacingText = true
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.baseAttributes))
        isReplacingText = false
        restyleAll()
        textView.undoManager?.removeAllActions()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        ruler.invalidateLines()
    }

    /// Inserts text at the selection as if typed (undoable; marks the buffer as changed).
    func insertAsTyped(_ text: String) {
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    // MARK: Colouring

    private static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.textColor]
    }

    private static func color(for kind: SyntaxTokenKind) -> NSColor {
        switch kind {
        case .comment: .secondaryLabelColor
        case .string: .systemRed
        case .number, .entity: .systemPurple
        case .color: .systemIndigo
        case .atRule: .systemPink
        case .selector: .systemTeal
        case .property, .tag: .systemBlue
        case .keyword: .systemBrown
        case .important: .systemOrange
        case .attribute: .systemOrange
        }
    }

    private func restyleAll() {
        guard let storage = textView.textStorage else { return }
        tokens = SyntaxHighlighter.tokens(in: Array(storage.string.utf16), language: language)
        apply(tokens, in: 0..<storage.length, to: storage)
    }

    private func apply(_ tokens: [SyntaxToken], in range: Range<Int>, to storage: NSTextStorage) {
        guard !range.isEmpty else { return }
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: NSRange(range))
        // Tokens are sorted: binary search for the first one ending after the range start.
        var low = 0, high = tokens.count
        while low < high {
            let middle = (low + high) / 2
            if tokens[middle].range.upperBound <= range.lowerBound { low = middle + 1 } else { high = middle }
        }
        var index = low
        while index < tokens.count, tokens[index].range.lowerBound < range.upperBound {
            let token = tokens[index]
            let clipped = max(token.range.lowerBound, range.lowerBound)..<min(token.range.upperBound, range.upperBound)
            if !clipped.isEmpty {
                storage.addAttribute(.foregroundColor, value: Self.color(for: token.kind), range: NSRange(clipped))
            }
            index += 1
        }
    }

    nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                 range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // The editor's storage is only ever edited on the main thread, by its text view.
        MainActor.assumeIsolated {
            highlight(editedRange: editedRange, changeInLength: delta)
        }
    }

    private func highlight(editedRange: NSRange, changeInLength delta: Int) {
        guard !isReplacingText, let textStorage = textView.textStorage else { return }
        let units = Array(textStorage.string.utf16)
        // Content pasted into an empty buffer may be another language.
        if tokens.isEmpty, editedRange.location == 0, editedRange.length == units.count {
            language = SyntaxLanguage.detect(text: textStorage.string, fileExtension: fileExtension)
        }
        let updated = SyntaxHighlighter.tokens(in: units, language: language)
        let range = SyntaxHighlighter.restyleRange(
            old: tokens, new: updated, location: editedRange.location,
            oldLength: editedRange.length - delta, newLength: editedRange.length)
        tokens = updated
        apply(updated, in: range.clamped(to: 0..<units.count), to: textStorage)
        ruler.invalidateLines()
    }

    func textDidChange(_ notification: Notification) {
        onChange?()
    }
}

/// A text view for code: Tab inserts two spaces, ⇧Tab removes up to two, Return keeps the
/// line's indentation (one level more after `{`).
@MainActor
final class CodeTextView: NSTextView {
    static let indent = "  "

    override func insertTab(_ sender: Any?) {
        insertText(Self.indent, replacementRange: selectedRange())
    }

    override func insertBacktab(_ sender: Any?) {
        let string = self.string as NSString
        let lineStart = string.lineRange(for: NSRange(location: selectedRange().location, length: 0)).location
        var length = 0
        while length < Self.indent.count, lineStart + length < string.length, string.character(at: lineStart + length) == 0x20 {
            length += 1
        }
        guard length > 0 else { return }
        insertText("", replacementRange: NSRange(location: lineStart, length: length))
    }

    override func insertNewline(_ sender: Any?) {
        let string = self.string as NSString
        let caret = selectedRange().location
        let lineStart = string.lineRange(for: NSRange(location: caret, length: 0)).location
        var indentEnd = lineStart
        while indentEnd < caret, [0x20, 0x09].contains(string.character(at: indentEnd)) { indentEnd += 1 }
        var indent = string.substring(with: NSRange(location: lineStart, length: indentEnd - lineStart))
        var before = caret - 1
        while before >= lineStart, [0x20, 0x09].contains(string.character(at: before)) { before -= 1 }
        if before >= lineStart, string.character(at: before) == 0x7B { indent += Self.indent }
        insertText("\n" + indent, replacementRange: selectedRange())
    }
}

/// Line numbers beside the editor, drawn for the visible lines only.
@MainActor
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?
    /// UTF-16 offset of the start of every line; recomputed lazily after edits.
    private var lineStarts: [Int] = [0]
    private var linesAreValid = false
    private var observers: [any NSObjectProtocol] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: nil, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 36
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        guard let clip = scrollView?.contentView else { return }
        clip.postsBoundsChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        })
    }

    func invalidateLines() {
        linesAreValid = false
        needsDisplay = true
    }

    private func updateLines() {
        guard !linesAreValid, let textView else { return }
        var starts = [0]
        var offset = 0
        for unit in textView.string.utf16 {
            offset += 1
            if unit == 0x0A { starts.append(offset) }
        }
        lineStarts = starts
        linesAreValid = true
        let digits = max(3, String(starts.count).count)
        let width = CGFloat(digits) * 7.5 + 14
        if abs(ruleThickness - width) > 0.5 { ruleThickness = width }
    }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor]
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        updateLines()
        guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        rect.fill()
        let length = (textView.string as NSString).length
        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // The first line starting at or before the first visible character.
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if lineStarts[middle] <= characters.location { low = middle } else { high = middle - 1 }
        }
        let attributes = attributes
        var line = low
        while line < lineStarts.count, lineStarts[line] <= NSMaxRange(characters) {
            let start = lineStarts[line]
            let fragment: NSRect
            if start < length {
                fragment = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
            } else {
                fragment = layoutManager.extraLineFragmentRect
            }
            let y = convert(NSPoint(x: 0, y: fragment.minY + textView.textContainerOrigin.y), from: textView).y
            let label = NSAttributedString(string: "\(line + 1)", attributes: attributes)
            let size = label.size()
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y + (fragment.height - size.height) / 2))
            line += 1
        }
    }
}
