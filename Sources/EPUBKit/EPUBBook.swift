import Foundation

/// A resource declared in the package manifest.
public struct ManifestItem: Equatable, Sendable {
    public let id: String
    /// Container-relative path.
    public let path: String
    public let mediaType: String
    public let properties: Set<String>
}

/// A reading-order entry.
public struct SpineItem: Equatable, Sendable {
    public let idref: String
    public let path: String
    public let mediaType: String
    /// `false` for `linear="no"` items (notes, answers, pop-ups): reachable by links, skipped by
    /// sequential navigation.
    public let isLinear: Bool
}

/// A table-of-contents entry. Headings without a target have a `nil` path.
public struct TOCEntry: Equatable, Sendable {
    public let title: String
    public let path: String?
    public let fragment: String?
    public let children: [TOCEntry]
}

/// The parsed structure of an EPUB publication.
public struct EPUBBook: Sendable {
    /// The package unique identifier (`unique-identifier`), empty if absent.
    public let identifier: String
    public let title: String?
    public let language: String?
    /// Path of the package document (OPF).
    public let packagePath: String
    public let manifest: [ManifestItem]
    public let spine: [SpineItem]
    public let toc: [TOCEntry]

    private let manifestByPath: [String: ManifestItem]
    private let spineIndexByPath: [String: Int]

    public init(identifier: String, title: String?, language: String?, packagePath: String,
                manifest: [ManifestItem], spine: [SpineItem], toc: [TOCEntry]) {
        self.identifier = identifier
        self.title = title
        self.language = language
        self.packagePath = packagePath
        self.manifest = manifest
        self.spine = spine
        self.toc = toc
        self.manifestByPath = Dictionary(manifest.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        self.spineIndexByPath = Dictionary(spine.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func manifestItem(forPath path: String) -> ManifestItem? {
        manifestByPath[path]
    }

    public func spineIndex(forPath path: String) -> Int? {
        spineIndexByPath[path]
    }

    /// The first spine item a reader should show.
    public var firstReadableIndex: Int? {
        spine.firstIndex(where: \.isLinear) ?? (spine.isEmpty ? nil : 0)
    }

    /// The next linear item after `index`. Books that mark every item non-linear are read in order.
    public func nextReadableIndex(after index: Int) -> Int? {
        guard index + 1 < spine.count else { return nil }
        let candidates = spine.indices[(index + 1)...]
        return candidates.first(where: { spine[$0].isLinear }) ?? (hasLinearItems ? nil : candidates.first)
    }

    /// The previous linear item before `index`.
    public func previousReadableIndex(before index: Int) -> Int? {
        guard index > 0, index <= spine.count else { return nil }
        let candidates = spine.indices[..<index].reversed()
        return candidates.first(where: { spine[$0].isLinear }) ?? (hasLinearItems ? nil : candidates.first)
    }

    /// The title of the first TOC entry that points at `path`, searched depth-first.
    public func tocTitle(forPath path: String) -> String? {
        func search(_ entries: [TOCEntry]) -> String? {
            for entry in entries {
                if entry.path == path { return entry.title }
                if let found = search(entry.children) { return found }
            }
            return nil
        }
        return search(toc)
    }

    private var hasLinearItems: Bool { spine.contains(where: \.isLinear) }
}
