import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// The result of parsing a container: the book structure and how to decode its resources.
public struct ParsedPublication: Sendable {
    public let book: EPUBBook
    /// Obfuscated resources, by container path.
    public let obfuscatedResources: [String: FontDeobfuscator]
}

/// Parses the OCF container, the package document and the navigation of an EPUB 2 or 3 book.
public enum EPUBParser {
    static let containerPath = "META-INF/container.xml"
    static let encryptionPath = "META-INF/encryption.xml"

    public static func parse(_ container: some ResourceContainer) throws -> ParsedPublication {
        let packagePath = try packageDocumentPath(in: container)
        guard container.contains(packagePath) else { throw EPUBError.missingPackage(path: packagePath) }
        let package = try xml(at: packagePath, in: container)
        guard let root = package.rootElement() else { throw EPUBError.malformedXML(path: packagePath) }

        let metadata = root.firstChild(named: "metadata")
        let identifiers = metadata?.childElements(named: "identifier") ?? []
        let uniqueIdentifier = uniqueIdentifierText(root: root, identifiers: identifiers)
        let manifest = manifestItems(root: root, packagePath: packagePath)
        let manifestByID = Dictionary(manifest.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let spineElement = root.firstChild(named: "spine")
        let spine = spineItems(spineElement, manifest: manifestByID)
        guard !spine.isEmpty else { throw EPUBError.emptySpine }

        let toc = tableOfContents(manifest: manifest, manifestByID: manifestByID, spineElement: spineElement, in: container)
        let book = EPUBBook(
            identifier: uniqueIdentifier,
            title: metadata?.firstChild(named: "title")?.normalizedText.nilIfEmpty,
            language: metadata?.firstChild(named: "language")?.normalizedText.nilIfEmpty,
            packagePath: packagePath,
            manifest: manifest,
            spine: spine,
            toc: toc,
            metadata: descriptiveMetadata(metadata, uniqueIdentifier: uniqueIdentifier),
            coverPath: coverPath(manifest: manifest, manifestByID: manifestByID, metadata: metadata)
        )
        let obfuscated = try obfuscatedResources(
            in: container,
            spine: spine,
            uniqueIdentifier: uniqueIdentifier,
            identifiers: identifiers.map(\.normalizedText)
        )
        return ParsedPublication(book: book, obfuscatedResources: obfuscated)
    }

    // MARK: Container and package

    static func packageDocumentPath(in container: some ResourceContainer) throws -> String {
        guard container.contains(containerPath) else { throw EPUBError.missingContainer }
        let document = try xml(at: containerPath, in: container)
        let rootfiles = document.rootElement()?.descendants(named: "rootfile") ?? []
        let preferred = rootfiles.first { $0.attributeValue("media-type") == MediaType.package } ?? rootfiles.first
        guard let fullPath = preferred?.attributeValue("full-path"), !fullPath.isEmpty else {
            throw EPUBError.missingContainer
        }
        return ResourcePath.normalize(fullPath.removingPercentEncoding ?? fullPath)
    }

    static func uniqueIdentifierText(root: XMLElement, identifiers: [XMLElement]) -> String {
        if let id = root.attributeValue("unique-identifier"),
           let element = identifiers.first(where: { $0.attributeValue("id") == id }) {
            return element.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        return identifiers.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func descriptiveMetadata(_ element: XMLElement?, uniqueIdentifier: String) -> EPUBMetadata {
        var metadata = EPUBMetadata()
        guard let element else { return metadata }
        let texts = { (name: String) in element.childElements(named: name).map(\.normalizedText).filter { !$0.isEmpty } }
        metadata.title = texts("title").first
        metadata.creators = texts("creator")
        metadata.contributors = texts("contributor")
        metadata.publisher = texts("publisher").first
        metadata.date = texts("date").first
        metadata.language = texts("language").first
        metadata.rights = texts("rights").first
        metadata.subjects = texts("subject")
        metadata.description = texts("description").first
        metadata.identifier = uniqueIdentifier.nilIfEmpty
        metadata.modified = element.childElements(named: "meta")
            .first { $0.attributeValue("property") == "dcterms:modified" }?.normalizedText.nilIfEmpty
        return metadata
    }

    static func coverPath(manifest: [ManifestItem], manifestByID: [String: ManifestItem], metadata: XMLElement?) -> String? {
        if let item = manifest.first(where: { $0.properties.contains("cover-image") }) { return item.path }
        let id = metadata?.childElements(named: "meta").first { $0.attributeValue("name") == "cover" }?.attributeValue("content")
        guard let item = id.flatMap({ manifestByID[$0] }), item.mediaType.hasPrefix("image/") else { return nil }
        return item.path
    }

    static func manifestItems(root: XMLElement, packagePath: String) -> [ManifestItem] {
        let items = root.firstChild(named: "manifest")?.childElements(named: "item") ?? []
        return items.compactMap { element in
            guard let id = element.attributeValue("id"),
                  let href = element.attributeValue("href"),
                  let resolved = ResourcePath.resolve(href, relativeTo: packagePath) else { return nil }
            let properties = Set((element.attributeValue("properties") ?? "").split(whereSeparator: \.isWhitespace).map(String.init))
            return ManifestItem(
                id: id,
                path: resolved.path,
                mediaType: MediaType.normalized(element.attributeValue("media-type") ?? "", path: resolved.path),
                properties: properties
            )
        }
    }

    static func spineItems(_ spine: XMLElement?, manifest: [String: ManifestItem]) -> [SpineItem] {
        (spine?.childElements(named: "itemref") ?? []).compactMap { element in
            guard let idref = element.attributeValue("idref"), let item = manifest[idref] else { return nil }
            let linear = element.attributeValue("linear")?.trimmingCharacters(in: .whitespaces).lowercased() != "no"
            return SpineItem(idref: idref, path: item.path, mediaType: item.mediaType, isLinear: linear)
        }
    }

    // MARK: Table of contents

    static func tableOfContents(manifest: [ManifestItem], manifestByID: [String: ManifestItem],
                                spineElement: XMLElement?, in container: some ResourceContainer) -> [TOCEntry] {
        // EPUB 3 navigation document first, EPUB 2 NCX as fallback. A broken TOC never blocks reading.
        if let nav = manifest.navigationDocument,
           let document = try? xml(at: nav.path, in: container) {
            let entries = navigationEntries(document, documentPath: nav.path)
            if !entries.isEmpty { return entries }
        }
        let ncx = spineElement?.attributeValue("toc").flatMap { manifestByID[$0] }
            ?? manifest.first { $0.mediaType == MediaType.ncx }
        if let ncx, let document = try? xml(at: ncx.path, in: container) {
            return ncxEntries(document, documentPath: ncx.path)
        }
        return []
    }

    static func navigationEntries(_ document: XMLDocument, documentPath: String) -> [TOCEntry] {
        let navs = document.rootElement()?.descendants(named: "nav") ?? []
        let toc = navs.first { nav in
            (nav.attributeValue("type") ?? "").split(whereSeparator: \.isWhitespace).contains("toc")
        } ?? navs.first
        guard let list = toc?.firstChild(named: "ol") else { return [] }
        return navigationList(list, documentPath: documentPath)
    }

    private static func navigationList(_ list: XMLElement, documentPath: String) -> [TOCEntry] {
        list.childElements(named: "li").compactMap { item in
            let label = item.firstChild(named: "a") ?? item.firstChild(named: "span")
            let children = item.firstChild(named: "ol").map { navigationList($0, documentPath: documentPath) } ?? []
            let title = label?.normalizedText ?? ""
            guard !title.isEmpty || !children.isEmpty else { return nil }
            let target = label?.attributeValue("href").flatMap { ResourcePath.resolve($0, relativeTo: documentPath) }
            return TOCEntry(title: title, path: target?.path, fragment: target?.fragment, children: children)
        }
    }

    static func ncxEntries(_ document: XMLDocument, documentPath: String) -> [TOCEntry] {
        guard let navMap = document.rootElement()?.firstChild(named: "navMap") else { return [] }
        return ncxPoints(navMap, documentPath: documentPath)
    }

    private static func ncxPoints(_ parent: XMLElement, documentPath: String) -> [TOCEntry] {
        parent.childElements(named: "navPoint").compactMap { point in
            let title = point.firstChild(named: "navLabel")?.firstChild(named: "text")?.normalizedText ?? ""
            let children = ncxPoints(point, documentPath: documentPath)
            guard !title.isEmpty || !children.isEmpty else { return nil }
            let target = point.firstChild(named: "content")?.attributeValue("src")
                .flatMap { ResourcePath.resolve($0, relativeTo: documentPath) }
            return TOCEntry(title: title, path: target?.path, fragment: target?.fragment, children: children)
        }
    }

    // MARK: Encryption

    static func obfuscatedResources(in container: some ResourceContainer, spine: [SpineItem],
                                    uniqueIdentifier: String, identifiers: [String]) throws -> [String: FontDeobfuscator] {
        guard container.contains(encryptionPath), let document = try? xml(at: encryptionPath, in: container) else { return [:] }
        let spinePaths = Set(spine.map(\.path))
        var deobfuscators: [ObfuscationAlgorithm: FontDeobfuscator] = [:]
        var result: [String: FontDeobfuscator] = [:]

        for data in document.rootElement()?.descendants(named: "EncryptedData") ?? [] {
            guard let uri = data.descendants(named: "CipherReference").first?.attributeValue("URI"),
                  let path = ResourcePath.resolve(uri, relativeTo: "")?.path else { continue }
            let algorithmURI = data.firstChild(named: "EncryptionMethod")?.attributeValue("Algorithm") ?? ""
            guard let algorithm = ObfuscationAlgorithm(rawValue: algorithmURI) else {
                // Real encryption. Fonts can fall back to system ones; content documents cannot.
                if spinePaths.contains(path) { throw EPUBError.drmProtected }
                continue
            }
            if deobfuscators[algorithm] == nil {
                deobfuscators[algorithm] = FontDeobfuscator(algorithm: algorithm, uniqueIdentifier: uniqueIdentifier, identifiers: identifiers)
            }
            if let deobfuscator = deobfuscators[algorithm] { result[path] = deobfuscator }
        }
        return result
    }

    // MARK: Helpers

    static func xml(at path: String, in container: some ResourceContainer) throws -> XMLDocument {
        try XMLParsing.document(from: container.data(at: path), path: path)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
