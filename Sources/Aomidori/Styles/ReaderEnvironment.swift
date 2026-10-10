import AppKit
import EPUBKit
import AomidoriCore

extension Notification.Name {
    /// Posted on the main thread whenever a reading setting or the styles folder changes.
    static let readerEnvironmentDidChange = Notification.Name("AomidoriReaderEnvironmentDidChange")
    /// A book's bookmarks changed in one of its views; `userInfo["bookKey"]` names the book.
    static let readerBookStateDidChange = Notification.Name("AomidoriReaderBookStateDidChange")
}

/// App-wide reading settings and the user styles folder. Every reader window renders from it.
@MainActor
final class ReaderEnvironment {
    static let shared = ReaderEnvironment()

    private enum Key {
        static let defaultStyle = "AomidoriDefaultStyle"
        static let selectedStyle = "AomidoriSelectedStyle"
        static let overrideEnabled = "AomidoriOverrideEnabled"
        static let justified = "AomidoriJustified"
        static let blendsInk = "AomidoriBlendsInk"
        static let textScale = "AomidoriTextScale"
        /// The light/dark override since 0.53 (`AppearanceChoice`): `true` dark, `false` light,
        /// absent to follow macOS.
        static let appearanceOverride = "AomidoriAppearanceOverride"
        /// Up to 0.52: a Night/Day choice that, once made, never followed macOS again. Removed
        /// at launch, so every reader starts 0.53 following the system.
        static let legacyNight = "AomidoriNight"
        static let minimal = "AomidoriMinimal"
        /// Settings › Features (0.90).
        static let linksInNewTabs = "AomidoriOpenLinksInNewTabs"
        static let linksNextToSource = "AomidoriOpenLinksNextToSource"
        static let customFontEnabled = "AomidoriCustomFontEnabled"
        /// The family alone; still written so earlier versions keep the family on a downgrade.
        static let customFontFamily = "AomidoriCustomFontFamily"
        /// The whole choice (`CustomFontChoice`) as JSON, since 0.4.0.
        static let customFont = "AomidoriCustomFont"
    }

    /// The reader's settings. A scripted session (smoke test or screenshots) shares the bundle
    /// identifier of the installed app: it gets its own settings, emptied at every start, so it
    /// begins from the factory values and never writes the user's.
    private let defaults: UserDefaults = {
        guard AppPaths.smokeFolder != nil, let session = UserDefaults(suiteName: ReaderEnvironment.sessionSuite) else { return .standard }
        session.removePersistentDomain(forName: ReaderEnvironment.sessionSuite)
        return session
    }()
    nonisolated static let sessionSuite = "com.roccobot.aomidori.session"
    let library = StyleLibrary(directory: AppPaths.styles)
    let positions = ReadingPositionStore(fileURL: AppPaths.positions)
    let books = BookStateStore(fileURL: AppPaths.books)

    private(set) var styles: [StyleFile] = []
    private(set) var nightPaletteCSS = ""
    private var colorSchemeCache: [String: Bool] = [:]
    let fonts = CustomFonts()
    private var watcher: DirectoryWatcher?
    private var fontsWatcher: DirectoryWatcher?
    /// Bumped by every change in the styles folder and by Reload Style: part of the style's URL,
    /// so the page fetches the file again even when an `@import`ed file is what changed.
    private var styleRevision = 0
    private var fontCache: (family: String, css: String)?
    private var appearanceObservation: NSKeyValueObservation?
    private var stateSaveTask: Task<Void, Never>?

    private init() {}

