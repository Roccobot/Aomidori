import AppKit
import CoreText
import AomidoriCore
import EPUBKit
import WebKit

/// Stands for any server during a smoke session: it only counts what reaches it.
@MainActor
final class OfflineProbe: NSObject, WKURLSchemeHandler {
    static let scheme = "aomidori-probe"
    static let shared = OfflineProbe()
    var requests = 0

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        requests += 1
        task.didFailWithError(URLError(.cancelled))
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// A scripted reader session for `scripts/smoke-reader.sh`, enabled by the launch argument
/// `-AomidoriReaderSmoke <folder>`. With the book's first spine item (usually the cover) it
/// measures the picture at three window sizes and three rendering modes; then it checks the
/// per-chapter position memory and the chapter-edge toast; then the custom font (AppKit fonts
/// turned into choices, and choices rendered in a chapter), the book information window, and
/// the history of followed links (`⌘←` `⌘→`), and last that nothing outside the book loads. Snapshots and `report.json` go in the
/// folder. Reading state is kept there too (see `AppPaths`), settings are never changed, and
/// the window frame is put back at the end.
@MainActor
final class ReaderSmokeTest {
    nonisolated static let defaultsKey = "AomidoriReaderSmoke"
    static var isActive: Bool { UserDefaults.standard.string(forKey: defaultsKey) != nil }

    private let folder: URL
    private weak var windowController: ReaderWindowController?
    private var report: [String: Any] = [:]
    private var failures: [String] = []
    /// The session runs in the background (`open -g`): no App Nap meanwhile.
    private let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Reader smoke test")

    init?(windowController: ReaderWindowController) {
        guard let path = UserDefaults.standard.string(forKey: Self.defaultsKey) else { return nil }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        self.windowController = windowController
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { await run() }
    }

    private var reader: ReaderViewController? { windowController?.reader }

