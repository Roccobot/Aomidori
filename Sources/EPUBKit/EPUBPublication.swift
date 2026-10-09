import Foundation

/// A resource ready to be served to the renderer.
public struct EPUBResource: Sendable {
    public let data: Data
    public let mediaType: String

    public init(data: Data, mediaType: String) {
        self.data = data
        self.mediaType = mediaType
    }
}

/// An open EPUB: the parsed structure plus lazy, thread-safe access to its resources.
public final class EPUBPublication: Sendable {
    public let book: EPUBBook
    private let container: any ResourceContainer
    private let obfuscatedResources: [String: FontDeobfuscator]

    public init(container: any ResourceContainer) throws {
        let parsed = try EPUBParser.parse(container)
        self.book = parsed.book
        self.container = container
        self.obfuscatedResources = parsed.obfuscatedResources
    }

    /// Opens the EPUB file at `url`. Only the ZIP directory and the package/navigation documents
    /// are read here; everything else is read on demand.
    public convenience init(contentsOf url: URL) throws {
        try self.init(container: ZIPContainer(url: url))
    }

    /// The bytes and MIME type of the resource at a container-relative path, de-obfuscated if needed.
    public func resource(at path: String) throws -> EPUBResource {
        var data = try container.data(at: path)
        if let deobfuscator = obfuscatedResources[path] {
            data = deobfuscator.apply(to: data)
        }
        let mediaType = book.manifestItem(forPath: path)?.mediaType ?? MediaType.forPath(path)
        return EPUBResource(data: data, mediaType: mediaType)
    }

    /// Whether a resource needs de-obfuscation (exposed for diagnostics and tests).
    public func isObfuscated(_ path: String) -> Bool {
        obfuscatedResources[path] != nil
    }
}
