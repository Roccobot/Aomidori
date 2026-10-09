import AppKit
import AomidoriCore
import CoreText

/// Between AppKit fonts (what the Font panel and the chooser deal in) and `CustomFontChoice`
/// (what the page gets as CSS).
@MainActor
enum FontChoiceConversion {
    /// The four-letter tag of a variation axis or feature identifier (`0x77676874` → `wght`).
    nonisolated static func tag(_ identifier: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((identifier >> $0) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated static func identifier(_ tag: String) -> UInt32? {
        let bytes = Array(tag.utf8)
        guard bytes.count == 4 else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// The choice an AppKit font stands for: its family and face, the face's weight, width and
    /// style, its variation values, and the Typography features set on its descriptor.
    /// `unknownFeatures` lists features with no OpenType equivalent, which are left out.
    static func choice(from font: NSFont) -> (choice: CustomFontChoice, unknownFeatures: [String]) {
        let descriptor = font.fontDescriptor as CTFontDescriptor
        let style = CustomFonts.style(of: descriptor)
        var weight: Double = style.weight
        var stretch: Double? = style.stretch == 100 ? nil : style.stretch
        var variations: [String: Double] = [:]
        let usable = Set(CustomFonts.variationAxes(of: font as CTFont).map(\.tag))
        let values = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber] ?? [:]
        for (identifier, value) in values {
            let axis = tag(identifier.uint32Value)
            guard usable.contains(axis) else { continue }
            switch axis {
            case "wght": weight = value.doubleValue
            case "wdth": stretch = value.doubleValue == 100 ? nil : value.doubleValue
            default: variations[axis] = value.doubleValue
            }
        }
        let (features, unknown) = features(of: font)
        let choice = CustomFontChoice(family: font.familyName ?? font.fontName, faceName: font.fontName, weight: weight,
                                      italic: style.italic, stretch: stretch, variations: variations, features: features)
        return (choice, unknown)
    }

    /// OpenType features of a font: OpenType entries as they are, Apple (AAT) type and selector
    /// pairs through `OpenTypeFeatures`. The descriptor's settings come first (what the Font
    /// panel set); Core Text's effective settings fill in when the descriptor has none.
    static func features(of font: NSFont) -> (features: [String: Int], unknown: [String]) {
        // Bridged with plain string keys: the Core Text and AppKit key constants are strings.
        var settings = font.fontDescriptor.object(forKey: .featureSettings) as? [[String: Any]] ?? []
        if settings.isEmpty {
            settings = CTFontCopyFeatureSettings(font as CTFont) as? [[String: Any]] ?? []
        }
        let typeKey = NSFontDescriptor.FeatureKey.typeIdentifier.rawValue
        let selectorKey = NSFontDescriptor.FeatureKey.selectorIdentifier.rawValue
        var features: [String: Int] = [:]
        var unknown: [String] = []
        for setting in settings {
            if let tag = setting[kCTFontOpenTypeFeatureTag as String] as? String {
                features[tag] = (setting[kCTFontOpenTypeFeatureValue as String] as? NSNumber)?.intValue ?? 1
            } else if let type = (setting[typeKey] as? NSNumber)?.intValue,
                      let selector = (setting[selectorKey] as? NSNumber)?.intValue {
                if let mapped = OpenTypeFeatures.tag(type: type, selector: selector) {
                    features[mapped.tag] = mapped.value
                } else {
                    unknown.append("\(type):\(selector)")
                }
            }
        }
        return (features, unknown)
    }

    /// An AppKit font showing a choice, to preview it and to select it in the Font panel.
    static func font(for choice: CustomFontChoice, size: CGFloat) -> NSFont? {
        var base = choice.faceName.flatMap { NSFont(name: $0, size: size) }
            ?? NSFontManager.shared.font(withFamily: choice.family, traits: choice.italic ? .italicFontMask : [],
                                         weight: 5, size: size)
        guard let font = base else { return nil }
        var attributes: [NSFontDescriptor.AttributeName: Any] = [:]
        var variation: [NSNumber: Double] = [:]
        for (tag, value) in choice.variations {
            if let identifier = identifier(tag) { variation[NSNumber(value: identifier)] = value }
        }
        let style = CustomFonts.style(of: font.fontDescriptor as CTFontDescriptor)
        if let weight = choice.weight, style.weightRange != nil, let identifier = identifier("wght") {
            variation[NSNumber(value: identifier)] = weight
        }
        if style.stretchRange != nil, let identifier = identifier("wdth") {
            variation[NSNumber(value: identifier)] = choice.stretch ?? 100
        }
        if !variation.isEmpty { attributes[.variation] = variation }
        if !choice.features.isEmpty {
            attributes[.featureSettings] = choice.features.sorted { $0.key < $1.key }.map { tag, value in
                [kCTFontOpenTypeFeatureTag as String: tag, kCTFontOpenTypeFeatureValue as String: value] as [String: Any]
            }
        }
        if !attributes.isEmpty {
            base = NSFont(descriptor: font.fontDescriptor.addingAttributes(attributes), size: size)
        }
        return base ?? font
    }

    /// "Avenir Next Condensed Demi Bold", for menus.
    static func displayName(of choice: CustomFontChoice) -> String {
        guard let face = choice.faceName, let font = NSFont(name: face, size: 12),
              let name = font.displayName, !name.isEmpty else { return choice.family }
        return name
    }
}