    private func run() async {
        guard let windowController, let window = windowController.window, let reader else { return }
        log("started")
        await waitForLoad()
        let originalFrame = window.frame
        let book = reader.book
        report["spine"] = book.spine.count
        report["tableOfContentsIndex"] = book.tableOfContentsIndex ?? -1

        // 1. The first spine item at three window sizes and three modes.
        reader.showSpineItem(at: 0, landing: .top)
        await waitForLoad()
        var covers: [[String: Any]] = []
        let modes: [(String, ((inout ReaderConfiguration) -> Void)?)] = [
            ("default", nil),
            ("override-scale1.6", { $0.overrideEnabled = true; $0.scale = 1.6 }),
            ("night-book-scale0.8", { $0.overrideEnabled = false; $0.night = true; $0.scale = 0.8 }),
        ]
        for size in [NSSize(width: 560, height: 860), NSSize(width: 1500, height: 720), NSSize(width: 900, height: 1040)] {
            window.setContentSize(size)
            for (name, change) in modes {
                reader.smokeConfigure(change)
                try? await Task.sleep(for: .milliseconds(700))
                var entry = await measureCover()
                entry["window"] = "\(Int(size.width))x\(Int(size.height))"
                entry["mode"] = name
                covers.append(entry)
                if entry["centred"] as? Bool != true { failures.append("cover \(entry["window"]!) \(name)") }
                await snapshot("cover-\(Int(size.width))x\(Int(size.height))-\(name)")
            }
        }
        reader.smokeConfigure(nil)
        report["covers"] = covers
        window.setFrame(originalFrame, display: true)
        try? await Task.sleep(for: .milliseconds(500))

        // 2. The chapter-edge toast on the cover (a page that cannot scroll), through a real
        // key event, then a click: the next chapter opens at the top.
        report["edgesOnFirstItem"] = "\(reader.smokeEdges)"
        let keyRouted = postKey(KeyCode.space, in: window)
        try? await Task.sleep(for: .milliseconds(300))
        report["keyWindowIsReader"] = NSApp.keyWindow === window
        report["spaceOnCoverShows"] = reader.smokeToast.map { "\($0)" } ?? "nothing"
        if !keyRouted || reader.smokeToast == nil {
            _ = reader.handleEdgeKey(.forward)
            report["spaceOnCoverShowsDirect"] = reader.smokeToast.map { "\($0)" } ?? "nothing"
        }
        await snapshotWindow("toast-cover")

        // 3. Position memory: halfway down the next chapter, away and back.
        guard let next = reader.nextChapterIndex else { return finish(window: window, originalFrame: originalFrame) }
        reader.showSpineItem(at: next, landing: .top)
        await waitForLoad()
        reader.smokeScroll(toFraction: 0.5)
        try? await Task.sleep(for: .milliseconds(600))
        let left = await reader.smokeCurrentPosition()
        report["leftChapterAt"] = left.map { "\($0.fraction) \($0.anchor ?? "-")" } ?? "nil"
        reader.goToPreviousChapter()
        await waitForLoad()
        reader.goToNextChapter()
        await waitForLoad()
        try? await Task.sleep(for: .milliseconds(500))
        let back = await reader.smokeCurrentPosition()
        report["backInChapterAt"] = back.map { "\($0.fraction) \($0.anchor ?? "-")" } ?? "nil"
        if let left, let back, abs(left.fraction - back.fraction) > 0.02 { failures.append("position memory") }
        report["storedChapterPosition"] = ReaderEnvironment.shared.positions
            .chapterPosition(forBook: reader.bookKey, spinePath: book.spine[next].path).map { "\($0.fraction)" } ?? "nil"

        // The toast from the previous item goes to the top of this chapter, whatever was remembered.
        reader.goToPreviousChapter()
        await waitForLoad()
        _ = reader.handleEdgeKey(.forward)
        reader.smokeClickToast()
        await waitForLoad()
        try? await Task.sleep(for: .milliseconds(400))
        let landed = await reader.smokeCurrentPosition()
        report["toastNextLandsAt"] = landed?.fraction ?? -1
        if (landed?.fraction ?? -1) != 0 { failures.append("toast lands at the top") }

        // 4. Bottom of the chapter: a wheel notch, then the toast says next chapter or end of book.
        reader.smokeScroll(toFraction: 1)
        try? await Task.sleep(for: .milliseconds(600))
        report["edgesAtBottom"] = "\(reader.smokeEdges)"
        if let wheel = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0),
           let event = NSEvent(cgEvent: wheel) {
            _ = reader.handleEdgeScroll(event)
        }
        report["wheelAtBottomShows"] = reader.smokeToast.map { "\($0)" } ?? "nothing"
        await snapshotWindow("toast-bottom")

        // 5. The custom font, rendered only (the saved choice is not changed).
        report["fontConversions"] = fontConversions()
        reader.smokeScroll(toFraction: 0)
        var rendered: [String: Any] = [:]
        for (name, choice) in Self.fontChoices() {
            reader.smokeConfigure { $0 = ReaderEnvironment.shared.configuration(customFont: choice) }
            try? await Task.sleep(for: .milliseconds(900))
            rendered[name] = await measureFont()
            await snapshot("font-\(name)")
        }
        reader.smokeConfigure(nil)
        report["fontRendered"] = rendered

        // 6. Book information: the book's title, and both tabs laid out from the top.
        await checkInspector()

        // 7. The reader's history: links followed from partway down a chapter, then back and
        // forward to the exact places.
        await checkHistory()

        // 8. Offline: a picture, a sheet and a font outside the book's scheme never load.
        await checkOffline()

        // 9. A book sheet dressed as one of the reader's own still loses to the override.
        await checkForgedMarks()

        // 10. Running text is flush left over the book's justify, without automatic hyphenation;
        // ⌘J's setting makes it justified and hyphenated, whatever the book says; centred text
        // keeps its alignment and its hyphenation.
        await checkAlignment()

