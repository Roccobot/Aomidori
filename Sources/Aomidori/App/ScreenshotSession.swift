import AppKit

/// The download page's screenshots, from `scripts/screenshots.sh`, enabled by the launch argument
/// `-AomidoriScreenshot <folder>`. The app starts with factory settings and its own support
/// folder (see `AppPaths.smokeFolder`), in the theme of `-AomidoriScreenshotTheme light|dark`
/// without touching macOS's, opens the book at the spine item `-AomidoriScreenshotSpine <n>` in a
/// window of a fixed size with the table of contents shown, and writes `window.txt` with the
/// window number once the page is laid out; the script captures that window.
/// Author: Rocco Casadei, a.k.a. Roccobot
@MainActor
enum ScreenshotSession {
    nonisolated static let defaultsKey = "AomidoriScreenshot"
    static let themeKey = "AomidoriScreenshotTheme"
    static let spineKey = "AomidoriScreenshotSpine"
    /// 800 x 560 points: 1600 pixels wide on a Retina screen, as the page expects.
    static let contentSize = NSSize(width: 800, height: 560)

    static var isActive: Bool { UserDefaults.standard.string(forKey: defaultsKey) != nil }

    /// At launch, before any window: the theme the screenshot asks for.
    static func applyTheme() {
        guard isActive, let theme = UserDefaults.standard.string(forKey: themeKey) else { return }
        NSApp.appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
    }

    /// Once the reader window exists: its size, the contents pane, the chapter, then the signal.
    static func prepare(_ controller: ReaderWindowController) {
        guard isActive, let folder = AppPaths.smokeFolder, let window = controller.window else { return }
        window.setContentSize(contentSize)
        window.center()
        controller.showContentsForScreenshot()
        let spine = UserDefaults.standard.integer(forKey: spineKey)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            if spine > 0, spine < controller.reader.book.spine.count {
                controller.reader.showSpineItem(at: spine, landing: .top)
            }
            try? await Task.sleep(for: .seconds(2))
            // The size again, last: AppKit may have restored another frame after the first one.
            window.setContentSize(contentSize)
            window.center()
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(for: .milliseconds(800))
            try? "\(window.windowNumber)".write(to: folder.appendingPathComponent("window.txt"), atomically: true, encoding: .utf8)
        }
    }
}
