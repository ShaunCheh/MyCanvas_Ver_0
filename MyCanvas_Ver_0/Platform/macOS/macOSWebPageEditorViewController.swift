#if os(macOS)
import AppKit
import WebKit

final class macOSWebPageEditorViewController: NSViewController, NSTextFieldDelegate, WKNavigationDelegate {
    private enum Layout {
        static let horizontalInset: CGFloat = 24
        static let fieldTopSpacing: CGFloat = 16
        static let webViewTopSpacing: CGFloat = 16
        static let bottomInset: CGFloat = 16
        static let minimumWebViewHeight: CGFloat = 260
        static let webViewCornerRadius: CGFloat = 18
    }

    private let shellView = macOSCanvasEditorShellView(
        titleAlignment: .centered
    )
    private let urlTextField: NSTextField = {
        let textField = NSTextField(string: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholderString = "https://example.com"
        textField.controlSize = .large
        textField.font = .systemFont(ofSize: 14)
        textField.bezelStyle = .roundedBezel
        textField.lineBreakMode = .byTruncatingMiddle
        return textField
    }()
    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.wantsLayer = true
        webView.layer?.cornerRadius = Layout.webViewCornerRadius
        webView.layer?.masksToBounds = true
        return webView
    }()

    private var hasAppliedInitialFocus = false

    private var closeButton: NSButton {
        shellView.leadingButton
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = shellView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = macOSCanvasEditorShellView.defaultPreferredContentSize
        configureShell()
        configureInteractions()
        setupViewHierarchy()
        setupConstraints()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard hasAppliedInitialFocus == false else {
            return
        }

        hasAppliedInitialFocus = true
        view.window?.makeFirstResponder(urlTextField)
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss(self)
    }

    private func configureShell() {
        shellView.configureTitle(
            "Open Website",
            alignment: .centered
        )
        shellView.setLeadingButtonHidden(false)
        shellView.setTrailingButtonHidden(true)

        closeButton.title = "Close"
        closeButton.keyEquivalent = "\u{1b}"
    }

    private func configureInteractions() {
        closeButton.target = self
        closeButton.action = #selector(handleCloseButtonClick)
        urlTextField.delegate = self
    }

    private func setupViewHierarchy() {
        shellView.contentView.addSubview(urlTextField)
        shellView.contentView.addSubview(webView)
    }

    private func setupConstraints() {
        let contentView = shellView.contentView
        let safeArea = contentView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            urlTextField.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: Layout.fieldTopSpacing
            ),
            urlTextField.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            urlTextField.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -Layout.horizontalInset
            ),

            webView.topAnchor.constraint(
                equalTo: urlTextField.bottomAnchor,
                constant: Layout.webViewTopSpacing
            ),
            webView.leadingAnchor.constraint(
                equalTo: safeArea.leadingAnchor,
                constant: Layout.horizontalInset
            ),
            webView.trailingAnchor.constraint(
                equalTo: safeArea.trailingAnchor,
                constant: -Layout.horizontalInset
            ),
            webView.bottomAnchor.constraint(
                equalTo: safeArea.bottomAnchor,
                constant: -Layout.bottomInset
            ),
            webView.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Layout.minimumWebViewHeight
            )
        ])
    }

    @objc
    private func handleCloseButtonClick() {
        dismiss(self)
    }

    private func loadWebsite(from rawInput: String) {
        do {
            let resolvedURL = try CanvasHTTPSURLPolicy.url(from: rawInput)
            urlTextField.stringValue = resolvedURL.absoluteString
            webView.load(URLRequest(url: resolvedURL))
        } catch {
            presentError(
                title: "Unable to Open Website",
                message: error.localizedDescription
            )
        }
    }

    private func navigationPolicyError(
        for requestURL: URL
    ) -> CanvasHTTPSURLPolicyError? {
        guard requestURL.absoluteString != "about:blank" else {
            return nil
        }

        do {
            _ = try CanvasHTTPSURLPolicy.url(from: requestURL.absoluteString)
            return nil
        } catch let policyError as CanvasHTTPSURLPolicyError {
            return policyError
        } catch {
            return .invalidURL
        }
    }

    private func shouldIgnoreNavigationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain &&
            nsError.code == NSURLErrorCancelled
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")

        if let window = view.window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    private func handleNavigationFailure(_ error: Error) {
        guard shouldIgnoreNavigationError(error) == false else {
            return
        }

        presentError(
            title: "Unable to Load Website",
            message: error.localizedDescription
        )
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            loadWebsite(from: urlTextField.stringValue)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            dismiss(self)
            return true
        }

        return false
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let isTopLevelNavigation = navigationAction.targetFrame?.isMainFrame ?? true
        guard isTopLevelNavigation else {
            decisionHandler(.allow)
            return
        }

        guard let requestURL = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if let policyError = navigationPolicyError(for: requestURL) {
            decisionHandler(.cancel)
            presentError(
                title: "Unable to Open Website",
                message: policyError.localizedDescription
            )
            return
        }

        // Keep target=_blank style navigations inside the in-app browser.
        if navigationAction.targetFrame == nil {
            webView.load(URLRequest(url: requestURL))
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard
            let resolvedURL = webView.url,
            navigationPolicyError(for: resolvedURL) == nil
        else {
            return
        }

        urlTextField.stringValue = resolvedURL.absoluteString
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        handleNavigationFailure(error)
    }
}
#endif
