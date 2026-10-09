import Foundation
import AomidoriCore
import WebKit

/// One web view showing one document at a time, with the reader's style layers.
///
/// This is the reusable rendering layer: the reader window uses it for books, the future
/// CSS Playground can drive it with a different `PageResourceProvider`.
@MainActor
final class PageRenderer: NSObject {
    let webView: WKWebView
    /// Unique per renderer, so caches and origins never mix two books.
    let host: String
    private let userContent = WKUserContentController()
    private let messageProxy = ScriptMessageProxy()
    private(set) var configuration: ReaderConfiguration

    /// Called with the document's path and position after the reader stops scrolling. The path
    /// says which document it was: a report may arrive after the next one has started loading.
    var onPosition: ((_ path: String, _ position: ChapterPosition) -> Void)?

    init(provider: any PageResourceProvider, configuration: ReaderConfiguration) {
        let host = UUID().uuidString.lowercased()
        self.host = host
        self.configuration = configuration

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.setURLSchemeHandler(PageSchemeHandler(host: host, provider: provider), forURLScheme: PageSchemeHandler.scheme)
        // Nothing is written to disk; every window starts clean.
        webConfiguration.websiteDataStore = .nonPersistent()
        // Book scripts never run. The reader's own script lives in an isolated world and still does.
        webConfiguration.defaultWebpagePreferences.allowsContentJavaScript = false
        webConfiguration.mediaTypesRequiringUserActionForPlayback = .all
        webConfiguration.userContentController = userContent

        webView = WKWebView(frame: .zero, configuration: webConfiguration)
        // Pinch never scales the page; text size is the reader's own setting.
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        super.init()

        messageProxy.renderer = self
        userContent.add(messageProxy, contentWorld: .defaultClient, name: ReaderScript.messageHandlerName)
        installScript()
    }

    /// The URL of a container-relative path, with an optional fragment.
    func url(forPath path: String, fragment: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = PageSchemeHandler.scheme
        components.host = host
        components.path = "/" + path
        components.fragment = fragment
        return components.url!
    }

    /// The container-relative path of a URL served by this renderer, or `nil` for any other URL.
    func path(for url: URL?) -> String? {
        guard let url, url.scheme == PageSchemeHandler.scheme, url.host()?.lowercased() == host else { return nil }
        return String(url.path(percentEncoded: false).drop { $0 == "/" })
    }

    func load(path: String, fragment: String? = nil) {
        webView.load(URLRequest(url: url(forPath: path, fragment: fragment)))
    }

    /// Applies a new configuration to the current document without reloading it, and to every
    /// document loaded afterwards.
    func update(_ configuration: ReaderConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        installScript()
        webView.evaluateJavaScript(ReaderScript.applyCall(configuration), in: nil, in: .defaultClient)
    }

    func scroll(toFraction fraction: Double) {
        webView.evaluateJavaScript("window.Aomidori && Aomidori.scrollToFraction(\(fraction))", in: nil, in: .defaultClient)
    }

    /// Scrolls the current document to a saved position (element anchor first, then fraction).
    func restore(_ position: ChapterPosition) {
        guard let data = try? JSONEncoder().encode(position), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.Aomidori && Aomidori.restorePosition(\(json))", in: nil, in: .defaultClient)
    }

    /// The current document's position, read from the page now.
    func currentPosition() async -> ChapterPosition? {
        let value = try? await webView.callAsyncJavaScript(
            "return window.Aomidori ? Aomidori.position() : null", arguments: [:], in: nil, contentWorld: .defaultClient)
        return Self.chapterPosition(from: value as? [String: Any])
    }

    private static func chapterPosition(from message: [String: Any]?) -> ChapterPosition? {
        guard let message, let fraction = (message["fraction"] as? NSNumber)?.doubleValue else { return nil }
        return ChapterPosition(fraction: fraction, anchor: message["anchor"] as? String)
    }

    private func installScript() {
        userContent.removeAllUserScripts()
        userContent.addUserScript(WKUserScript(
            source: ReaderScript.source(configuration: configuration),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .defaultClient
        ))
    }

    fileprivate func didReceive(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "position":
            guard let href = message["href"] as? String, let path = path(for: URL(string: href)),
                  let position = Self.chapterPosition(from: message) else { return }
            onPosition?(path, position)
        default:
            break
        }
    }
}

/// Breaks the retain cycle between the user content controller and the renderer.
@MainActor
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var renderer: PageRenderer?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        renderer?.didReceive(message.body)
    }
}
