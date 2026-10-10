import AppKit
import Carbon
import Sparkle

/// A scripted session for `scripts/smoke-launch.sh`, enabled by the launch argument
/// `-AomidoriLaunchSmoke <folder>` (with `-AomidoriLaunchSmokeBook <epub>`). The app is
/// launched with no book: it checks that the empty window is shown (drop zone, recent books,
/// minimum size), that the drop target accepts only EPUB files, that a book opened from it
/// takes its place (frame included), that `⌘T` adds an empty tab listing that book first, and
/// that the Dock's reopen event brings the empty window back once the book is closed. It also
/// checks that Sparkle is loaded from the app's own Frameworks folder and that the app menu has
/// "Check for Updates…" (the updater itself stays off in smoke sessions). Reading state
/// is kept in the folder (see `AppPaths`) and window frames are not remembered meanwhile.
@MainActor
final class LaunchSmokeTest {
    nonisolated static let defaultsKey = "AomidoriLaunchSmoke"
    static var isActive: Bool { UserDefaults.standard.string(forKey: defaultsKey) != nil }

    private let folder: URL
    private let book: URL?
    private var report: [String: Any] = [:]
    private var failures: [String] = []
    private let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical], reason: "Launch smoke test")

    init?() {
        guard let path = UserDefaults.standard.string(forKey: Self.defaultsKey) else { return nil }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        book = UserDefaults.standard.string(forKey: "AomidoriLaunchSmokeBook").map { URL(fileURLWithPath: $0) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { await run() }
    }

    private func run() async {
        try? await Task.sleep(for: .milliseconds(1500))

        checkUpdater()

        // 1. Launch with no book: the empty window, and nothing else.
        report["atLaunch"] = windows()
        report["activeAtLaunch"] = NSApp.isActive
        guard let empty = EmptyReaderWindowController.all.first, let emptyWindow = empty.window, emptyWindow.isVisible else {
            failures.append("no empty window at launch")
            return finish()
        }
        let content = empty.smokeContent
        report["placeholder"] = content.message
        report["emptyToolbar"] = emptyWindow.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
        report["minimumSize"] = NSStringFromSize(emptyWindow.minSize)
        report["dropZoneFromSVG"] = content.smokeRendersSVG
        report["recentsAtLaunch"] = content.recents.count
        report["recentsLimit"] = NSDocumentController.shared.maximumRecentDocumentCount
        report["emptyLayout"] = content.smokeLayout
        checkEmptyLayout(content.smokeLayout, name: "launch size")
        checkAppearance()
        snapshot(emptyWindow, name: "empty.png")
        content.smokeHighlight(true)
        content.display()
        snapshot(emptyWindow, name: "empty-highlighted.png")
        content.smokeHighlight(false)
        // The window's real minimum: AppKit adds the toolbar to the minimum set in code.
        emptyWindow.setFrame(NSRect(origin: emptyWindow.frame.origin, size: emptyWindow.minSize), display: true)
        emptyWindow.layoutIfNeeded()
        snapshot(emptyWindow, name: "empty-minimum.png")
        report["emptyLayoutMinimum"] = content.smokeLayout
        checkEmptyLayout(content.smokeLayout, name: "minimum size")
        let emptyFrame = emptyWindow.frame

        // 2. The drop target takes EPUB files only.
        let pasteboard = NSPasteboard(name: .init("AomidoriLaunchSmoke-\(ProcessInfo.processInfo.processIdentifier)"))
        pasteboard.clearContents()
        let other = folder.appendingPathComponent("progress.log")
        log("drop check")
        pasteboard.writeObjects([(book ?? other) as NSURL, other as NSURL])
        let accepted = EmptyReaderView.epubURLs(on: pasteboard)
        report["dropAccepts"] = accepted.map(\.lastPathComponent)
        if accepted.count != (book == nil ? 0 : 1) { failures.append("drop filter") }
        pasteboard.releaseGlobally()

        // 3. A book opened from the empty window takes its place.
        guard let book else { failures.append("no book given"); return finish() }
        empty.open([book])
        for _ in 0..<40 where readerWindows().isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(800))
        report["afterOpen"] = windows()
        var readers = readerWindows()
        if readers.count != 1 { failures.append("one reader window after opening") }
        // Watched without being held: once the book is closed, nothing may keep its window or
        // its page (web view, archive) alive.
        weak let openedWindow = readers.first
        weak let openedPage = (readers.first?.windowController as? ReaderWindowController)?.reader
        if EmptyReaderWindowController.all.contains(where: { $0 === empty }) || emptyWindow.isVisible { failures.append("empty window replaced") }
        if let reader = readers.first {
            report["frames"] = ["empty": NSStringFromRect(emptyFrame), "reader": NSStringFromRect(reader.frame)]
            if reader.frame != emptyFrame { failures.append("reader takes the empty window's frame") }

            // 4. ⌘T in the reader window: an empty tab beside it, listing the book first.
            reader.windowController?.newWindowForTab(nil)
            try? await Task.sleep(for: .milliseconds(600))
            let tab = EmptyReaderWindowController.all.last
            report["afterNewTab"] = windows()
            report["tabsAfterNewTab"] = reader.tabbedWindows?.count ?? 1
            if reader.tabbedWindows?.count != 2 || tab?.window?.tabGroup !== reader.tabGroup { failures.append("new tab") }
            let firstRecent = tab?.smokeContent.recents.first?.url.standardizedFileURL
            report["firstRecentIsTheBook"] = firstRecent == book.standardizedFileURL
            if firstRecent != book.standardizedFileURL { failures.append("recent books") }
            if let tabWindow = tab?.window { snapshot(tabWindow, name: "empty-tab.png") }
            if let layout = tab?.smokeContent.smokeLayout {
                report["emptyTabLayout"] = layout
                checkEmptyLayout(layout, name: "tab")
                if layout["headerTextX"] == nil { failures.append("empty tab: no recent files heading measured") }
            }
            tab?.close()
            try? await Task.sleep(for: .milliseconds(400))
        }
        readers.removeAll()

        // 5. Book closed, then the Dock's reopen event: the empty window again.
        NSDocumentController.shared.documents.forEach { $0.close() }
        try? await Task.sleep(for: .milliseconds(600))
        report["afterClose"] = windows()
        for _ in 0..<20 where openedWindow != nil || openedPage != nil { try? await Task.sleep(for: .milliseconds(100)) }
        report["closedBookReleased"] = ["window": openedWindow == nil, "page": openedPage == nil]
        if openedWindow != nil || openedPage != nil { failures.append("closed book still in memory") }
        do {
            try sendReopenEvent()
        } catch {
            report["reopenError"] = "\(error)"
        }
        for _ in 0..<30 where EmptyReaderWindowController.all.isEmpty { try? await Task.sleep(for: .milliseconds(100)) }
        try? await Task.sleep(for: .milliseconds(400))
        report["afterReopen"] = windows()
        if EmptyReaderWindowController.all.first?.window?.isVisible != true { failures.append("empty window on reopen") }
        finish()
    }

    /// Sparkle comes from Contents/Frameworks (the rpath works, the embedded copy is the one
    /// in use), the menu item exists, and the updater stayed off because of the smoke session.
    private func checkUpdater() {
        let framework = Bundle(for: SPUUpdater.self).bundleURL.resolvingSymlinksInPath().path
        let embedded = Bundle.main.privateFrameworksURL?.resolvingSymlinksInPath().path ?? "?"
        let menuItem = NSApp.mainMenu?.items.first?.submenu?.items
            .first { $0.action == #selector(AppDelegate.checkForUpdates(_:)) }
        report["updater"] = [
            "framework": framework,
            "sparkleVersion": Bundle(for: SPUUpdater.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            "menuItem": menuItem?.title ?? "",
            "feedURL": Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "",
            "notStarted": Updater.shared.reasonNotStarted ?? "",
        ]
        if !framework.hasPrefix(embedded + "/") { failures.append("Sparkle not loaded from Contents/Frameworks") }
        if menuItem == nil { failures.append("no Check for Updates menu item") }
        if Updater.shared.reasonNotStarted != "smoke test" { failures.append("updater must stay off in smoke sessions") }
    }

    /// The drop zone within half the width and 30% of the height (or at its minimum, Graphe's
    /// 184 × 128), in its proportions; the heading's text exactly over the file names'.
    private func checkEmptyLayout(_ layout: [String: Double], name: String) {
        guard let width = layout["dropZoneWidth"], let height = layout["dropZoneHeight"],
              let contentWidth = layout["contentWidth"], let contentHeight = layout["contentHeight"] else { return }
        let minimum = DropZoneView.minimumSize
        let atMinimum = width <= Double(minimum.width) + 0.5
        if !atMinimum, width > contentWidth * 0.5 + 1 || height > contentHeight * 0.3 + 1 { failures.append("drop zone too large (\(name))") }
        if abs(width / height - Double(minimum.width / minimum.height)) > 0.02 { failures.append("drop zone proportions (\(name))") }
        if let header = layout["headerTextX"], let title = layout["firstTitleTextX"], abs(header - title) > 0.5 {
            failures.append("recent files heading not aligned (\(name)): \(header) vs \(title)")
        }
    }

    /// 0.53 follows macOS: the 0.5x Night/Day key is gone, and with no override set in this
    /// session the reading appearance is the system's.
    private func checkAppearance() {
        let system = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let legacy = UserDefaults.standard.object(forKey: "AomidoriNight")
        let override = UserDefaults.standard.object(forKey: "AomidoriAppearanceOverride")
        report["appearance"] = [
            "systemIsDark": system, "isNight": ReaderEnvironment.shared.isNight,
            "legacyNightKey": legacy.map { "\($0)" } ?? "removed", "override": override.map { "\($0)" } ?? "none",
        ] as [String: Any]
        if legacy != nil { failures.append("0.5x Night key not removed") }
        if override == nil, ReaderEnvironment.shared.isNight != system { failures.append("appearance does not follow macOS") }
    }

    /// The `rapp` Apple event the Dock sends when its icon is clicked, sent to this process.
    private func sendReopenEvent() throws {
        let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
        let event = NSAppleEventDescriptor.appleEvent(
            withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
            targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try event.sendEvent(options: [.noReply], timeout: 5)
    }

    private func readerWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.windowController is ReaderWindowController }
    }

    private func windows() -> [String] {
        NSApp.windows.filter(\.isVisible).map { window in
            "\(window.windowController.map { String(describing: type(of: $0)) } ?? String(describing: type(of: window))) \"\(window.title)\""
        }
    }

    private func finish() {
        report["failures"] = failures
        report["finished"] = true
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? json.write(to: folder.appendingPathComponent("report.json"))
        }
        log("finished")
    }

    private func snapshot(_ window: NSWindow, name: String) {
        guard let frameView = window.contentView?.superview,
              let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name))
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
