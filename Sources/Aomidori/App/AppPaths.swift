import Foundation

/// Locations of the reader's user data. Everything lives in one folder that can be opened,
/// backed up or edited with any application.
enum AppPaths {
    /// `~/Library/Application Support/Aomidori`; in a scripted smoke session, `Support` inside the
    /// session's folder, so no session ever writes to the user's styles, fonts or places.
    static let support: URL = smokeFolder?.appendingPathComponent("Support", isDirectory: true)
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aomidori", isDirectory: true)

    /// The output folder of a scripted session (`-AomidoriReaderSmoke <folder>`,
    /// `-AomidoriLaunchSmoke <folder>`, `-AomidoriPlaygroundSmoke <folder>`,
    /// `-AomidoriScreenshot <folder>`), if this is one.
    static let smokeFolder: URL? = [ReaderSmokeTest.defaultsKey, LaunchSmokeTest.defaultsKey,
                                    PlaygroundSmokeTest.defaultsKey, ScreenshotSession.defaultsKey]
        .lazy.compactMap { UserDefaults.standard.string(forKey: $0) }.first
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        // `scripts/smoke.sh` names a snapshot file: its folder is the session's.
        ?? UserDefaults.standard.string(forKey: ReaderViewController.snapshotDefaultsKey)
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent() }

    /// User style sheets, listed in the Style menu.
    static let styles = support.appendingPathComponent("Styles", isDirectory: true)
    /// Font files that user styles can reference as `url("../Fonts/<file>")`.
    static let fonts = support.appendingPathComponent("Fonts", isDirectory: true)
    /// Last reading position of every book.
    static let positions = stateFolder.appendingPathComponent("Positions.json")
    /// Bookmarks and other per-book state.
    static let books = stateFolder.appendingPathComponent("Books.json")
    /// A smoke session keeps its reading state at the top of its folder, next to its report.
    private static let stateFolder: URL = smokeFolder ?? support

    /// The style shipped inside the app bundle and installed on first launch.
    static let bundledStyleName = "ReadingRoccobot.css"
    static var bundledStyle: URL? {
        Bundle.main.url(forResource: (bundledStyleName as NSString).deletingPathExtension, withExtension: "css")
    }
}
