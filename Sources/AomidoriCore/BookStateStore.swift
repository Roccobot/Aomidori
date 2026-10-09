import Foundation

/// What the window's sidebar shows. The order is the selector's order, and `⌥⌘1`…`⌥⌘6`
/// follow it, so shortcuts stay stable when the panes that are still missing arrive.
public enum SidebarPane: String, Codable, CaseIterable, Sendable {
    case contents
    case bookmarks
    case thumbnails
    case images
    case search
    case notes

    /// Panes implemented in this version; the others keep their slot and shortcut.
    public var isAvailable: Bool {
        switch self {
        case .contents, .bookmarks, .search: true
        case .thumbnails, .images, .notes: false
        }
    }

    public static var available: [SidebarPane] { allCases.filter(\.isAvailable) }

    /// The digit of the pane's `⌥⌘` shortcut.
    public var shortcutDigit: Int { Self.allCases.firstIndex(of: self)! + 1 }
}

/// A saved place in a book.
public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var spinePath: String
    public var spineIndex: Int
    /// Vertical scroll position in the spine item, 0...1.
    public var fraction: Double
    public var created: Date

    public init(id: UUID = UUID(), title: String, spinePath: String, spineIndex: Int, fraction: Double,
                created: Date = Date()) {
        self.id = id
        self.title = title
        self.spinePath = spinePath
        self.spineIndex = spineIndex
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        self.created = created
    }
}

/// Everything remembered about one book besides the reading position.
public struct BookState: Codable, Equatable, Sendable {
    public var bookmarks: [Bookmark] = []
    public var sidebarPane: SidebarPane?

    public init(bookmarks: [Bookmark] = [], sidebarPane: SidebarPane? = nil) {
        self.bookmarks = bookmarks
        self.sidebarPane = sidebarPane
    }

    /// Bookmarks in reading order.
    public var sortedBookmarks: [Bookmark] {
        bookmarks.sorted { ($0.spineIndex, $0.fraction, $0.created) < ($1.spineIndex, $1.fraction, $1.created) }
    }

    // Unknown panes (from a newer version) decode as nil instead of failing the whole file.
    private enum CodingKeys: String, CodingKey { case bookmarks, sidebarPane }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bookmarks = try container.decodeIfPresent([Bookmark].self, forKey: .bookmarks) ?? []
        sidebarPane = (try? container.decodeIfPresent(String.self, forKey: .sidebarPane)).flatMap(SidebarPane.init(rawValue:))
    }
}

/// Per-book state of every book (bookmarks, last sidebar pane) in one JSON file. Unlike reading
/// positions it is never pruned: bookmarks are the reader's own data.
/// Thread-safe; writes are explicit (`save()`) so callers can coalesce them.
public final class BookStateStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var states: [String: BookState]
    private var isDirty = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        states = data.flatMap { try? Self.decoder.decode([String: BookState].self, from: $0) } ?? [:]
    }

    public func state(forBook key: String) -> BookState {
        lock.withLock { states[key] ?? BookState() }
    }

    /// Changes a book's state in place; empty states are dropped from the file.
    public func update(forBook key: String, _ change: (inout BookState) -> Void) {
        lock.withLock {
            var state = states[key] ?? BookState()
            change(&state)
            let newValue: BookState? = state == BookState() ? nil : state
            guard states[key] != newValue else { return }
            states[key] = newValue
            isDirty = true
        }
    }

    /// Writes the file atomically if anything changed since the last save.
    public func save() throws {
        let snapshot: [String: BookState]? = lock.withLock {
            guard isDirty else { return nil }
            isDirty = false
            return states
        }
        guard let snapshot else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
