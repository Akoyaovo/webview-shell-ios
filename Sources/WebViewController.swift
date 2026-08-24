import UIKit
import WebKit

final class WebViewController: UIViewController {

    // ★ 改成你的网站地址
    private static let homeURL = URL(string: "http://47.82.146.22:3001")!

    private var webView: WKWebView!
    private var themeObservation: NSKeyValueObservation?
    private var statusBarStyle: UIStatusBarStyle = .darkContent

    // MARK: - 生命周期

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        // 开 Service Worker（配合 Info.plist 的 WKAppBoundDomains）
        
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?"

        // 注入标记，让前端知道自己跑在壳里
        let flag = WKUserScript(
            source: "window.__NATIVE_SHELL__ = true; window.__SHELL_VER__ = '\(ver)';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true)
        config.userContentController.addUserScript(flag)
        config.applicationNameForUserAgent = "WebViewShell/\(ver)"

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false

        // 全屏铺满，不让系统自动加 inset
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        let shellBg = UIColor(red: 0x3d/255.0, green: 0x4a/255.0, blue: 0x4f/255.0, alpha: 1)
        webView.underPageBackgroundColor = shellBg
        webView.isOpaque = false
        webView.backgroundColor = .clear

        let root = UIView()
        root.backgroundColor = shellBg
        root.addSubview(webView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: root.topAnchor),
            webView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeThemeColor()
        loadHome()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { statusBarStyle }

    // MARK: - 加载

    private func loadHome() {
        webView.load(URLRequest(url: Self.homeURL))
    }

    @objc private func appDidBecomeActive() {
        // WebKit 渲染进程可能被系统回收，回来是白屏
        if webView.url == nil { loadHome() }
    }

    // MARK: - 主题色跟随

    private func observeThemeColor() {
        themeObservation = webView.observe(\.themeColor, options: [.new]) {
            [weak self] webView, _ in
            self?.applyThemeColor(webView.themeColor)
        }
    }

    private func applyThemeColor(_ color: UIColor?) {
        guard let color else { return }
        webView.underPageBackgroundColor = color
        view.backgroundColor = color
        let style: UIStatusBarStyle = color.isDark ? .lightContent : .darkContent
        guard style != statusBarStyle else { return }
        statusBarStyle = style
        setNeedsStatusBarAppearanceUpdate()
    }
}

// MARK: - 导航

extension WebViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow); return
        }
        let inApp = url.host == Self.homeURL.host
            || ["data", "blob", "about"].contains(url.scheme ?? "")
        if inApp {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyThemeColor(webView.themeColor)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadHome()
    }
}

// MARK: - JS 弹窗

extension WebViewController: WKUIDelegate {

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            if url.host == Self.homeURL.host {
                webView.load(navigationAction.request)
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(ac, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let ac = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        present(ac, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let ac = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        ac.addTextField { $0.text = defaultText }
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        ac.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(ac.textFields?.first?.text)
        })
        present(ac, animated: true)
    }
}

// MARK: - 工具

private extension UIColor {
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.6
    }
}
