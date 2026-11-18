import Observation
import SwiftUI
import WebKit

/// Eén WKWebView voor de hele app, met de LearnHarness-UI van de server.
///
/// Waarom één gedeelde instantie: op de iPhone Duo wisselt de split view tussen één kolom
/// (buitenscherm) en twee kolommen (binnenscherm). SwiftUI maakt de detailkolom daarbij opnieuw;
/// zou de WebView daarin leven, dan begon de les opnieuw te laden. Apple: "Keep functionality and
/// the state of elements the same between displays."
///
/// Native rondom de les (zie MainView): sessielijst, titel, toolbars. De pagina meldt route,
/// thema en wijzigingen via bridge.js; de app stuurt acties terug via kleine JS-functies.
@MainActor @Observable
final class WebStore {
    struct Chat: Decodable, Identifiable, Hashable, Sendable {
        let id: String
        var title: String
        let kind: String?
        let phase: String?
        let updatedAt: String?
        let busy: Bool?
        let pendingQuestion: Bool?
        let pendingProblem: Bool?
        var isPractice: Bool { kind == "practice" }
        var updated: Date? { updatedAt.flatMap { ISO8601DateFormatter.lh.date(from: $0) } }
    }

    let serverURL: URL
    let web: WKWebView
    private let coordinator: WebCoordinator

    private(set) var chats: [Chat] = []
    private(set) var path = "/"
    private(set) var planAvailable = false
    var theme = LHTheme.default
    var loadError: String?
    var loadedOnce = false

    /// Huidige sessie volgens de URL van de pagina (`/chat/<id>`).
    var currentChatId: String? {
        guard path.hasPrefix("/chat/") else { return nil }
        let id = String(path.dropFirst("/chat/".count))
        return id == "new" || id.isEmpty ? nil : id
    }