        // 11. ⇧-click opens a link in a new tab in front, ⌥-click in a new tab behind, each one
        // a second view of the book at the link's target, beside this tab; this view stays put.
        // With "Open links in new tabs" on, a plain click opens one in front.
        await checkLinksInNewTabs()
        finish(window: window, originalFrame: originalFrame)
    }

    private func checkLinksInNewTabs() async {
        guard let windowController, let window = windowController.window, let reader,
              let document = windowController.document as? NSDocument,
              let target = reader.book.nextReadableIndex(after: 0) else { return }
        func views() -> [ReaderWindowController] { document.windowControllers.compactMap { $0 as? ReaderWindowController } }
        let before = views().count
        let sourcePath = reader.currentPath
        let click = """
        const a = document.createElement('a');
        a.href = new URL('/' + href, location.href).href;
        a.textContent = '·';
        document.body.insertBefore(a, document.body.firstChild);
        a.dispatchEvent(new MouseEvent('click', {bubbles: true, cancelable: true, shiftKey: shift, altKey: option, view: window}));
        a.remove();
        """
        var result: [String: Any] = [:]
        let environment = ReaderEnvironment.shared
        // The last one with "Open links in new tabs" on (this session's own settings).
        for (name, shift, option, newTabs) in [("shift", true, false, false), ("option", false, true, false), ("plainWithSetting", false, false, true)] {
            environment.opensLinksInNewTabs = newTabs
            defer { environment.opensLinksInNewTabs = false }
            let known = Set(views().map(ObjectIdentifier.init))
            _ = try? await reader.webView.callAsyncJavaScript(click, arguments: ["href": reader.book.spine[target].path, "shift": shift, "option": option],
                                                              in: nil, contentWorld: .defaultClient)
            try? await Task.sleep(for: .milliseconds(1500))
            let tab = views().first { !known.contains(ObjectIdentifier($0)) }
            result[name] = [
                "newTabPath": tab?.reader.currentPath ?? "",
                "besideSource": tab?.window?.tabbedWindows?.contains(window) == true,
                "selected": tab?.window.map { $0.tabGroup?.selectedWindow === $0 } ?? false,
                "sourceStays": reader.currentPath == sourcePath,
            ] as [String: Any]
            if tab == nil { failures.append("links: \(name)-click opens a new tab") }
            if tab?.reader.currentPath != reader.book.spine[target].path { failures.append("links: \(name)-click shows the link's target") }
            if tab?.window?.tabbedWindows?.contains(window) != true { failures.append("links: \(name)-click tab beside its source") }
            if (tab?.window.map { $0.tabGroup?.selectedWindow === $0 } ?? false) != !option {
                failures.append("links: \(name)-click tab \(option ? "behind" : "in front")")
            }
            if reader.currentPath != sourcePath { failures.append("links: the source tab stays where it was (\(name))") }
            window.tabGroup?.selectedWindow = window
        }
        report["linksInNewTabs"] = result
        views().filter { $0 !== windowController }.forEach { $0.close() }
        try? await Task.sleep(for: .milliseconds(400))
        if views().count != before { failures.append("links: the extra views close") }
        window.makeKeyAndOrderFront(nil)
    }

