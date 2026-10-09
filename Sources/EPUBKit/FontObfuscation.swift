import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// Font de-obfuscation ported from foliate-js `epub.js` (MIT, Copyright (c) 2022 John Factotum,
// https://github.com/johnfactotum/foliate-js). See THIRD_PARTY.md.
// Spec: https://www.w3.org/publishing/epub32/epub-ocf.html#sec-resource-obfuscation

/// The obfuscation algorithms EPUB uses to protect embedded fonts. They are not encryption:
/// the leading bytes of the file are XOR-ed with a key derived from the package identifier.
public enum ObfuscationAlgorithm: String, Sendable, CaseIterable {
    case idpf = "http://www.idpf.org/2008/embedding"
    case adobe = "http://ns.adobe.com/pdf/enc#RC"

    /// Number of leading bytes that are obfuscated.
    public var headerLength: Int {
        switch self {
        case .idpf: 1040
        case .adobe: 1024
        }
    }
}

/// Reverses font obfuscation for one publication and algorithm.
public struct FontDeobfuscator: Sendable, Equatable {
    public let algorithm: ObfuscationAlgorithm
    public let key: [UInt8]

    public init(algorithm: ObfuscationAlgorithm, key: [UInt8]) {
        self.algorithm = algorithm
        self.key = key
    }

    /// Builds the deobfuscator from package metadata. Returns `nil` when the key cannot be derived
    /// (no identifier, no UUID for Adobe, or no SHA-1 on this platform).
    ///
    /// - Parameters:
    ///   - uniqueIdentifier: the text of the element named by the package `unique-identifier`.
    ///   - identifiers: the text of every `dc:identifier`, in document order.
    public init?(algorithm: ObfuscationAlgorithm, uniqueIdentifier: String, identifiers: [String]) {
        switch algorithm {
        case .idpf:
            // White space (U+0020, U+0009, U+000D, U+000A) is removed before hashing.
            let stripped = uniqueIdentifier.unicodeScalars.filter { !"\u{20}\u{09}\u{0D}\u{0A}".unicodeScalars.contains($0) }
            guard !stripped.isEmpty, let digest = Self.sha1(Data(String(String.UnicodeScalarView(stripped)).utf8)) else { return nil }
            self.init(algorithm: algorithm, key: digest)
        case .adobe:
            guard let key = identifiers.lazy.compactMap(Self.uuidBytes).first else { return nil }
            self.init(algorithm: algorithm, key: key)
        }
    }

    /// XORs the obfuscated header of `data` with the key. The operation is its own inverse.
    public func apply(to data: Data) -> Data {
        guard !key.isEmpty else { return data }
        var bytes = data
        let count = min(algorithm.headerLength, bytes.count)
        bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            for index in 0..<count {
                buffer[index] ^= key[index % key.count]
            }
        }
        return bytes
    }

    /// Whether this platform can derive IDPF keys (SHA-1 comes from CryptoKit).
    public static var isSHA1Available: Bool {
        #if canImport(CryptoKit)
        true
        #else
        false
        #endif
    }

    static func sha1(_ data: Data) -> [UInt8]? {
        #if canImport(CryptoKit)
        Array(Insecure.SHA1.hash(data: data))
        #else
        nil
        #endif
    }

    /// The 16 bytes of the first UUID found in an identifier such as `urn:uuid:…`.
    /// Unlike foliate-js, upper-case hex digits are accepted too.
    static func uuidBytes(in identifier: String) -> [UInt8]? {
        let candidate = identifier.split(separator: ":").last.map(String.init) ?? identifier
        guard let match = candidate.range(of: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
                                          options: .regularExpression) else { return nil }
        let hex = Array(candidate[match].replacingOccurrences(of: "-", with: "").utf8)
        return stride(from: 0, to: hex.count, by: 2).map { offset in
            UInt8(String(decoding: hex[offset..<offset + 2], as: UTF8.self), radix: 16) ?? 0
        }
    }
}