    init(serverURL: URL, onAuthRequired: @escaping @MainActor () -> Void) {
        self.serverURL = serverURL
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let ucc = config.userContentController
        // Alleen op de eigen server. Tabbladen uit window.open (aanmelden bij ChatGPT e.d.) delen
        // deze configuratie; zonder deze grens draaiden bridge.js en mobile.js ook op de pagina van
        // OpenAI, die dan route en thema van de app overschreef.
        let origin = Self.origin(of: serverURL)
        for name in ["bridge", "mobile"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "js"),
               let src = try? String(contentsOf: url, encoding: .utf8) {
                let guarded = "if (location.origin === \(Self.jsString(origin))) {\n\(src)\n}"
                ucc.addUserScript(WKUserScript(source: guarded, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
        let view = LHWebView(frame: .zero, configuration: config)
        web = view
        coordinator = WebCoordinator(serverURL: serverURL, onAuthRequired: onAuthRequired)
        coordinator.store = self
        ucc.add(coordinator, name: "lhNative")
        web.navigationDelegate = coordinator
        web.uiDelegate = coordinator
        web.isOpaque = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.isInspectable = true // Safari → Ontwikkel, voor foutzoeken
        coordinator.web = web
        // Andere breedte (Duo open/dicht, lijst in- of uitgeklapt): viewport voor de zoom bijwerken.
        view.onWidthChange = { [weak self] in self?.applyZoom() }
        applyThemeToWebView()
        web.load(URLRequest(url: serverURL))
    }

    nonisolated static func origin(of url: URL) -> String {
        var c = URLComponents()
        c.scheme = url.scheme; c.host = url.host(); c.port = url.port
        return c.string ?? ""
    }

    nonisolated static func jsString(_ s: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8)).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    // MARK: Navigatie

    /// Naar een pad in de UI. Next.js heeft geen publieke router-API van buitenaf, dus een gewone
    /// navigatie; de rest van de app blijft staan.
    func open(path newPath: String) {
        guard newPath != path else { return }
        path = newPath
        web.load(URLRequest(url: serverURL.appending(path: String(newPath.dropFirst()))))
    }

    func openChat(_ id: String) { open(path: "/chat/\(id)") }
    func openHome() { open(path: "/") }
    func newSession(practice: Bool) { open(path: practice ? "/chat/new?mode=practice" : "/chat/new") }
    func reload() { loadError = nil; web.reload() }

    // MARK: Zoom (op de Mac: ⌘+ / ⌘− / ⌘0 in Electron)

    /// Zelfde stappen als Chromium/Electron, zodat de UI op beide even groot kan staan.
    /// `WKWebView.pageZoom` deed op iOS niets zichtbaars; zie `applyZoom`.
    nonisolated static let zoomSteps: [Double] = [0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    private static let zoomKey = "LHPageZoom"

    var zoom: Double = UserDefaults.standard.object(forKey: "LHPageZoom") as? Double ?? 1.0 {
        didSet {
            applyZoom()
            UserDefaults.standard.set(zoom, forKey: Self.zoomKey)
        }
    }

    var canZoomIn: Bool { zoom < (Self.zoomSteps.last ?? 2) - 0.001 }
    var canZoomOut: Bool { zoom > (Self.zoomSteps.first ?? 0.5) + 0.001 }

    func zoomIn() { if let next = Self.zoomSteps.first(where: { $0 > zoom + 0.001 }) { zoom = next } }
    func zoomOut() { if let prev = Self.zoomSteps.last(where: { $0 < zoom - 0.001 }) { zoom = prev } }
    func resetZoom() { zoom = 1.0 }

    /// Bij elke nieuwe pagina opnieuw (WebCoordinator, didCommit); binnen de app blijft het staan.
    func applyZoom() {
        // Via de viewport in mobile.js (zie daar waarom). Breedte in punten = CSS-pixels bij zoom 1.
        run("window.__lhSetZoom && window.__lhSetZoom(\(zoom), \(Int(web.bounds.width)))")
    }

    // Acties in de pagina (zie bridge.js).
    func openSettings() { run("window.__lhOpenSettings && window.__lhOpenSettings()") }
    func openBackgroundAgents() { run("window.__lhClickSidebar && window.__lhClickSidebar(/background agents/i)") }
    func openPlan() { run("document.querySelector('[data-testid=\"plan-chip\"]')?.click()") }

    private func run(_ js: String) { web.evaluateJavaScript(js) { _, _ in } }

    // MARK: Sessies (zelfde API als de UI; fetch in de pagina, dus met de login van de pagina)

    func refreshChats() async {
        do {
            let result = try await web.callAsyncJavaScript(
                "const r = await fetch('/api/chats', {headers: {Accept: 'application/json'}}); if (!r.ok) throw new Error('HTTP ' + r.status); return await r.text();",
                contentWorld: .page)
            guard let text = result as? String, let data = text.data(using: .utf8) else { return }
            struct List: Decodable { let chats: [Chat] }
            let list = try JSONDecoder().decode(List.self, from: data)
            chats = list.chats.sorted { ($0.updated ?? .distantPast) > ($1.updated ?? .distantPast) }
        } catch {
            // De pagina is nog niet geladen of de sessie is verlopen; de navigatie vangt dat op.
        }
    }

    func rename(_ id: String, to title: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["title": title])
        _ = try? await web.callAsyncJavaScript(
            "await fetch('/api/chats/' + id, {method: 'PUT', headers: {'Content-Type': 'application/json'}, body});",
            arguments: ["id": id, "body": String(decoding: body ?? Data(), as: UTF8.self)], contentWorld: .page)
        await refreshChats()
    }

    /// Verwijderen zoals de UI: `preserve-graph` laat de kennisgraaf staan, `delete-nodes` haalt de
    /// nodes uit deze sessie weg. 409 = er loopt nog werk.
    func delete(_ id: String, keepGraph: Bool) async -> String? {
        let mode = keepGraph ? "preserve-graph" : "delete-nodes"
        let result = try? await web.callAsyncJavaScript(
            "const r = await fetch('/api/chats/' + id + '?mode=' + mode, {method: 'DELETE'}); return r.status;",
            arguments: ["id": id, "mode": mode], contentWorld: .page)
        await refreshChats()
        if currentChatId == id { openHome() }
        switch (result as? Int) ?? 0 {
        case 200: return nil
        case 409: return String(localized: "A turn or background task is still running in this session.")
        default: return String(localized: "Couldn’t delete the session.")
        }
    }

    /// Zelfde als "Export as Markdown…" in het sessiemenu op de Mac: de server stuurt een bestand,
    /// de download komt in het deelmenu.
    func exportMarkdown(_ id: String) {
        guard let url = URL(string: "/api/chats/\(id)/markdown", relativeTo: web.url) else { return }
        let delegate = coordinator
        web.startDownload(using: URLRequest(url: url)) { d in d.delegate = delegate }
    }

    /// "Extract" uit het sessiemenu op de Mac: de rest van de sessie in de kennisgraaf zetten.
    /// 202 = gestart, 409 = loopt al (ook goed).
    func extract(_ id: String) async -> String? {
        let result = try? await web.callAsyncJavaScript(
            "const r = await fetch('/api/graph/coverage/extract', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({chatId: id})}); return r.status;",
            arguments: ["id": id], contentWorld: .page)
        switch (result as? Int) ?? 0 {
        case 200..<300, 409: return nil
        default: return String(localized: "Couldn’t start extraction.")
        }
    }

    // MARK: Van de pagina (WebCoordinator)

    fileprivate func pageRoute(_ newPath: String, planAvailable: Bool) {
        path = newPath
        self.planAvailable = planAvailable
    }

    fileprivate func pageTheme(_ theme: LHTheme) {
        self.theme = theme
        applyThemeToWebView()
    }

    private func applyThemeToWebView() {
        let bg = UIColor(theme.background)
        web.backgroundColor = bg
        web.scrollView.backgroundColor = bg
        web.underPageBackgroundColor = bg
    }
}

/// Navigatie, dialogen, downloads en berichten van de pagina.
@MainActor
final class WebCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    weak var store: WebStore?
    weak var web: WKWebView?
    private let serverURL: URL
    private let onAuthRequired: @MainActor () -> Void
    private var downloadURLs: [ObjectIdentifier: URL] = [:]
    private var attachmentPicker: AttachmentPicker?
    private var folderUploader: FolderUploader?

    init(serverURL: URL, onAuthRequired: @escaping @MainActor () -> Void) {
        self.serverURL = serverURL
        self.onAuthRequired = onAuthRequired
    }

    private var host: String? { serverURL.host() }

    /// Open een externe link in Safari, via de scene van deze WebView (geen globale toestand).
    private func openExternally(_ url: URL) {
        web?.window?.windowScene?.open(url, options: nil, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if action.shouldPerformDownload { return .download }
        if ["blob", "data", "about"].contains(url.scheme ?? "") { return .allow }
        // Authelia stuurt een verlopen sessie naar /auth: dan het native loginscherm.
        if url.host() == host, url.path().hasPrefix("/auth"), action.targetFrame?.isMainFrame == true {
            onAuthRequired()
            return .cancel
        }
        // Andere sites (bronnen, documentatie): in Safari, niet in de app.
        if url.host() != host, action.targetFrame?.isMainFrame != false, ["http", "https"].contains(url.scheme ?? "") {
            openExternally(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if let http = response.response as? HTTPURLResponse,
           let disposition = http.value(forHTTPHeaderField: "Content-Disposition"), disposition.lowercased().hasPrefix("attachment") {
            return .download
        }
        return response.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === web { store?.applyZoom() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // didCommit kan vóór mobile.js vallen; hier staat __lhSetZoom zeker klaar.
        if webView === web { store?.applyZoom() }
        store?.loadError = nil
        store?.loadedOnce = true
        Task { await store?.refreshChats() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        store?.loadError = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // window.open() van de pagina zelf (leeg of eigen server): een echt tabblad als sheet, met
        // dezelfde configuratie en dus dezelfde login. Nodig voor Settings → Providers → Connect
        // (ChatGPT, Copilot, Grok): upstream opent eerst about:blank en stuurt dat tabblad daarna naar
        // de aanmeldpagina. Zonder tabblad gaf dat "Allow a sign-in tab to open".
        let url = action.request.url
        if url == nil || url?.scheme == "about" || url?.host() == host {
            let popup = PopupWebViewController(configuration: configuration)
            present(UINavigationController(rootViewController: popup))
            return popup.web
        }
        if let url { openExternally(url) }
        return nil
    }

    // Microfoon voor dicteren, alleen voor de eigen server.
    func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                 initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        origin.host == host ? .grant : .deny
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { cont in
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in cont.resume(returning: false) })
            a.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in cont.resume(returning: true) })
            present(a)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            a.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in cont.resume() })
            present(a)
        }
    }

    func topController() -> UIViewController? {
        var top = web?.window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    private func present(_ vc: UIViewController) { topController()?.present(vc, animated: true) }

    // MARK: Downloads (markdown-export van een sessie)

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: suggestedFilename)
        downloadURLs[ObjectIdentifier(download)] = url
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadURLs.removeValue(forKey: ObjectIdentifier(download)), let web else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = web
        share.popoverPresentationController?.sourceRect = CGRect(x: web.bounds.midX, y: web.bounds.midY, width: 1, height: 1)
        present(share)
    }

    // MARK: Berichten van bridge.js

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        // Alleen berichten van de eigen pagina in de eigen WebView (niet van een aanmeldtabblad).
        guard message.webView === web, message.frameInfo.securityOrigin.host == host,
              let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
        switch kind {
        case "route":
            store?.pageRoute(body["path"] as? String ?? "/", planAvailable: body["plan"] as? Bool ?? false)
        case "theme":
            if let vars = body["vars"] as? [String: String] { store?.pageTheme(LHTheme(cssVars: vars)) }
        case "chatsChanged":
            Task { await store?.refreshChats() }
        case "uploadFailed":
            let name = body["name"] as? String ?? String(localized: "file")
            let reason = body["error"] as? String ?? String(localized: "unknown error")
            let a = UIAlertController(title: String(localized: "Attachment not uploaded"),
                                      message: String(localized: "\(name): \(reason). The agent can’t read this file; please add it again."),
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
            present(a)
        case "pickFiles":
            guard let web, let id = body["id"] as? String else { return }
            let rect = CGRect(x: body["x"] as? Double ?? 0, y: body["y"] as? Double ?? 0,
                              width: max(body["w"] as? Double ?? 1, 1), height: max(body["h"] as? Double ?? 1, 1))
            let picker = AttachmentPicker(web: web) { [weak self] in self?.topController() }
            attachmentPicker = picker
            picker.start(requestId: id, multiple: body["multiple"] as? Bool ?? true, directory: body["directory"] as? Bool ?? false,
                         accept: body["accept"] as? String ?? "", sourceRect: rect)
        case "pickFolder":
            guard let web, let id = body["id"] as? String else { return }
            let uploader = FolderUploader(web: web) { [weak self] in self?.topController() }
            folderUploader = uploader
            uploader.start(requestId: id)
        default:
            break
        }
    }
}

/// De WebView in de detailkolom; altijd dezelfde instantie uit WebStore.
struct WebContainer: UIViewRepresentable {
    let store: WebStore
    func makeUIView(context: Context) -> WKWebView { store.web }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        // Niet opruimen: de WebView leeft in WebStore en komt terug in de volgende kolom.
        uiView.removeFromSuperview()
    }
}

/// WKWebView die meldt als zijn breedte verandert; nodig voor de zoom (viewportbreedte = breedte/zoom).
final class LHWebView: WKWebView {
    var onWidthChange: (() -> Void)?
    private var lastWidth: CGFloat = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastWidth) > 0.5 {
            lastWidth = bounds.width
            onWidthChange?()
        }
    }
}