    private func checkAlignment() async {
        guard let reader else { return }
        let ids = ["aomidori-smoke-justify", "aomidori-smoke-left", "aomidori-smoke-centre"]
        let insert = """
        for (const [id, align, hyphens] of [[ids[0], 'justify', 'auto'], [ids[1], 'left', 'manual'], [ids[2], 'center', 'auto']]) {
          const p = document.createElement('p'); p.id = id; p.textContent = 'Testo di prova.';
          p.style.textAlign = align; p.style.webkitHyphens = hyphens; p.style.hyphens = hyphens;
          document.body.appendChild(p);
        }
        """
        _ = try? await reader.webView.callAsyncJavaScript(insert, arguments: ["ids": ids], in: nil, contentWorld: .defaultClient)
        let read = """
        return ids.map(id => {
          const style = getComputedStyle(document.getElementById(id));
          return `${style.textAlign}/${style.hyphens || style.webkitHyphens}`;
        }).join(' ');
        """
        // Justified first: an unchanged configuration is not applied again, and the paragraphs
        // just inserted are read only when a change reaches the page.
        reader.smokeConfigure { $0.justified = true }
        try? await Task.sleep(for: .milliseconds(500))
        let justified = try? await reader.webView.callAsyncJavaScript(read, arguments: ["ids": ids], in: nil, contentWorld: .defaultClient) as? String
        reader.smokeConfigure { $0.justified = false }
        try? await Task.sleep(for: .milliseconds(500))
        let flush = try? await reader.webView.callAsyncJavaScript(read, arguments: ["ids": ids], in: nil, contentWorld: .defaultClient) as? String
        reader.smokeConfigure(nil)
        report["alignment"] = ["default": flush ?? "nil", "justified": justified ?? "nil"]
        if flush != "left/manual left/manual center/auto" {
            failures.append("alignment: flush left without hyphenation by default, centred kept")
        }
        if justified != "justify/auto justify/auto center/auto" {
            failures.append("alignment: justified and hyphenated with the setting, centred kept")
        }
    }

