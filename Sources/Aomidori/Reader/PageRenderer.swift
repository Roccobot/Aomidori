import Foundation
import AomidoriCore
import WebKit

/// One web view showing one document at a time, with the reader's style layers.
///
/// This is the reusable rendering layer: the reader window uses it for books, the CSS
/// Playground drives it with a different `PageResourceProvider`.
@MainActor
final class PageRenderer: NSObject {
    let webView: WKWebView
    /// Unique per renderer, so caches and origins never mix two books.
    let host: String
    private let userContent = WKUserContentController()
    private let messageProxy = ScriptMessageProxy()
    private(set) var configuration: ReaderConfiguration
    /// Set once the offline rules are in place; a load asked for before waits here.
    private var rulesReady = false
    private var pendingLoad: URLRequest?

    /// Called with the document's path and position after the reader stops scrolling. The path
    /// says which document it was: a report may arrive after the next one has started loading.
    var onPosition: ((_ path: String, _ position: ChapterPosition) -> Void)?
    /// Called when the document's ability to scroll further up or down changes.
    var onEdges: ((_ path: String, _ edges: ScrollEdges) -> Void)?

    init(provider: any PageResourceProvider, configuration: ReaderConfiguration) {
        let host = UUID().uuidString.lowercased()
        self.host = host
        self.configuration = configuration

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.setURLSchemeHandler(PageSchemeHandler(host: host, provider: provider), forURLScheme: PageSchemeHandler.scheme)
        if ReaderSmokeTest.isActive {
            webConfiguration.setURLSchemeHandler(OfflineProbe.shared, forURLScheme: OfflineProbe.scheme)
        }
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
        OfflineRules.whenReady { [weak self] rules in
            guard let self else { return }
            if let rules { userContent.add(rules) }
            rulesReady = true
            if let request = pendingLoad {
                pendingLoad = nil
                webView.load(request)
            }
        }
    }

    /// Every load goes through here, so no page is shown before the offline rules apply.
    private func load(_ request: URLRequest) {
        if rulesReady { webView.load(request) } else { pendingLoad = request }
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
        load(URLRequest(url: url(forPath: path, fragment: fragment)))
    }

    /// Loads a document again, bypassing WebKit's caches, so the page and its own resources
    /// (the book's CSS, pictures, fonts) are read from the book anew.
    func reload(path: String) {
        load(URLRequest(url: url(forPath: path), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
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

    /// Where the page was when a link was last clicked (once: reading it clears it).
    func takeLinkDeparture() async -> ChapterPosition? {
        let value = try? await webView.callAsyncJavaScript(
            "return window.Aomidori ? Aomidori.takeLinkDeparture() : null", arguments: [:], in: nil, contentWorld: .defaultClient)
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
        case "edges":
            guard let href = message["href"] as? String, let path = path(for: URL(string: href)),
                  let atTop = message["atTop"] as? Bool, let atBottom = message["atBottom"] as? Bool else { return }
            onEdges?(path, ScrollEdges(atTop: atTop, atBottom: atBottom))
        default:
            break
        }
    }
}

/// Keeps every page offline: a book (or a style) may name pictures, sheets or fonts on the web,
/// and loading them would tell a server when and where the book is read. Only the renderer's
/// own scheme and inline `data:` and `blob:` resources load; links the reader clicks are not
/// loads and still open in the browser. Compiled once per launch, shared by every renderer.
@MainActor
enum OfflineRules {
    static let identifier = "AomidoriOffline"
    /// Content-blocker URL filters have no alternation (`a|b`): one exception per scheme.
    static let source: String = {
        let allowed = [PageSchemeHandler.scheme, "data", "blob", "about"].map {
            #"{"trigger": {"url-filter": "^\#($0):"}, "action": {"type": "ignore-previous-rules"}}"#
        }
        return "[" + ([#"{"trigger": {"url-filter": ".*"}, "action": {"type": "block"}}"#] + allowed).joined(separator: ",\n") + "]"
    }()

    private enum State { case idle, compiling, done(WKContentRuleList?) }
    private static var state = State.idle
    private static var waiting: [(WKContentRuleList?) -> Void] = []

    /// Calls `body` with the compiled rules once they exist; with `nil` if compiling failed,
    /// so a page is never held back forever.
    static func whenReady(_ body: @escaping (WKContentRuleList?) -> Void) {
        if case .done(let rules) = state { return body(rules) }
        waiting.append(body)
        guard case .idle = state else { return }
        state = .compiling
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: source) { rules, error in
            MainActor.assumeIsolated {
                if let error { NSLog("Aomidori: offline rules not compiled: \(error)") }
                state = .done(rules)
                let callbacks = waiting
                waiting = []
                callbacks.forEach { $0(rules) }
            }
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
