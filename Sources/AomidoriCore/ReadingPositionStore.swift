import Foundation

/// A place inside one spine item, robust to text size and style changes: the scroll fraction,
/// plus an element anchor (`"3.0.2@0.25"`: child indices from the body to the element at the
/// reading line, and how far down that element the line was) used first when it still resolves.
public struct ChapterPosition: Codable, Equatable, Sendable {
    /// Vertical scroll position as a fraction of the scrollable height, 0...1.
    public var fraction: Double
    public var anchor: String?

    public init(fraction: Double, anchor: String? = nil) {
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        self.anchor = anchor.flatMap { $0.isEmpty ? nil : $0 }
    }

    public static let top = ChapterPosition(fraction: 0)
}

/// Where the reader left a book, and where they left each chapter of it.
public struct ReadingPosition: Codable, Equatable, Sendable {
    /// Container path of the spine item. Preferred over the index, which shifts if the book changes.
    public var spinePath: String
    public var spineIndex: Int
    /// Vertical scroll position as a fraction of the scrollable height, 0...1.
    public var fraction: Double
    /// Element anchor for the position; see `ChapterPosition`.
    public var anchor: String?
    public var updated: Date
    /// The last position in every chapter visited, keyed by spine item path. Maintained by
    /// `ReadingPositionStore`.
    public var chapters: [String: ChapterPosition]

    public init(spinePath: String, spineIndex: Int, fraction: Double, anchor: String? = nil,
                updated: Date = Date(), chapters: [String: ChapterPosition] = [:]) {
        self.spinePath = spinePath
        self.spineIndex = spineIndex
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        self.anchor = anchor.flatMap { $0.isEmpty ? nil : $0 }
        self.updated = updated
        self.chapters = chapters
    }

    /// The position in the current chapter.
    public var chapterPosition: ChapterPosition { ChapterPosition(fraction: fraction, anchor: anchor) }

    // Files written before 0.3.0 have no anchor and no chapter map.
    private enum CodingKeys: String, CodingKey { case spinePath, spineIndex, fraction, anchor, updated, chapters }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            spinePath: try container.decode(String.self, forKey: .spinePath),
            spineIndex: try container.decode(Int.self, forKey: .spineIndex),
            fraction: try container.decode(Double.self, forKey: .fraction),
            anchor: try container.decodeIfPresent(String.self, forKey: .anchor),
            updated: try container.decode(Date.self, forKey: .updated),
            chapters: (try? container.decodeIfPresent([String: ChapterPosition].self, forKey: .chapters)) ?? [:]
        )
    }
}

/// Reading positions of every book, kept in one small JSON file.
/// Thread-safe; writes are explicit (`save()`) so callers can coalesce them.
public final class ReadingPositionStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()
    private var positions: [String: ReadingPosition]
    private var isDirty = false

    /// Positions beyond this count are pruned, oldest first.
    public static let capacity = 500

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? Data(contentsOf: fileURL)
        positions = data.flatMap { try? Self.decoder.decode([String: ReadingPosition].self, from: $0) } ?? [:]
    }

    public func position(forBook key: String) -> ReadingPosition? {
        lock.withLock { positions[key] }
    }

    /// Records where the reader is now. The chapter map is kept, and updated for this chapter.
    public func setPosition(_ position: ReadingPosition, forBook key: String) {
        lock.withLock {
            var merged = position
            merged.chapters = positions[key]?.chapters ?? [:]
            merged.chapters.merge(position.chapters) { _, new in new }
            merged.chapters[position.spinePath] = position.chapterPosition
            guard positions[key] != merged else { return }
            positions[key] = merged
            isDirty = true
        }
    }

    /// Records the position in a chapter the reader is leaving (or has left), without moving
    /// the book's current position. Ignored for books with no position yet.
    public func setChapterPosition(_ chapter: ChapterPosition, spinePath: String, forBook key: String) {
        lock.withLock {
            guard var position = positions[key], position.chapters[spinePath] != chapter else { return }
            position.chapters[spinePath] = chapter
            if position.spinePath == spinePath {
                position.fraction = chapter.fraction
                position.anchor = chapter.anchor
            }
            positions[key] = position
            isDirty = true
        }
    }

    /// Where the reader left a chapter, if they have been there.
    public func chapterPosition(forBook key: String, spinePath: String) -> ChapterPosition? {
        lock.withLock { positions[key]?.chapters[spinePath] }
    }

    /// Writes the file atomically if anything changed since the last save.
    public func save() throws {
        let snapshot: [String: ReadingPosition]? = lock.withLock {
            guard isDirty else { return nil }
            isDirty = false
            if positions.count > Self.capacity {
                let stale = positions.sorted { $0.value.updated < $1.value.updated }.prefix(positions.count - Self.capacity)
                stale.forEach { positions.removeValue(forKey: $0.key) }
            }
            return positions
        }
        guard let snapshot else { return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