    /// A book can write `data-aomidori…` attributes too: a sheet carrying the reader's own
    /// mark and an already-stashed media must still be switched off by *Override Book Style*.
    private func checkForgedMarks() async {
        guard let reader else { return }
        reader.smokeConfigure { $0.overrideEnabled = false }
        try? await Task.sleep(for: .milliseconds(500))
        let insert = """
        const style = document.createElement('style');
        style.setAttribute('data-aomidori', 'base');
        style.setAttribute('data-aomidori-media', '-');
        style.textContent = 'body p { color: rgb(1, 2, 3) !important; }';
        document.head.appendChild(style);
        const p = document.createElement('p'); p.id = 'aomidori-smoke-forged'; p.textContent = '·';
        document.body.appendChild(p);
        return getComputedStyle(p).color;
        """
        let before = try? await reader.webView.callAsyncJavaScript(insert, arguments: [:], in: nil, contentWorld: .defaultClient)
        reader.smokeConfigure { $0.overrideEnabled = true }
        try? await Task.sleep(for: .milliseconds(700))
        let after = try? await reader.webView.callAsyncJavaScript(
            "return getComputedStyle(document.getElementById('aomidori-smoke-forged')).color",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        reader.smokeConfigure(nil)
        report["forgedSheet"] = "\(before as? String ?? "?") -> \(after as? String ?? "?")"
        if (after as? String) == "rgb(1, 2, 3)" { failures.append("override: a sheet with a forged reader mark survives") }
    }

    /// The page asks for a picture, a style sheet and a font from `OfflineProbe`'s scheme, which
    /// stands for any server: the offline rules must stop all three before they leave the page.
    private func checkOffline() async {
        guard let reader else { return }
        OfflineProbe.shared.requests = 0
        let probe = "\(OfflineProbe.scheme)://probe"
        let script = """
        const img = document.createElement('img'); img.src = probe + '/pixel.png';
        const link = document.createElement('link'); link.rel = 'stylesheet'; link.href = probe + '/sheet.css';
        const style = document.createElement('style');
        style.textContent = "@font-face { font-family: AomidoriProbe; src: url('" + probe + "/font.woff2'); } body { font-family: AomidoriProbe; }";
        document.head.append(link, style); document.body.append(img);
        """
        _ = try? await reader.webView.callAsyncJavaScript(script, arguments: ["probe": probe], in: nil, contentWorld: .defaultClient)
        try? await Task.sleep(for: .milliseconds(1500))
        report["offlineProbeRequests"] = OfflineProbe.shared.requests
        if OfflineProbe.shared.requests != 0 { failures.append("offline: resources outside the book were requested") }
    }

    /// A link to another chapter and a link to an anchor in the same chapter, each clicked from
    /// partway down the page: Back must return there (±2%), Forward to where the link went.
    private func checkHistory() async {
        // The chapter after the cover, linking to the next one (or back to the cover, in a
        // two-item book like the test book).
        guard let reader, let from = reader.book.nextReadableIndex(after: 0) else { return }
        let to = reader.book.nextReadableIndex(after: from) ?? 0
        guard to != from else { return }
        let book = reader.book
        var result: [String: Any] = [:]
        reader.showSpineItem(at: from, landing: .top)
        await waitForLoad()

        func click(href: String, addingTargetAtEnd: Bool, newWindow: Bool = false) async {
            let script = """
            if (addTarget) {
              const target = document.createElement('p'); target.id = 'aomidori-smoke-target'; target.textContent = '·';
              document.body.appendChild(target);
            }
            const a = document.createElement('a');
            a.href = href.startsWith('#') ? href : new URL('/' + href, location.href).href;
            if (newWindow) a.target = '_blank';
            a.textContent = '·';
            document.body.insertBefore(a, document.body.firstChild);
            a.click();
            return a.href;
            """
            _ = try? await reader.webView.callAsyncJavaScript(script, arguments: ["href": href, "addTarget": addingTargetAtEnd, "newWindow": newWindow],
                                                              in: nil, contentWorld: .defaultClient)
        }

        // A chapter link.
        reader.smokeScroll(toFraction: 0.4)
        try? await Task.sleep(for: .milliseconds(600))
        let before = await reader.smokeCurrentPosition()
        await click(href: book.spine[to].path, addingTargetAtEnd: false)
        await waitForLoad()
        result["chapterLinkLandsIn"] = reader.currentPath ?? "nil"
        result["canGoBackAfterLink"] = reader.canGoBack
        reader.goBack()
        await waitForLoad()
        try? await Task.sleep(for: .milliseconds(500))
        let back = await reader.smokeCurrentPosition()
        result["backTo"] = "\(reader.currentPath ?? "nil") \(back?.fraction ?? -1) (left at \(before?.fraction ?? -1))"
        if reader.currentPath != book.spine[from].path { failures.append("history: back to the chapter") }
        if let before, let back, abs(before.fraction - back.fraction) > 0.02 { failures.append("history: back to the exact place") }
        reader.goForward()
        await waitForLoad()
        result["forwardTo"] = reader.currentPath ?? "nil"
        if reader.currentPath != book.spine[to].path { failures.append("history: forward") }

        // An anchor in the same chapter (a same-document navigation).
        reader.goBack()
        await waitForLoad()
        try? await Task.sleep(for: .milliseconds(500))
        let anchorFrom = await reader.smokeCurrentPosition()
        await click(href: "#aomidori-smoke-target", addingTargetAtEnd: true)
        try? await Task.sleep(for: .milliseconds(700))
        let atAnchor = await reader.smokeCurrentPosition()
        result["canGoBackAfterAnchor"] = reader.canGoBack
        reader.goBack()
        try? await Task.sleep(for: .milliseconds(900))
        let anchorBack = await reader.smokeCurrentPosition()
        result["anchor"] = "from \(anchorFrom?.fraction ?? -1) to \(atAnchor?.fraction ?? -1) back \(anchorBack?.fraction ?? -1)"
        if let anchorFrom, let anchorBack, abs(anchorFrom.fraction - anchorBack.fraction) > 0.02 {
            failures.append("history: back from an anchor in the same chapter")
        }

        // A link that asks for a new window (`target="_blank"`) opens here, and Back returns.
        reader.showSpineItem(at: from, landing: .top)
        await waitForLoad()
        await click(href: book.spine[to].path, addingTargetAtEnd: false, newWindow: true)
        await waitForLoad()
        try? await Task.sleep(for: .milliseconds(400))
        result["newWindowLinkLandsIn"] = reader.currentPath ?? "nil"
        if reader.currentPath != book.spine[to].path { failures.append("history: a target=_blank link opens in the reader") }
        reader.goBack()
        await waitForLoad()
        if reader.currentPath != book.spine[from].path { failures.append("history: back from a target=_blank link") }
        report["history"] = result
    }

    /// Choices to render: a light face (bold must come out at 600), a condensed face, a feature,
    /// an italic face, and a variable font's named instance.
    private static func fontChoices() -> [(String, CustomFontChoice)] {
        let faces = ["HelveticaNeue-Light", "HelveticaNeue-CondensedBold", "Georgia-Italic", "Skia-Regular_Light"]
        var choices: [(String, CustomFontChoice)] = faces.compactMap { name in
            NSFont(name: name, size: 16).map { (name, FontChoiceConversion.choice(from: $0).choice) }
        }
        choices.append(("Georgia+smcp", CustomFontChoice(family: "Georgia", features: ["smcp": 1, "onum": 1])))
        return choices
    }

    /// AppKit fonts as choices: faces, an Apple-style small caps feature, an OpenType feature,
    /// a variable font's axes, and the way back to an AppKit font.
    private func fontConversions() -> [String: Any] {
        var result: [String: Any] = [:]
        func describe(_ choice: CustomFontChoice) -> String {
            String(decoding: choice.record(), as: UTF8.self) + " bold=\(choice.boldWeight.map(CustomFontCSS.number) ?? "-")"
        }
        for name in ["HelveticaNeue-Light", "HelveticaNeue-CondensedBold", "AvenirNext-DemiBoldItalic", "Skia-Regular"] {
            guard let font = NSFont(name: name, size: 16) else { result[name] = "missing"; continue }
            result[name] = describe(FontChoiceConversion.choice(from: font).choice)
        }
        // Baskerville has small caps: macOS drops a feature the face lacks, so a font made with
        // one keeps no settings at all. Hoefler Text, used here until 0.60, has none on macOS 27,
        // and this check failed for that reason alone, not because of the conversion.
        if let font = NSFont(name: "Baskerville", size: 16) {
            let apple = font.fontDescriptor.addingAttributes([.featureSettings: [[
                NSFontDescriptor.FeatureKey.typeIdentifier: kLowerCaseType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kLowerCaseSmallCapsSelector,
            ]]])
            let openType = font.fontDescriptor.addingAttributes([.featureSettings: [[
                kCTFontOpenTypeFeatureTag as String: "onum", kCTFontOpenTypeFeatureValue as String: 1,
            ] as [String: Any]]])
            for (name, descriptor) in [("appleSmallCaps", apple), ("openTypeOnum", openType)] {
                let made = NSFont(descriptor: descriptor, size: 16) ?? font
                let converted = FontChoiceConversion.choice(from: made)
                result[name] = describe(converted.choice) + " unknown=\(converted.unknownFeatures)"
                result[name + "Raw"] = "descriptor=\(made.fontDescriptor.object(forKey: .featureSettings).map { "\($0)" } ?? "nil")"
                    + " coreText=\(CTFontCopyFeatureSettings(made as CTFont).map { "\($0)" } ?? "nil")"
            }
            let expected = ["smcp": 1]
            if FontChoiceConversion.choice(from: NSFont(descriptor: apple, size: 16) ?? font).choice.features != expected {
                failures.append("Apple small caps feature")
            }
        }
        if let light = NSFont(name: "HelveticaNeue-Light", size: 16) {
            let choice = FontChoiceConversion.choice(from: light).choice
            if choice.weight.map({ abs($0 - 300) > 30 }) ?? true || choice.boldWeight.map({ abs($0 - 600) > 30 }) ?? true {
                failures.append("Helvetica Neue Light weights")
            }
        }
        result["SkiaFaces"] = ReaderEnvironment.shared.fonts.faces(forFamily: "Skia").map { face in
            "\(face.postScriptName ?? "-") \(face.url ?? "-") w=\(face.weightRange.map { "\($0)" } ?? "\(face.weight)")"
                + " s=\(face.stretchRange.map { "\($0)" } ?? "\(face.stretch)") i=\(face.italic)"
        }
        let skia = Dictionary(ReaderEnvironment.shared.fonts.faces(forFamily: "Skia").compactMap { face in
            face.postScriptName.map { ($0, face.stretch) }
        }, uniquingKeysWith: { first, _ in first })
        if let extended = skia["Skia-Regular_Extended"], let condensed = skia["Skia-Regular_Condensed"],
           !(extended > 100 && condensed < 100) {
            failures.append("Skia widths")
        }
        result["SkiaAxes"] = CustomFonts.variationAxes(ofFace: "Skia-Regular").map { "\($0.tag) \($0.name) \($0.range) \($0.defaultValue)" }
        // The system font has CSS-scale axes: a weight between named instances survives the round trip.
        let system = NSFont.systemFont(ofSize: 16)
        result["systemAxes"] = CustomFonts.variationAxes(of: system as CTFont).map { "\($0.tag) \($0.range) \($0.defaultValue)" }
        var roundTrip = FontChoiceConversion.choice(from: system).choice
        roundTrip.weight = 550
        let back = FontChoiceConversion.font(for: roundTrip, size: 16).map { FontChoiceConversion.choice(from: $0).choice }
        result["systemRoundTrip"] = back.map(describe) ?? "nil"
        if back?.variations["opsz"] != nil || back.map({ abs(($0.weight ?? 0) - 550) > 1 }) ?? true {
            failures.append("system font round trip")
        }
        return result
    }

    /// The custom font as the page computes it: on plain text, on bold and on italic text, and
    /// the faces the page has loaded.
    private func measureFont() async -> [String: Any] {
        guard let reader else { return [:] }
        let script = """
        const describe = (el) => {
          if (!el) return null;
          const s = getComputedStyle(el);
          return [el.localName, s.fontFamily.slice(0, 60), s.fontWeight, s.fontStyle, s.fontStretch,
                  s.fontFeatureSettings, s.fontVariationSettings].join(' | ');
        };
        const text = [...document.querySelectorAll('p')].find((p) => p.textContent.trim().length > 40);
        return JSON.stringify({
          text: describe(text),
          bold: describe(document.querySelector('[data-aomidori-bold]')),
          italic: describe(document.querySelector('[data-aomidori-italic]')),
          loadedFaces: [...document.fonts].filter((f) => f.status === 'loaded')
            .map((f) => [f.family, f.weight, f.style, f.stretch].join(' ')),
          failedFaces: [...document.fonts].filter((f) => f.status === 'error').length });
        """
        let value = try? await reader.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard let text = value as? String, let data = text.data(using: .utf8),
              let entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ["error": "no measurement"] }
        return entry
    }

