import Foundation

/// MIME types for publication resources.
public enum MediaType {
    public static let xhtml = "application/xhtml+xml"
    public static let ncx = "application/x-dtbncx+xml"
    public static let package = "application/oebps-package+xml"

    /// A MIME type inferred from the file extension, for resources the manifest does not list.
    public static func forPath(_ path: String) -> String {
        let ext = path.split(separator: ".").last.map { $0.lowercased() } ?? ""
        return byExtension[ext] ?? "application/octet-stream"
    }

    /// Normalises legacy or non-standard manifest types that WebKit would not recognise.
    public static func normalized(_ declared: String, path: String) -> String {
        let type = declared.trimmingCharacters(in: .whitespaces).lowercased()
        if type.isEmpty || type == "application/octet-stream" { return forPath(path) }
        return aliases[type] ?? type
    }

    private static let aliases: [String: String] = [
        "text/x-oeb1-document": "text/html",
        "application/x-font-ttf": "font/ttf",
        "application/x-font-truetype": "font/ttf",
        "application/x-font-opentype": "font/otf",
        "application/vnd.ms-opentype": "font/otf",
        "application/font-woff": "font/woff",
        "application/x-font-woff": "font/woff",
        "application/font-sfnt": "font/ttf",
    ]

    private static let byExtension: [String: String] = [
        "xhtml": xhtml, "xht": xhtml, "html": "text/html", "htm": "text/html",
        "xml": "application/xml", "opf": package, "ncx": ncx,
        "css": "text/css", "js": "text/javascript",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif",
        "webp": "image/webp", "avif": "image/avif", "svg": "image/svg+xml", "svgz": "image/svg+xml",
        "otf": "font/otf", "ttf": "font/ttf", "woff": "font/woff", "woff2": "font/woff2",
        "mp3": "audio/mpeg", "m4a": "audio/mp4", "mp4": "video/mp4", "webm": "video/webm",
        "smil": "application/smil+xml", "pls": "application/pls+xml",
    ]
}
