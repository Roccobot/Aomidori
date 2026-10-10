import AppKit
import AomidoriCore
import WebKit

/// A scripted Playground session for `scripts/smoke-playground.sh`, enabled by the launch
/// argument `-AomidoriPlaygroundSmoke <folder>`. It types into the editor, toggles Night,
/// saves to the styles folder (the session's own, see `AppPaths.support`), loads an EPUB if
/// `-AomidoriPlaygroundEPUB <book.epub>` is given, and writes numbered snapshots of the
/// preview and the window plus `report.json` into the folder.
@MainActor
final class PlaygroundSmokeTest {
    nonisolated static let defaultsKey = "AomidoriPlaygroundSmoke"
    static let epubDefaultsKey = "AomidoriPlaygroundEPUB"
    static let savedStyleName = "PlaygroundSmoke.css"

    private let folder: URL
    private weak var playground: PlaygroundWindowController?
    private var started = false
    private var report: [String: Any] = [:]
    /// The session runs in the background (`open -g`): no App Nap meanwhile.
    private let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Playground smoke test")

    init(folder: URL, playground: PlaygroundWindowController) {
        self.folder = folder
        self.playground = playground
    }

    func previewDidLoad() {
        log("preview loaded")
        guard !started else { return }
        started = true
        Task { await run() }
    }

