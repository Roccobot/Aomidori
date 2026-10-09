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
        let style: FaceStyle
    }

    /// How a face is declared to the page: exact weight and width, style, and the axis ranges
    /// of a variable font.
    struct FaceStyle: Equatable {
        var weight: Double
        var italic: Bool
        var stretch: Double
        var weightRange: ClosedRange<Double>?
        var stretchRange: ClosedRange<Double>?

        var isVariable: Bool { weightRange != nil || stretchRange != nil }
    }

    /// One axis of a variable font, as the chooser shows it.
    struct VariationAxis: Equatable {
        let tag: String
        let name: String
        let range: ClosedRange<Double>
        let defaultValue: Double
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
                faces.append(FileFace(family: family, postScriptName: name, fileName: url.lastPathComponent, style: Self.style(of: descriptor)))
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
    /// also offered, in case the web view does not see fonts the user installed. A variable
    /// font is declared once per file and style, with its weight and width ranges, so the
    /// page's weights drive its axes.
    func faces(forFamily family: String) -> [FontFaceSource] {
        let files = fileFaces.filter { $0.family == family }
        if !files.isEmpty {
            SystemFontFiles.shared.replace(with: [:])
            var seenVariable: Set<String> = []
            return files.compactMap { face in
                let url = "/\(PageSchemeHandler.userPrefix)Fonts/\(Self.pathComponent(face.fileName))"
                // Named instances of a variable font share its file: declared once.
                if face.style.isVariable, !seenVariable.insert("\(face.fileName) \(face.style.italic)").inserted { return nil }
                return Self.source(url: url, style: face.style)
            }
        }
        var tokens: [String: URL] = [:]
        var seenVariable: Set<String> = []
        let faces = Self.members(ofFamily: family).enumerated().compactMap { index, member -> FontFaceSource? in
            let descriptor = CTFontDescriptorCreateWithNameAndSize(member.postScriptName as CFString, 0)
            let style = Self.style(of: descriptor)
            var url: String?
            let file = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL
            // A named instance of a font whose axes the page cannot drive would be served as the
            // file's default instance: such faces are asked for by name only.
            let instanceOnly = !style.isVariable && CTFontDescriptorCopyAttribute(descriptor, kCTFontVariationAxesAttribute) != nil
            if let file, !instanceOnly, ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
                let token = "\(index)-\(file.lastPathComponent)"
                tokens[token] = file
                url = "/\(PageSchemeHandler.userPrefix)SystemFonts/\(Self.pathComponent(token))"
            }
            if style.isVariable, let url, let file {
                // Named instances share one file: declared once, by URL, with its ranges.
                guard seenVariable.insert("\(file.path) \(style.italic)").inserted else { return nil }
                return Self.source(url: url, style: style)
            }
            return Self.source(postScriptName: member.postScriptName, url: url, style: style)
        }
        SystemFontFiles.shared.replace(with: tokens)
        return faces
    }

    /// A face of a family, as the font manager lists it ("Condensed Bold", "Light Italic").
    struct Member: Equatable {
        let postScriptName: String
        let displayName: String
    }

    /// The faces of a family: from the fonts folder if it was loaded there, else installed.
    func faceMembers(ofFamily family: String) -> [Member] {
        let files = fileFaces.filter { $0.family == family }
        if !files.isEmpty {
            return files.map { face in
                let font = CTFontCreateWithName(face.postScriptName as CFString, 0, nil)
                let style = CTFontCopyName(font, kCTFontStyleNameKey) as String? ?? face.postScriptName
                return Member(postScriptName: face.postScriptName, displayName: style)
            }
        }
        return Self.members(ofFamily: family)
    }

    private static func members(ofFamily family: String) -> [Member] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard let name = member.first as? String else { return nil }
            return Member(postScriptName: name, displayName: member.count > 1 ? (member[1] as? String ?? name) : name)
        }
    }

    private static func source(postScriptName: String? = nil, url: String?, style: FaceStyle) -> FontFaceSource {
        FontFaceSource(postScriptName: postScriptName, url: url, weight: style.weight, italic: style.italic,
                       stretch: style.stretch, weightRange: style.weightRange, stretchRange: style.stretchRange)
    }

    /// The variable axes of a face that the page can use, if it has any.
    static func variationAxes(ofFace postScriptName: String) -> [VariationAxis] {
        variationAxes(of: CTFontCreateWithName(postScriptName as CFString, 12, nil))
    }

    /// The axes of a font that the page can use. Weight and width axes are kept only on the
    /// CSS scales (`wght` 1–1000, `wdth` in percent), which they drive through `font-weight`
    /// and `font-stretch`; older Apple fonts such as Skia use other scales (`wght`
    /// 0.48–3.2), and for those the faces' own weights and widths are used instead.
    static func variationAxes(of font: CTFont) -> [VariationAxis] {
        let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] ?? []
        return axes.compactMap { axis in
            guard let identifier = (axis[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value,
                  let minimum = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
                  let maximum = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue, minimum < maximum else { return nil }
            let tag = FontChoiceConversion.tag(identifier)
            let defaultValue = (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue ?? minimum
            let name = axis[kCTFontVariationAxisNameKey] as? String ?? tag
            switch tag {
            case "wght" where minimum < 1 || maximum > 1000 || maximum <= 10: return nil
            case "wdth" where !CustomFontCSS.isCSSWidthAxis(minimum...maximum): return nil
            default: return VariationAxis(tag: tag, name: name, range: minimum...maximum, defaultValue: defaultValue)
            }
        }
    }

    /// A font to preview a family in, at the given size.
    static func previewFont(family: String, size: CGFloat) -> NSFont? {
        NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
    }

    /// Weight, width and style of a face, in CSS terms, with axis ranges for variable fonts.
    static func style(of descriptor: CTFontDescriptor) -> FaceStyle {
        let traits = CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [CFString: Any] ?? [:]
        let weight = (traits[kCTFontWeightTrait] as? NSNumber)?.doubleValue ?? 0
        let width = (traits[kCTFontWidthTrait] as? NSNumber)?.doubleValue ?? 0
        let symbolic = (traits[kCTFontSymbolicTrait] as? NSNumber)?.uint32Value ?? 0
        var style = FaceStyle(weight: CustomFontCSS.exactWeight(fromTrait: weight),
                              italic: symbolic & CTFontSymbolicTraits.traitItalic.rawValue != 0,
                              stretch: CustomFontCSS.stretch(fromWidthTrait: width))
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        if let width = rawWidthAxis(of: font) {
            style.stretch = CustomFontCSS.stretch(fromWidthAxisValue: width.value, range: width.range)
        }
        for axis in variationAxes(of: font) {
            switch axis.tag {
            case "wght": style.weightRange = axis.range
            case "wdth": style.stretchRange = axis.range
            default: break
            }
        }
        return style
    }

    /// The value and range of a width axis that is not on the CSS scale, if the font has one.
    private static func rawWidthAxis(of font: CTFont) -> (value: Double, range: ClosedRange<Double>)? {
        let axes = CTFontCopyVariationAxes(font) as? [[CFString: Any]] ?? []
        guard let identifier = FontChoiceConversion.identifier("wdth"),
              let axis = axes.first(where: { ($0[kCTFontVariationAxisIdentifierKey] as? NSNumber)?.uint32Value == identifier }),
              let minimum = (axis[kCTFontVariationAxisMinimumValueKey] as? NSNumber)?.doubleValue,
              let maximum = (axis[kCTFontVariationAxisMaximumValueKey] as? NSNumber)?.doubleValue, minimum < maximum,
              !CustomFontCSS.isCSSWidthAxis(minimum...maximum) else { return nil }
        let values = CTFontCopyVariation(font) as? [NSNumber: NSNumber] ?? [:]
        let defaultValue = (axis[kCTFontVariationAxisDefaultValueKey] as? NSNumber)?.doubleValue ?? 1
        return (values[NSNumber(value: identifier)]?.doubleValue ?? defaultValue, minimum...maximum)
    }

    private static func pathComponent(_ name: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#;")
        return name.addingPercentEncoding(withAllowedCharacters: allowed) ?? name
    }
}
