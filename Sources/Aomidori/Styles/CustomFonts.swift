import AppKit
import AomidoriCore
import CoreText

/// System font files the page may load for the custom font, by token. Only files that back the
/// chosen family are registered, so the scheme handler never serves arbitrary paths.
final class SystemFontFiles: @unchecked Sendable {
    static let shared = SystemFontFiles()
    private let lock = NSLock()
    private var files: [String: URL] = [:]

    func replace(with files: [String: URL]) {
        lock.withLock { self.files = files }
    }

    func url(forToken token: String) -> URL? {
        lock.withLock { files[token] }
    }
}

/// The fonts the reader can choose for the app's custom font: installed families, plus font
/// files loaded into `~/Library/Application Support/Aomidori/Fonts/`.
@MainActor
final class CustomFonts {
    /// A face found in a file of the fonts folder.
    struct FileFace: Equatable {
        let family: String
        let postScriptName: String
        let fileName: String
        let weight: Int
        let italic: Bool
    }

    static let fileExtensions: Set<String> = ["ttf", "otf", "woff", "woff2"]

    private(set) var fileFaces: [FileFace] = []
    private var registeredFiles: Set<URL> = []

    /// Families from the fonts folder first, then the installed ones, without duplicates.
    var families: [String] {
        let loaded = loadedFamilies
        let installed = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") && !loaded.contains($0) }
        return loaded.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            + installed.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var loadedFamilies: Set<String> { Set(fileFaces.map(\.family)) }

    /// Reads the fonts folder. Its files are also registered for this process, so the picker
    /// can preview them.
    func rescan() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: AppPaths.fonts, includingPropertiesForKeys: nil)) ?? []
        var faces: [FileFace] = []
        for url in urls where Self.fileExtensions.contains(url.pathExtension.lowercased()) {
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            for descriptor in descriptors {
                guard let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String,
                      let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { continue }
                let (weight, italic) = Self.style(of: descriptor)
                faces.append(FileFace(family: family, postScriptName: name, fileName: url.lastPathComponent, weight: weight, italic: italic))
            }
            if !descriptors.isEmpty, !registeredFiles.contains(url) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                registeredFiles.insert(url)
            }
        }
        fileFaces = faces
    }

    /// Copies font files into the fonts folder (replacing files with the same name) and returns
    /// the families they contain. Files Core Text cannot read are refused.
    func install(_ urls: [URL]) throws -> [String] {
        var families: [String] = []
        for url in urls {
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            guard Self.fileExtensions.contains(url.pathExtension.lowercased()), !descriptors.isEmpty else {
                throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: url])
            }
            let destination = AppPaths.fonts.appendingPathComponent(url.lastPathComponent)
            if destination.standardizedFileURL != url.standardizedFileURL {
                if registeredFiles.contains(destination) {
                    CTFontManagerUnregisterFontsForURL(destination as CFURL, .process, nil)
                    registeredFiles.remove(destination)
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.copyItem(at: url, to: destination)
            }
            families += descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        }
        rescan()
        return Array(Set(families)).sorted()
    }

    /// The faces of a family as the page loads them. Loaded files are served from the fonts
    /// folder. Installed fonts are asked for by PostScript name (`local()`); their files are
    /// also offered, in case the web view does not see fonts the user installed.
    func faces(forFamily family: String) -> [FontFaceSource] {
        let files = fileFaces.filter { $0.family == family }
        if !files.isEmpty {
            SystemFontFiles.shared.replace(with: [:])
            return files.map { face in
                FontFaceSource(url: "/\(PageSchemeHandler.userPrefix)Fonts/\(Self.pathComponent(face.fileName))",
                               weight: face.weight, italic: face.italic)
            }
        }
        var tokens: [String: URL] = [:]
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        let faces = members.enumerated().compactMap { index, member -> FontFaceSource? in
            guard let name = member.first as? String else { return nil }
            let descriptor = CTFontDescriptorCreateWithNameAndSize(name as CFString, 0)
            let (weight, italic) = Self.style(of: descriptor)
            var url: String?
            if let file = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
               ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
                let token = "\(index)-\(file.lastPathComponent)"
                tokens[token] = file
                url = "/\(PageSchemeHandler.userPrefix)SystemFonts/\(Self.pathComponent(token))"
            }
            return FontFaceSource(postScriptName: name, url: url, weight: weight, italic: italic)
        }
        SystemFontFiles.shared.replace(with: tokens)
        return faces
    }

    /// A font to preview a family in, at the given size.
    static func previewFont(family: String, size: CGFloat) -> NSFont? {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }

    private static func style(of descriptor: CTFontDescriptor) -> (weight: Int, italic: Bool) {
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
        let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
        return (CustomFontCSS.cssWeight(fromTrait: weight), symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0)
    }

    private static func pathComponent(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}
