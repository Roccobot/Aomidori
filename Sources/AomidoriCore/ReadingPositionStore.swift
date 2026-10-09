import Foundation

/// Where the reader left a book.
public struct ReadingPosition: Codable, Equatable, Sendable {
    /// Container path of the spine item. Preferred over the index, which shifts if the book changes.
    public var spinePath: String
    public var spineIndex: Int
    /// Vertical scroll position as a fraction of the scrollable height, 0...1.
    public var fraction: Double
    public var updated: Date

    public init(spinePath: String, spineIndex: Int, fraction: Double, updated: Date = Date()) {
        self.spinePath = spinePath
        self.spineIndex = spineIndex
        self.fraction = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        self.updated = updated
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

    public func setPosition(_ position: ReadingPosition, forBook key: String) {
        lock.withLock {
            guard positions[key] != position else { return }
            positions[key] = position
            isDirty = true
        }
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