    private func finish(window: NSWindow, originalFrame: NSRect) {
        window.setFrame(originalFrame, display: true)
        report["failures"] = failures
        report["finished"] = true
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: folder.appendingPathComponent("report.json"))
        }
        log("finished")
    }

    /// Where the picture sits in the page's visible area, in CSS pixels, plus the native view's
    /// size and toolbar inset, to tell whether `100vh` is the area below the toolbar.
    private func measureCover() async -> [String: Any] {
        guard let reader else { return [:] }
        let script = """
        const el = document.querySelector('[data-aomidori-cover]');
        const target = el && el.localName === 'svg' ? (el.querySelector('image') || el) : el;
        const b = target ? target.getBoundingClientRect() : null;
        return JSON.stringify({
          imagePage: document.documentElement.classList.contains('aomidori-image-page'),
          rect: b ? [b.left, b.top, b.right, b.bottom] : null,
          inner: [innerWidth, innerHeight], scrollY, scrollHeight: document.documentElement.scrollHeight });
        """
        let value = try? await reader.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .defaultClient)
        guard let text = value as? String, let data = text.data(using: .utf8),
              var entry = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return ["error": "no measurement"] }
        let inset = reader.webView.obscuredContentInsets.top
        entry["webView"] = [reader.webView.bounds.width, reader.webView.bounds.height]
        entry["toolbarInset"] = inset
        if let rect = entry["rect"] as? [Double], let inner = entry["inner"] as? [Double], rect.count == 4, inner.count == 2 {
            let left = rect[0], top = rect[1], right = inner[0] - rect[2], bottom = inner[1] - rect[3]
            entry["margins"] = [left, top, right, bottom].map { ($0 * 10).rounded() / 10 }
            let fits = min(left, top, right, bottom) >= -0.5
            entry["centred"] = abs(left - right) < 1.5 && abs(top - bottom) < 1.5 && fits && (entry["scrollY"] as? Double ?? 0) == 0
        }
        return entry
    }

    /// Posts a key-down through the application's event queue, so it takes the same route as
    /// a real key press (the app's local monitor, then the window).
    private func postKey(_ keyCode: UInt16, in window: NSWindow) -> Bool {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: " ",
                                           charactersIgnoringModifiers: " ", isARepeat: false, keyCode: keyCode) else { return false }
        NSApp.postEvent(event, atStart: false)
        return true
    }

    private func waitForLoad() async {
        try? await Task.sleep(for: .milliseconds(400))
        for _ in 0..<50 where reader?.webView.isLoading == true {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func checkInspector() async {
        guard let windowController, let reader else { return }
        windowController.showInspector(nil)
        try? await Task.sleep(for: .milliseconds(600))
        guard let info = windowController.smokeInspectorWindow, let content = info.contentView,
              let tabs = info.contentViewController as? NSTabViewController else {
            failures.append("inspector opens")
            return
        }
        let expected = L10n.format("inspector.title",
                                   BookTitle.display(title: reader.book.title, fileURL: (windowController.document as? NSDocument)?.fileURL) ?? "")
        report["inspectorTitle"] = info.title
        if info.title != expected { failures.append("inspector title") }
        content.layoutSubtreeIfNeeded()
        // Distance from the top of the window's content to the top of the metadata grid: the
        // tabs and a margin, not half the window.
        if let grid = Self.firstSubview(of: NSGridView.self, in: content) {
            let frame = grid.convert(grid.bounds, to: content)
            let gap = content.isFlipped ? frame.minY : content.bounds.maxY - frame.maxY
            report["inspectorGridTop"] = gap
            if gap > 110 { failures.append("inspector metadata from the top") }
        } else {
            failures.append("inspector metadata grid")
        }
        snapshotFrame(of: info, name: "inspector-metadata.png")
        tabs.selectedTabViewItemIndex = 1
        try? await Task.sleep(for: .milliseconds(300))
        content.layoutSubtreeIfNeeded()
        snapshotFrame(of: info, name: "inspector-cover.png")
        info.close()
    }

    private static func firstSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        for subview in view.subviews {
            if let match = subview as? T ?? firstSubview(of: type, in: subview) { return match }
        }
        return nil
    }

    private func snapshotFrame(of window: NSWindow, name: String) {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        write(rep.cgImage, name: name)
    }

    private func snapshot(_ name: String) async {
        guard let image = try? await reader?.webView.takeSnapshot(configuration: nil) else { return }
        write(image.cgImage(forProposedRect: nil, context: nil, hints: nil), name: "\(name).png")
    }

    private func snapshotWindow(_ name: String) async {
        await snapshot(name)
        guard let frameView = windowController?.window?.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        write(rep.cgImage, name: "\(name).window.png")
    }

    private func write(_ image: CGImage?, name: String) {
        guard let image else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
    }

    private func log(_ message: String) {
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
}
