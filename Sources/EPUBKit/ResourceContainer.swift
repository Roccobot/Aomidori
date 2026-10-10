import Foundation
import ZIPFoundation

/// Read-only access to the files of an OCF container, addressed by container-relative path.
public protocol ResourceContainer: Sendable {
    /// Returns the bytes of the file at `path` (exact match first, then case-insensitive).
    func data(at path: String) throws -> Data
    /// Whether a file exists at `path`.
    func contains(_ path: String) -> Bool
    /// The path as the container stores it, when `path` names a file with another letter case.
    func storedPath(for path: String) -> String?
}

/// A lazy, thread-safe reader over a ZIP archive: the central directory is indexed once,
/// entries are inflated only when requested. Nothing is extracted to disk.
public final class ZIPContainer: ResourceContainer, @unchecked Sendable {
    // `Archive` reads through a single file handle and is not thread-safe: every access
    // after initialisation goes through `lock`.
    private let archive: Archive
    private let entries: [String: Entry]
    private let foldedPaths: [String: String]
    private let lock = NSLock()
    private let maximumEntrySize: Int

    /// No file of a book or comic is this large; a larger one is an archive built to fill the
    /// memory ("zip bomb"), whatever size its directory declares.
    public static let defaultMaximumEntrySize = 256 << 20

    public init(url: URL, maximumEntrySize: Int = ZIPContainer.defaultMaximumEntrySize) throws {
        self.maximumEntrySize = maximumEntrySize
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw EPUBError.unreadableArchive
        }
        var entries: [String: Entry] = [:]
        var folded: [String: String] = [:]
        for entry in archive where entry.type == .file {
            entries[entry.path] = entry
            let key = entry.path.lowercased()
            if folded[key] == nil { folded[key] = entry.path }
        }
        self.archive = archive
        self.entries = entries
        self.foldedPaths = folded
    }

    public func contains(_ path: String) -> Bool {
        entry(for: path) != nil
    }

    public func storedPath(for path: String) -> String? {
        entry(for: path)?.path
    }

    public func data(at path: String) throws -> Data {
        guard let entry = entry(for: path) else { throw EPUBError.missingResource(path: path) }
        // The declared size comes from the archive itself: it only sizes the first allocation,
        // and the limit is checked on the bytes actually inflated.
        guard entry.uncompressedSize <= UInt64(maximumEntrySize) else { throw EPUBError.oversizedResource(path: path) }
        let limit = maximumEntrySize
        return try lock.withLock {
            var data = Data()
            data.reserveCapacity(min(Int(clamping: entry.uncompressedSize), 16 << 20))
            _ = try archive.extract(entry, skipCRC32: false) { chunk in
                guard data.count + chunk.count <= limit else { throw EPUBError.oversizedResource(path: path) }
                data.append(chunk)
            }
            return data
        }
    }

    private func entry(for path: String) -> Entry? {
        if let entry = entries[path] { return entry }
        // Some books reference files with a different letter case than the archive stores.
        return foldedPaths[path.lowercased()].flatMap { entries[$0] }
    }
}
