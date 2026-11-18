import UIKit
import WebKit

/// Een tabblad dat de pagina zelf opent met `window.open` (aanmelden bij ChatGPT, Copilot of Grok
/// in Settings → Providers). Zelfde WebView-configuratie als de app, dus dezelfde login bij de
/// server; ook andere sites (de aanmeldpagina van de provider) blijven hierin, zoals in een tabblad
/// op de Mac. `window.close()` of Gereed sluit het.
@MainActor
final class PopupWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView

    init(configuration: WKWebViewConfiguration) {
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is niet in gebruik") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(web)
        web.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { [weak self] _ in self?.close() })
        observation = web.observe(\.title, options: [.initial, .new]) { [weak self] web, _ in
            let title = web.title
            Task { @MainActor in self?.navigationItem.title = title }
        }
    }

    private var observation: NSKeyValueObservation?

    private func close() {
        web.stopLoading()
        dismiss(animated: true)
    }

    func webViewDidClose(_ webView: WKWebView) { close() }

    // Een volgend window.open vanuit dit tabblad: hier laden in plaats van nog een laag.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(action.request)
        return nil
    }
}