    /// Progress lines in `progress.log`, to see where a session stopped.
    func log(_ message: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("progress.log")
        let line = Data("\(Date().timeIntervalSince1970) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    private func run() async {
        guard let playground else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let editor = playground.smokeEditor
        report["initialStyle"] = playground.origin?.displayName
        report["initialSelection"] = playground.smokeStyleSelection
        report["language"] = "\(editor.language)"
        report["lines"] = editor.text.split(separator: "\n", omittingEmptySubsequences: false).count
        await snapshot("1-sample")
        report["editorGeometry"] = editorGeometry(editor)
        let textView = editor.textView
        if let rep = textView.bitmapImageRepForCachingDisplay(in: textView.visibleRect) {
            textView.cacheDisplay(in: textView.visibleRect, to: rep)
            write(rep.cgImage, name: "1-editor.png")
        }

        await checkSample()

        // Typing: the preview follows after the debounce; the file on disk is untouched.
        let original = playground.origin.flatMap { try? Data(contentsOf: $0.fileURL) }
        editor.textView.setSelectedRange(NSRange(location: (editor.text as NSString).length, length: 0))
        editor.insertAsTyped("\nbody { background-color: #c33 !important; }\n")
        report["dirtyAfterTyping"] = playground.isDirty
        await snapshot("2-live")
        report["fileUnchangedAfterTyping"] = original != nil && original == playground.origin.flatMap { try? Data(contentsOf: $0.fileURL) }

        playground.toggleNight(nil)
        await snapshot("3-night")
        playground.toggleNight(nil)

        report["highlightTimings"] = measureHighlighting()

        // Save to Styles: written normalised, selected, clean, picked up by the reader.
        let saved = playground.writeToStyles(named: Self.savedStyleName, overwrite: true)
        let savedURL = AppPaths.styles.appendingPathComponent(Self.savedStyleName)
        let data = (try? Data(contentsOf: savedURL)) ?? Data()
        report["saved"] = saved
        report["savedHasBOM"] = data.starts(with: [0xEF, 0xBB, 0xBF])
        report["savedHasCR"] = data.contains(0x0D)
        report["savedEndsWithNewline"] = data.last == 0x0A
        report["dirtyAfterSave"] = playground.isDirty
        report["selectionAfterSave"] = playground.smokeStyleSelection
        try? await Task.sleep(for: .milliseconds(800))
        report["readerListsSavedStyle"] = ReaderEnvironment.shared.styles.contains { $0.name == Self.savedStyleName }

        // Back to the default style, then remove the test file.
        playground.smokeLoadStyle(named: ReaderEnvironment.shared.defaultStyleName)
        report["selectionAfterSwitch"] = playground.smokeStyleSelection
        try? FileManager.default.removeItem(at: savedURL)

        if let path = UserDefaults.standard.string(forKey: Self.epubDefaultsKey) {
            playground.loadEPUB(at: URL(fileURLWithPath: path))
            await waitForLoad()
            report["epubChapter"] = playground.smokePreview.chapterLabel
            await snapshot("4-epub")
            playground.goToNextChapter(nil)
            await waitForLoad()
            playground.goToNextChapter(nil)
            await waitForLoad()
            report["epubChapterAfterNext"] = playground.smokePreview.chapterLabel
            await snapshot("5-epub-next")
        }
        log("finished")
        report["finished"] = true
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: folder.appendingPathComponent("report.json"))
        }
    }

    /// The bundled sample: the image loads, the stylesheet applies, and two scrolled views
    /// (poem and image, table) are captured. Scrolls back to the top afterwards.
    private func checkSample() async {
        guard let webView = playground?.smokePreview.webView else { return }
        let probe = """
        (() => {
          const img = document.querySelector('img');
          const link = document.querySelector('link[rel="stylesheet"][href*=".playground-"]');
          return JSON.stringify({
            imageLoaded: !!img && img.complete && img.naturalWidth > 0,
            playgroundStylesheet: !!link && !!link.sheet && link.sheet.cssRules.length > 0,
            bodyFont: getComputedStyle(document.body).fontFamily
          });
        })()
        """
        report["sample"] = (try? await webView.evaluateJavaScript(probe)) as? String ?? "probe failed"
        for (name, selector) in [("1b-sample-poem", ".vv"), ("1c-sample-image", "img"), ("1d-sample-table", "table")] {
            _ = try? await webView.evaluateJavaScript("document.querySelector('\(selector)')?.scrollIntoView({block: 'start'})")
            await snapshot(name, window: false)
        }
        _ = try? await webView.evaluateJavaScript("window.scrollTo(0, 0)")
    }

    private func editorGeometry(_ editor: CodeEditor) -> [String: String] {
        let textView = editor.textView
        let storage = textView.textStorage
        return [
            "textViewFrame": NSStringFromRect(textView.frame),
            "visibleRect": NSStringFromRect(textView.visibleRect),
            "clipFrame": NSStringFromRect(editor.scrollView.contentView.frame),
            "containerSize": NSStringFromSize(textView.textContainer?.size ?? .zero),
            "glyphs": "\(textView.layoutManager?.numberOfGlyphs ?? -1)",
            "length": "\(storage?.length ?? -1)",
            "colorAt0": attributeDescription(.foregroundColor, in: storage),
            "fontAt0": attributeDescription(.font, in: storage),
            "isHidden": "\(textView.isHiddenOrHasHiddenAncestor)",
            "alpha": "\(textView.alphaValue)",
        ]
    }

    private func attributeDescription(_ key: NSAttributedString.Key, in storage: NSTextStorage?) -> String {
        guard let storage, storage.length > 0, let value = storage.attribute(key, at: 0, effectiveRange: nil) else {
            return "none"
        }
        return String(describing: value)
    }

    /// Tokenizing and colouring a long file (12 × ReadingRoccobot.css), then one keystroke.
    private func measureHighlighting() -> [String: Double] {
        let base = AppPaths.bundledStyle.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let long = String(repeating: base, count: 12)
        let editor = CodeEditor()
        editor.scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 800)
        let clock = ContinuousClock()
        let load = clock.measure { editor.setText(long, fileExtension: "css") }
        editor.textView.setSelectedRange(NSRange(location: 5000, length: 0))
        let keystroke = clock.measure { editor.insertAsTyped("x") }
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        return ["lines": Double(long.split(separator: "\n", omittingEmptySubsequences: false).count),
                "loadMs": milliseconds(load), "keystrokeMs": milliseconds(keystroke)]
    }

    private func waitForLoad() async {
        try? await Task.sleep(for: .milliseconds(300))
        for _ in 0..<40 where playground?.smokePreview.webView.isLoading == true {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func snapshot(_ name: String, window: Bool = true) async {
        log("snapshot \(name)")
        try? await Task.sleep(for: .milliseconds(900))
        guard let playground else { return }
        if let image = try? await playground.smokePreview.webView.takeSnapshot(configuration: nil) {
            write(image.cgImage(forProposedRect: nil, context: nil, hints: nil), name: "\(name).png")
        }
        if window, let frameView = playground.window?.contentView?.superview,
           let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            write(rep.cgImage, name: "\(name).window.png")
        }
    }

    private func write(_ image: CGImage?, name: String) {
        guard let image else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
            .write(to: folder.appendingPathComponent(name))
    }
}
