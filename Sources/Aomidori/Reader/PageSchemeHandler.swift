import EPUBKit
import Foundation
import WebKit

/// Supplies the documents a `PageRenderer` shows, by container-relative path.
protocol PageResourceProvider: Sendable {
    func resource(at path: String) throws -> EPUBResource
}

extension EPUBPublication: PageResourceProvider {}

/// Serves `aomidori://<host>/<path>` requests.
///
/// - `/<path>`: a resource of the open book, read lazily from the archive off the main thread.
/// - `/.aomidori/Styles/<file>` and `/.aomidori/Fonts/<file>`: the user's styles and fonts folders,
///   so a user style's relative URLs (`../Fonts/MiSans-Regular.otf`) resolve next to it.
/// - `/.aomidori/SystemFonts/<token>`: the files of the installed family chosen as custom font
///   (see `SystemFontFiles`); nothing else on disk is reachable.
@MainActor
final class PageSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated static let scheme = "aomidori"
    nonisolated static let userPrefix = ".aomidori/"
    nonisolated private static let userFolders: Set<String> = ["Styles", "Fonts"]

    let host: String
    private let provider: any PageResourceProvider
    private var running: Set<ObjectIdentifier> = []

    init(host: String, provider: any PageResourceProvider) {
        self.host = host
        self.provider = provider
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.host()?.lowercased() == host else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let path = String(url.path(percentEncoded: false).drop { $0 == "/" })
        let id = ObjectIdentifier(task)
        running.insert(id)
        let provider = provider
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try Self.load(path, from: provider) }
            }.value
            // The web view may have cancelled the request meanwhile.
            guard running.remove(id) != nil else { return }
            switch result {
            case .success(let resource):
                task.didReceive(Self.response(for: url, status: 200, resource: resource))
                task.didReceive(resource.data)
            case .failure:
                task.didReceive(Self.response(for: url, status: 404, resource: nil))
            }
            task.didFinish()
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        running.remove(ObjectIdentifier(task))
    }

    nonisolated private static func load(_ path: String, from provider: any PageResourceProvider) throws -> EPUBResource {
        guard path.hasPrefix(userPrefix) else { return try provider.resource(at: path) }
        let components = path.dropFirst(userPrefix.count).split(separator: "/").map(String.init)
        if components.count == 2, components[0] == "SystemFonts" {
            guard let url = SystemFontFiles.shared.url(forToken: components[1]) else { throw EPUBError.missingResource(path: path) }
            return EPUBResource(data: try Data(contentsOf: url), mediaType: MediaType.forPath(url.path))
        }
        guard components.count >= 2, userFolders.contains(components[0]),
              !components.contains(where: { $0 == ".." || $0 == "." }) else {
            throw EPUBError.missingResource(path: path)
        }
        let url = components.reduce(AppPaths.support) { $0.appendingPathComponent($1) }
        return EPUBResource(data: try Data(contentsOf: url), mediaType: MediaType.forPath(path))
    }

    nonisolated private static func response(for url: URL, status: Int, resource: EPUBResource?) -> HTTPURLResponse {
        var headers = ["Cache-Control": "no-cache", "Content-Length": "\(resource?.data.count ?? 0)"]
        if let resource {
            // CSS without @charset would otherwise inherit the document's encoding guess.
            headers["Content-Type"] = resource.mediaType == "text/css" ? "text/css; charset=utf-8" : resource.mediaType
        }
        return HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
}
