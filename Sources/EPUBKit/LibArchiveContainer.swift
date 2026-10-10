#if canImport(CArchive)
import CArchive
import Foundation

/// An archive read with macOS's libarchive: RAR, RAR5 and 7z (a ZIP, even named `.cbr`, goes to
/// `ZIPContainer`). A RAR, above all a solid one, cannot give one file without decompressing what
/// comes before it, and a comic's page shows all its pictures at once: so the archive is read
/// through once, here, and the files it keeps are written to a private temporary folder, removed
/// when the container goes. Each file is stored under a number, never under its path in the
/// archive, so no name can point outside the folder.
/// Author: Rocco Casadei, a.k.a. Roccobot
public final class LibArchiveContainer: ResourceContainer {
    /// The kept files only, in the archive's order.
    public let paths: [String]
    /// Internal for the tests, which check that it goes with the container.
    let folder: URL
    private let files: [String: URL]
    private let foldedPaths: [String: String]

    /// A comic of 2 GB is already far past any real one: past that, the archive is built to fill
    /// the disk, whatever its directory declares.
    public static let defaultMaximumTotalSize = 2 << 30

    /// - Parameter keep: which stored paths to extract; the others are skipped unread.
    public init(url: URL, keep: (String) -> Bool = { _ in true },
                maximumEntrySize: Int = ZIPContainer.defaultMaximumEntrySize,
                maximumTotalSize: Int = LibArchiveContainer.defaultMaximumTotalSize) throws {
        let fileManager = FileManager.default
        _ = Self.leftoversRemoved
        let folder = fileManager.temporaryDirectory
            .appendingPathComponent("\(Self.prefix)\(getpid())-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            (paths, files) = try Self.extract(url, into: folder, keep: keep,
                                              maximumEntrySize: maximumEntrySize, maximumTotalSize: maximumTotalSize)
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        self.folder = folder
        var folded: [String: String] = [:]
        for path in paths where folded[path.lowercased()] == nil { folded[path.lowercased()] = path }
        foldedPaths = folded
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Folders are named `Aomidori-<process>-<random>`.
    static let prefix = "Aomidori-"

    /// Once per process, before the first folder: the folders of processes that are gone (the
    /// app was force-quit, or crashed, before its containers went). Another running copy of the
    /// app keeps its own.
    static let leftoversRemoved: Void = removeLeftovers(in: FileManager.default.temporaryDirectory)

    static func removeLeftovers(in temporary: URL) {
        let fileManager = FileManager.default
        for name in (try? fileManager.contentsOfDirectory(atPath: temporary.path)) ?? [] where name.hasPrefix(prefix) {
            guard let process = Int32(name.dropFirst(prefix.count).prefix { $0 != "-" }),
                  process != getpid(), kill(process, 0) != 0, errno == ESRCH else { continue }
            try? fileManager.removeItem(at: temporary.appendingPathComponent(name))
        }
    }

    public func contains(_ path: String) -> Bool {
        storedPath(for: path) != nil
    }

    public func storedPath(for path: String) -> String? {
        files[path] != nil ? path : foldedPaths[path.lowercased()]
    }

    public func data(at path: String) throws -> Data {
        guard let stored = storedPath(for: path), let file = files[stored] else { throw EPUBError.missingResource(path: path) }
        return try Data(contentsOf: file)
    }

    private static func extract(_ url: URL, into folder: URL, keep: (String) -> Bool,
                                maximumEntrySize: Int, maximumTotalSize: Int) throws -> ([String], [String: URL]) {
        guard let archive = archive_read_new() else { throw EPUBError.unreadableArchive }
        defer { archive_read_free(archive) }
        archive_read_support_format_rar(archive)
        archive_read_support_format_rar5(archive)
        archive_read_support_format_7zip(archive)
        guard archive_read_open_filename(archive, url.path, 1 << 16) == ARCHIVE_OK else { throw EPUBError.unreadableArchive }

        var paths: [String] = []
        var files: [String: URL] = [:]
        var total = 0
        var buffer = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            var entry: OpaquePointer?
            let status = archive_read_next_header(archive, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else { throw EPUBError.unreadableArchive }
            guard archive_entry_filetype(entry) & mode_t(AE_IFMT) == mode_t(AE_IFREG),
                  let name = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry) else { continue }
            let path = String(cString: name)
            guard files[path] == nil, keep(path) else { continue }
            // A file protected by a password: libarchive cannot read it, and neither can the reader.
            if archive_entry_is_encrypted(entry) != 0 { throw EPUBError.passwordProtected }

            let file = folder.appendingPathComponent(String(paths.count))
            guard FileManager.default.createFile(atPath: file.path, contents: nil),
                  let handle = try? FileHandle(forWritingTo: file) else { throw EPUBError.unreadableArchive }
            defer { try? handle.close() }
            var size = 0
            while true {
                let count = buffer.withUnsafeMutableBytes { archive_read_data(archive, $0.baseAddress, $0.count) }
                if count == 0 { break }
                guard count > 0 else { throw EPUBError.unreadableArchive }
                size += count
                total += count
                guard size <= maximumEntrySize, total <= maximumTotalSize else { throw EPUBError.oversizedResource(path: path) }
                try handle.write(contentsOf: buffer[0..<count])
            }
            paths.append(path)
            files[path] = file
        }
        return (paths, files)
    }
}
#endif