    /// Prepares the folders, installs the bundled style if missing and starts watching for edits.
    func start() {
        defaults.removeObject(forKey: Key.legacyNight)
        do {
            try library.prepare(installing: AppPaths.bundledStyle, as: AppPaths.bundledStyleName)
            try FileManager.default.createDirectory(at: AppPaths.fonts, withIntermediateDirectories: true)
        } catch {
            NSLog("Aomidori: cannot prepare %@: %@", AppPaths.support.path, error.localizedDescription)
        }
        reloadStyles(notify: false)
        fonts.rescan()
        // Editors save in place or atomically (write a temporary file, then rename it over the
        // original): both show up as file events in the folder, coalesced over 0.1 s.
        watcher = DirectoryWatcher(url: AppPaths.styles, latency: 0.1) { [weak self] in
            self?.styleRevision += 1
            self?.reloadStyles(notify: true)
        }
        fontsWatcher = DirectoryWatcher(url: AppPaths.fonts, latency: 0.3) { [weak self] in self?.reloadFonts() }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // macOS now shows what the reader had picked: follow it again from here.
                let override = self.nightOverride
                self.setNightOverride(AppearanceChoice.reconciled(override, systemIsDark: self.systemIsDark))
                if override == nil || self.nightOverride == nil { self.notify() }
            }
        }
    }

    // MARK: Styles

    /// The style named in the `AomidoriDefaultStyle` setting (`ReadingRoccobot.css` unless changed).
    var defaultStyleName: String {
        defaults.string(forKey: Key.defaultStyle) ?? AppPaths.bundledStyleName
    }

    /// The style applied when overriding: the selected one, else the default, else the first.
    var activeStyle: StyleFile? {
        let selected = selectedStyleName
        return styles.first { $0.name == selected }
            ?? styles.first { $0.name == defaultStyleName }
            ?? styles.first
    }

    var overrideEnabled: Bool { defaults.bool(forKey: Key.overrideEnabled) }

    /// The explicitly selected style name, which may no longer exist in the folder.
    var selectedStyleName: String? { defaults.string(forKey: Key.selectedStyle) }

    /// Selects a style. Choosing a style always turns the override on.
    func selectStyle(named name: String) {
        defaults.set(name, forKey: Key.selectedStyle)
        defaults.set(true, forKey: Key.overrideEnabled)
        notify()
    }

    /// Restores a previous selection exactly (used when a style preview is cancelled).
    func restoreStyle(named name: String?, overrideEnabled: Bool) {
        defaults.set(name, forKey: Key.selectedStyle)
        defaults.set(overrideEnabled, forKey: Key.overrideEnabled)
        notify()
    }

    func cycleStyle(by offset: Int) {
        guard let style = StyleCycle.style(from: activeStyle?.name, offset: offset, in: styles) else { return }
        selectStyle(named: style.name)
    }

    func toggleOverride() {
        defaults.set(!overrideEnabled, forKey: Key.overrideEnabled)
        notify()
    }

    /// Running text justified instead of flush left (the default), in every window.
    var justified: Bool { defaults.bool(forKey: Key.justified) }

    func toggleJustified() {
        defaults.set(!justified, forKey: Key.justified)
        notify()
    }

    /// Black-and-white illustrations blended into the page (on by default), in every window.
    var blendsInk: Bool { defaults.object(forKey: Key.blendsInk) as? Bool ?? true }

    func toggleBlendsInk() {
        defaults.set(!blendsInk, forKey: Key.blendsInk)
        notify()
    }

    /// Reads the styles and fonts folders again and re-applies the active style everywhere,
    /// keeping each window's reading position.
    func reloadStyle() {
        styleRevision += 1
        fonts.rescan()
        fontCache = nil
        reloadStyles(notify: true)
    }

    private func reloadStyles(notify shouldNotify: Bool) {
        styles = library.styles()
        colorSchemeCache.removeAll()
        // The Night fallback palette comes from the default style, as edited in the folder.
        let paletteSource = styles.first { $0.name == defaultStyleName }.flatMap(library.contents(of:))
            ?? AppPaths.bundledStyle.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? ""
        nightPaletteCSS = NightPalette.css(fromDarkRulesOf: paletteSource)
        if shouldNotify { notify() }
    }

    private func handlesColorScheme(_ style: StyleFile) -> Bool {
        if let cached = colorSchemeCache[style.name] { return cached }
        let handles = library.handlesColorScheme(style)
        colorSchemeCache[style.name] = handles
        return handles
    }

    // MARK: Appearance and size

    /// `true`/`false` when the reader picked dark/light against the system, `nil` to follow it.
    private var nightOverride: Bool? {
        defaults.object(forKey: Key.appearanceOverride) as? Bool
    }

    private func setNightOverride(_ override: Bool?) {
        if let override { defaults.set(override, forKey: Key.appearanceOverride) }
        else { defaults.removeObject(forKey: Key.appearanceOverride) }
    }

    /// The system's appearance. The app sets no appearance of its own (windows do), so the
    /// application's effective appearance is the system's.
    private var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    var isNight: Bool {
        AppearanceChoice.isDark(override: nightOverride, systemIsDark: systemIsDark)
    }

    /// The appearance reader windows use; `nil` follows the system.
    var windowAppearance: NSAppearance? {
        nightOverride.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
    }

    /// `⇧⌘N` and the toolbar's sun: the other appearance; back to following macOS when that
    /// is the system's.
    func toggleNight() {
        setNightOverride(AppearanceChoice.override(afterSwapping: nightOverride, systemIsDark: systemIsDark))
        notify()
    }

    var textScale: Double {
        let stored = defaults.double(forKey: Key.textScale)
        return stored == 0 ? TextScale.normal : TextScale.sanitized(stored)
    }

    func setTextScale(_ scale: Double) {
        defaults.set(TextScale.sanitized(scale), forKey: Key.textScale)
        notify()
    }

    /// Whether new windows open in minimal mode (the last choice made).
    var prefersMinimal: Bool {
        get { defaults.bool(forKey: Key.minimal) }
        set { defaults.set(newValue, forKey: Key.minimal) }
    }

    // MARK: Settings › Features

    /// "Open links in new tabs" (off by default).
    var opensLinksInNewTabs: Bool {
        get { defaults.bool(forKey: Key.linksInNewTabs) }
        set { defaults.set(newValue, forKey: Key.linksInNewTabs) }
    }

    /// "Open each link next to its source tab" (on by default), for every new tab.
    var opensLinksNextToSource: Bool {
        get { defaults.object(forKey: Key.linksNextToSource) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.linksNextToSource) }
    }

    var linkTabPlacement: LinkOpening.Placement {
        LinkOpening.placement(nextToSourceSetting: opensLinksNextToSource)
    }

    // MARK: Custom font

    var customFontEnabled: Bool { defaults.bool(forKey: Key.customFontEnabled) && customFontChoice != nil }

    /// The chosen font, kept when the custom font is turned off. Preferences from before 0.4.0
    /// (a family name only) read as that family with the style's own weights.
    var customFontChoice: CustomFontChoice? {
        CustomFontChoice.stored(record: defaults.data(forKey: Key.customFont), legacyFamily: defaults.string(forKey: Key.customFontFamily))
    }

    var customFontFamily: String? { customFontChoice?.family }

    /// Turns the custom font on or off. Returns `false` if no family was chosen yet.
    @discardableResult
    func toggleCustomFont() -> Bool {
        guard customFontFamily != nil else { return false }
        defaults.set(!customFontEnabled, forKey: Key.customFontEnabled)
        notify()
        return true
    }

    /// Chooses a family with the style's own weights and turns the custom font on.
    func setCustomFont(family: String) {
        setCustomFont(CustomFontChoice(family: family))
    }

    /// Chooses the custom font (family, face, weight, width, axes, features) and turns it on.
    func setCustomFont(_ choice: CustomFontChoice) {
        guard choice != customFontChoice || !customFontEnabled else { return }
        defaults.set(choice.record(), forKey: Key.customFont)
        defaults.set(choice.family, forKey: Key.customFontFamily)
        defaults.set(true, forKey: Key.customFontEnabled)
        notify()
    }

    func setCustomFontEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.customFontEnabled)
        notify()
    }

    /// Copies font files into the fonts folder; returns the families they contain.
    func installFonts(_ urls: [URL]) throws -> [String] {
        let families = try fonts.install(urls)
        fontCache = nil
        notify()
        return families
    }

    private func reloadFonts() {
        fonts.rescan()
        fontCache = nil
        notify()
    }

    private func fontFaceCSS(for family: String) -> String {
        if let fontCache, fontCache.family == family { return fontCache.css }
        let css = CustomFontCSS.fontFaceCSS(fonts.faces(forFamily: family))
        fontCache = (family, css)
        return css
    }

    // MARK: Rendering

    func configuration() -> ReaderConfiguration {
        configuration(customFont: customFontEnabled ? customFontChoice : nil)
    }

    /// The configuration with a given custom font (or none), whatever is saved.
    func configuration(customFont choice: CustomFontChoice?) -> ReaderConfiguration {
        let style = activeStyle
        var configuration = ReaderConfiguration(
            overrideEnabled: overrideEnabled,
            styleHref: style.map { Self.href(for: $0, revision: styleRevision) },
            styleHandlesColorScheme: style.map(handlesColorScheme) ?? false,
            night: isNight,
            nightPaletteCSS: nightPaletteCSS,
            scale: textScale,
            justified: justified,
            blendsInk: blendsInk
        )
        configuration.setCustomFont(choice, faceCSS: choice.map { fontFaceCSS(for: $0.family) } ?? "")
        return configuration
    }

    /// Origin-relative URL of a style; the modification time and the revision bust the web view's cache.
    private static func href(for style: StyleFile, revision: Int) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        let name = style.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? style.name
        let version = Int((style.modificationDate?.timeIntervalSince1970 ?? 0) * 1000)
        return "/\(PageSchemeHandler.userPrefix)Styles/\(name)?v=\(version)-\(revision)"
    }

    // MARK: Per-book state

    /// Saves reading positions and book state (bookmarks, sidebar pane) after a short pause,
    /// coalescing bursts of changes such as scrolling.
    func saveStateSoon() {
        stateSaveTask?.cancel()
        stateSaveTask = Task { [positions, books] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            Self.save(positions, books)
        }
    }

    func saveStateNow() {
        stateSaveTask?.cancel()
        Self.save(positions, books)
    }

    /// A failed write is logged; the stores keep the changes and the next save retries them.
    private nonisolated static func save(_ positions: ReadingPositionStore, _ books: BookStateStore) {
        for (name, save) in [("positions", positions.save), ("bookmarks", books.save)] {
            do {
                try save()
            } catch {
                NSLog("Aomidori: cannot save %@: %@", name, error.localizedDescription)
            }
        }
    }

    private func notify() {
        NotificationCenter.default.post(name: .readerEnvironmentDidChange, object: self)
    }
}
