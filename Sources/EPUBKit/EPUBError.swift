import Foundation

/// Errors raised while opening or reading an EPUB publication.
public enum EPUBError: Error, Equatable, Sendable {
    /// The file is not a readable ZIP archive.
    case unreadableArchive
    /// `META-INF/container.xml` is missing or names no package document.
    case missingContainer
    /// The package document (OPF) named by the container is missing.
    case missingPackage(path: String)
    /// An XML document could not be parsed.
    case malformedXML(path: String)
    /// A resource referenced by the publication is not in the archive.
    case missingResource(path: String)
    /// A file of the archive inflates past `ZIPContainer.defaultMaximumEntrySize`.
    case oversizedResource(path: String)
    /// The spine lists no readable content document.
    case emptySpine
    /// Content documents are encrypted with an unsupported (DRM) scheme.
    case drmProtected
}
