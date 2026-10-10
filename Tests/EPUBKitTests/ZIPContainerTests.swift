import Foundation
import Testing
@testable import EPUBKit

@Suite("ZIP container")
struct ZIPContainerTests {
    /// A file that inflates past the limit is refused instead of filling the memory: two
    /// megabytes of zeros compress to a few kilobytes, the shape of a "zip bomb".
    @Test func entryLargerThanTheLimitIsRefused() throws {
        var fixture = EPUBFixture()
        fixture.add("OEBPS/big.bin", Data(count: 2 << 20))
        fixture.add("OEBPS/small.txt", "piccolo")
        let url = try fixture.write()
        defer { try? FileManager.default.removeItem(at: url) }

        let container = try ZIPContainer(url: url, maximumEntrySize: 1 << 20)
        #expect(throws: EPUBError.oversizedResource(path: "OEBPS/big.bin")) { try container.data(at: "OEBPS/big.bin") }
        #expect(try container.data(at: "OEBPS/small.txt") == Data("piccolo".utf8))
        #expect(try ZIPContainer(url: url).data(at: "OEBPS/big.bin").count == 2 << 20)
    }
}
