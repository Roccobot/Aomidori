import Foundation

/// Locations of the reader's user data. Everything lives in one folder that can be opened,
/// backed up or edited with any application.
enum AppPaths {
    /// `~/Library/Application Support/Aomidori`
    static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Aomidori", isDirectory: true)

    /// User style sheets, listed in the Style menu.
    static let styles = support.appendingPathComponent("Styles", isDirectory: true)
    /// Font files that user styles can reference as `url("../Fonts/<file>")`.
    static let fonts = support.appendingPathComponent("Fonts", isDirectory: true)
    /// Last reading position of every book.
    static let positions = support.appendingPathComponent("Positions.json")
    /// Bookmarks and other per-book state.
    static let books = support.appendingPathComponent("Books.json")

    /// The style shipped inside the app bundle and installed on first launch.
    static let bundledStyleName = "ReadingRoccobot.css"
    static var bundledStyle: URL? {
        Bundle.main.url(forResource: (bundledStyleName as NSString).deletingPathExtension, withExtension: "css")
    }
}
