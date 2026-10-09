import Foundation
import Testing
#if canImport(CryptoKit)
import CryptoKit
#endif
@testable import EPUBKit

@Suite("Font de-obfuscation")
struct FontObfuscationTests {
    static let font = Data((0..<3000).map { UInt8(($0 * 7 + 3) % 256) })

    /// Obfuscates independently of the code under test.
    static func obfuscate(_ data: Data, key: [UInt8], length: Int) -> Data {
        var bytes = [UInt8](data)
        for index in 0..<min(length, bytes.count) { bytes[index] ^= key[index % key.count] }
        return Data(bytes)
    }

    static func fixture(algorithm: String, fontData: Data, identifier: String = "urn:uuid:12345678-90ab-cdef-1234-567890abcdef") -> EPUBFixture {
        var fixture = EPUBFixture.epub3()
        fixture.files.removeAll { $0.path == "OEBPS/Fonts/Serif.otf" }
        fixture.add("OEBPS/Fonts/Serif.otf", fontData)
        fixture.add("META-INF/encryption.xml", """
        <encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container" xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
          <enc:EncryptedData><enc:EncryptionMethod Algorithm="\(algorithm)"/>
            <enc:CipherData><enc:CipherReference URI="OEBPS/Fonts/Serif.otf"/></enc:CipherData></enc:EncryptedData>
        </encryption>
        """)
        return fixture
    }

    #if canImport(CryptoKit)
    @Test func idpfFontIsRestored() throws {
        // The key is the SHA-1 of the unique identifier with white space removed.
        let key = Array(Insecure.SHA1.hash(data: Data("urn:uuid:12345678-90ab-cdef-1234-567890abcdef".utf8)))
        let obfuscated = Self.obfuscate(Self.font, key: key, length: 1040)
        let url = try Self.fixture(algorithm: "http://www.idpf.org/2008/embedding", fontData: obfuscated).write()
        defer { try? FileManager.default.removeItem(at: url) }

        let publication = try EPUBPublication(contentsOf: url)
        #expect(publication.isObfuscated("OEBPS/Fonts/Serif.otf"))
        #expect(try publication.resource(at: "OEBPS/Fonts/Serif.otf").data == Self.font)
        #expect(try publication.resource(at: "OEBPS/Styles/book.css").data == Data("p { margin: 0 }".utf8))
    }
    #endif

    @Test func adobeFontIsRestored() throws {
        let key: [UInt8] = [0x12, 0x34, 0x56, 0x78, 0x90, 0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x90, 0xAB, 0xCD, 0xEF]
        let obfuscated = Self.obfuscate(Self.font, key: key, length: 1024)
        let url = try Self.fixture(algorithm: "http://ns.adobe.com/pdf/enc#RC", fontData: obfuscated).write()
        defer { try? FileManager.default.removeItem(at: url) }

        let publication = try EPUBPublication(contentsOf: url)
        #expect(try publication.resource(at: "OEBPS/Fonts/Serif.otf").data == Self.font)
    }

    @Test func shortFilesAndKeyDerivation() {
        let deobfuscator = FontDeobfuscator(algorithm: .adobe, key: [0xFF])
        #expect(deobfuscator.apply(to: Data([0x00, 0x0F])) == Data([0xFF, 0xF0]))
        #expect(FontDeobfuscator.uuidBytes(in: "urn:uuid:ABCDEF01-2345-6789-ABCD-EF0123456789")?.first == 0xAB)
        #expect(FontDeobfuscator.uuidBytes(in: "urn:isbn:9780000000000") == nil)
        #expect(FontDeobfuscator(algorithm: .adobe, uniqueIdentifier: "x", identifiers: ["urn:isbn:1"]) == nil)
    }
}
