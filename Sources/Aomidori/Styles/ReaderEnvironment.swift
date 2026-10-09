import AppKit
import EPUBKit
import AomidoriCore

extension Notification.Name {
    /// Posted on the main thread whenever a reading setting or the styles folder changes.
    static let readerEnvironmentDidChange = Notification.Name("AomidoriReaderEnvironmentDidChange")
}

/// App-wide reading settings and the user styles folder. Every reader window renders from it.
@MainActor
final class ReaderEnvironment {
    static let shared = ReaderEnvironment()

    private enum Key {
        static let defaultStyle = "AomidoriDefaultStyle"
        static let selectedStyle = "AomidoriSelectedStyle"
        static let overrideEnabled = "AomidoriOverrideEnabled"
        static let textScale = "AomidoriTextScale"
        static let night = "AomidoriNight"
        static let minimal = "AomidoriMinimal"
    }

    private let defaults = UserDefaults.standard
    let library = StyleLibrary(directory: AppPaths.styles)
    let positions = ReadingPositionStore(fileURL: AppPaths.positions)
    let books = BookStateStore(fileURL: AppPaths.books)

    private(set) var styles: [StyleFile] = []
    private(set) var nightPaletteCSS = ""
    private var colorSchemeCache: [String: Bool] = [:]
    private var watcher: DirectoryWatcher?
    private var appearanceObservation: NSKeyValueObservation?
    private var stateSaveTask: Task<Void, Never>?

    private init() {}

    /// Prepares the folders, installs the bundled style if missing and starts watching for edits.
    func start() {
        do {
            try library.prepare(installing: AppPaths.bundledStyle, as: AppPaths.bundledStyleName)
            try FileManager.default.createDirectory(at: AppPaths.fonts, withIntermediateDirectories: true)
        } catch {
            NSLog("Aomidori: cannot prepare %@: %@", AppPaths.support.path, error.localizedDescription)
        }
        reloadStyles(notify: false)
        watcher = DirectoryWatcher(url: AppPaths.styles) { [weak self] in self?.reloadStyles(notify: true) }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.nightOverride == nil else { return }
                self.notify()
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

    /// `true`/`false` when the reader chose Night/Day, `nil` to follow the system.
    private var nightOverride: Bool? {
        defaults.object(forKey: Key.night) as? Bool
    }

    var isNight: Bool {
        nightOverride ?? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
    }

    /// The appearance reader windows use; `nil` follows the system.
    var windowAppearance: NSAppearance? {
        nightOverride.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
    }

    func toggleNight() {
        defaults.set(!isNight, forKey: Key.night)
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

    // MARK: Rendering

    func configuration() -> ReaderConfiguration {
        let style = activeStyle
        return ReaderConfiguration(
            overrideEnabled: overrideEnabled,
            styleHref: style.map(Self.href(for:)),
            styleHandlesColorScheme: style.map(handlesColorScheme) ?? false,
            night: isNight,
            nightPaletteCSS: nightPaletteCSS,
            scale: textScale
        )
    }

    /// Origin-relative URL of a style; the modification time busts the web view's cache.
    private static func href(for style: StyleFile) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        let name = style.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? style.name
        let version = Int((style.modificationDate?.timeIntervalSince1970 ?? 0) * 1000)
        return "/\(PageSchemeHandler.userPrefix)Styles/\(name)?v=\(version)"
    }

    // MARK: Per-book state

    /// Saves reading positions and book state (bookmarks, sidebar pane) after a short pause,
    /// coalescing bursts of changes such as scrolling.
    func saveStateSoon() {
        stateSaveTask?.cancel()
        stateSaveTask = Task { [positions, books] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            try? positions.save()
            try? books.save()
        }
    }

    func saveStateNow() {
        stateSaveTask?.cancel()
        try? positions.save()
        try? books.save()
    }

    private func notify() {
        NotificationCenter.default.post(name: .readerEnvironmentDidChange, object: self)
    }
}
