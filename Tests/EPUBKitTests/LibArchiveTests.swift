#if canImport(CArchive)
import Foundation
import Testing
@testable import EPUBKit

/// The RAR side of comic archives (CBR), read with macOS's libarchive. The three archives in
/// Fixtures come from libarchive's own tests (see THIRD_PARTY.md), with the contents those tests
/// expect: nothing writes RAR on a Mac, so they cannot be generated here.
@Suite("Comics (CBR)")
struct LibArchiveTests {
    static func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "rar", subdirectory: "Fixtures"))
    }

    /// RAR 4: regular files only (the symbolic link and the folders are left out), in the
    /// archive's order, read back whole.
    @Test func rarFilesAreReadBack() throws {
        let container = try LibArchiveContainer(url: Self.fixture("test_read_format_rar"))
        #expect(container.paths == ["test.txt", "testdir/test.txt"])
        #expect(try container.data(at: "testdir/test.txt") == Data("test text document\r\n".utf8))
        #expect(container.storedPath(for: "TESTDIR/Test.TXT") == "testdir/test.txt")
        #expect(!container.contains("testlink"))
        #expect(throws: EPUBError.missingResource(path: "missing.jpg")) { try container.data(at: "missing.jpg") }
    }

    /// A solid RAR 5, where every file depends on the ones before it: each one comes back as
    /// libarchive's test generated it.
    @Test func solidRar5IsReadBack() throws {
        let container = try LibArchiveContainer(url: Self.fixture("test_read_format_rar5_multiple_files_solid"))
        #expect(container.paths == ["test1.bin", "test2.bin", "test3.bin", "test4.bin"])
        for (index, path) in container.paths.enumerated() {
            let data = try container.data(at: path)
            #expect(data.count == 4096)
            let magic = index + 1
            let expected = (1...1024).map { k in UInt32(max(k * k - 3 * k + 1 + magic, 0)) }
            let values = stride(from: 0, to: data.count, by: 4).map { offset in
                data[offset..<offset + 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
            }
            #expect(values == expected, "\(path)")
        }
    }

    /// Only the files asked for are written to disk, and the folder goes with the container.
    @Test func keepsOnlyWhatIsAskedAndCleansUp() throws {
        var container: LibArchiveContainer? = try LibArchiveContainer(
            url: Self.fixture("test_read_format_rar5_multiple_files_solid"), keep: { $0 == "test3.bin" })
        let folder = try #require(container?.folder)
        #expect(container?.paths == ["test3.bin"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 1)
        container = nil
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    /// What a force-quit leaves behind goes; this process's folders, another running process's
    /// (launchd, process 1, always runs) and anything not named by the container stay.
    @Test func leftoversOfGoneProcessesAreRemoved() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let names = ["Aomidori-999999999-a", "Aomidori-\(getpid())-b", "Aomidori-1-c", "Altro-999999999-d"]
        for name in names {
            try FileManager.default.createDirectory(at: temporary.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        LibArchiveContainer.removeLeftovers(in: temporary)
        let left = try FileManager.default.contentsOfDirectory(atPath: temporary.path).sorted()
        #expect(left == names.dropFirst().sorted())
    }

    @Test func aPasswordIsReported() throws {
        #expect(throws: EPUBError.passwordProtected) {
            try LibArchiveContainer(url: Self.fixture("test_read_format_rar_encryption_data"))
        }
    }

    @Test func entryLimitsHold() throws {
        let url = try Self.fixture("test_read_format_rar5_multiple_files_solid")
        #expect(throws: EPUBError.oversizedResource(path: "test1.bin")) {
            try LibArchiveContainer(url: url, maximumEntrySize: 4095)
        }
        #expect(throws: EPUBError.oversizedResource(path: "test3.bin")) {
            try LibArchiveContainer(url: url, maximumTotalSize: 3 * 4096 - 1)
        }
    }

    /// A comic goes to ZIPFoundation when it is a ZIP, whatever its name, and to libarchive
    /// otherwise; a file that is neither is refused.
    @Test func theArchiveDecidesTheReader() throws {
        #expect(try ComicArchive.container(at: Self.fixture("test_read_format_rar")) is LibArchiveContainer)

        var zip = EPUBFixture(files: [])
        zip.add("1.png", ComicTests.pixel)
        let renamed = try zip.write(extension: "cbr")
        defer { try? FileManager.default.removeItem(at: renamed) }
        #expect(try ComicArchive.container(at: renamed) is ZIPContainer)

        let text = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).cbr")
        try Data("not an archive".utf8).write(to: text)
        defer { try? FileManager.default.removeItem(at: text) }
        #expect(throws: EPUBError.unreadableArchive) { try ComicArchive.container(at: text) }
    }
}
#endif
