#if os(iOS)
import UIKit
import WebKit

final class iOSWebPageEditorViewController: UIViewController, UITextFieldDelegate, WKNavigationDelegate {
    private enum Layout {
        static let horizontalInset: CGFloat = 24
        static let fieldTopSpacing: CGFloat = 16
        static let webViewTopSpacing: CGFloat = 16
        static let bottomInset: CGFloat = 16
        static let urlFieldHeight: CGFloat = 40
        static let minimumWebViewHeight: CGFloat = 220
        static let webViewCornerRadius: CGFloat = 18
    }

    private let shellView = iOSCanvasEditorShellView(
        titleAlignment: .centered
    )
    private let urlTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.borderStyle = .roundedRect
        textField.placeholder = "https://example.com"
        textField.textContentType = UITextContentType.URL
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.clearButtonMode = .whileEditing
        textField.keyboardType = .URL
        textField.returnKeyType = .go
        return textField
    }()
    private lazy var webView: WKWebView = {
        let webView = WKWebView(frame: .zero)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .secondarySystemBackground
        webView.scrollView.backgroundColor = .secondarySystemBackground
        webView.layer.cornerRadius = Layout.webViewCornerRadius
        webView.layer.masksToBounds = true
        return webView
    }()

    private var hasAppliedInitialFocus = false

    private var closeButton: UIButton {
        shellView.leadingButton
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
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
        configureShell()
        configureInteractions()
        setupViewHierarchy()
        setupConstraints()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard hasAppliedInitialFocus == false else {
            return
        }

        hasAppliedInitialFocus = true
        urlTextField.becomeFirstResponder()
    }

    private func configureShell() {
        shellView.configureTitle(
            "Open Website",
            alignment: .centered
        )
        shellView.setLeadingButtonHidden(false)
        shellView.setTrailingButtonHidden(true)

        var configuration = UIButton.Configuration.plain()
        configuration.title = "Close"
        closeButton.configuration = configuration
    }

    private func configureInteractions() {
        closeButton.addTarget(
            self,
            action: #selector(handleCloseButtonTap),
            for: .touchUpInside
        )
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
            urlTextField.heightAnchor.constraint(
                greaterThanOrEqualToConstant: Layout.urlFieldHeight
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
    private func handleCloseButtonTap() {
        dismiss(animated: true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        loadWebsite(from: textField.text ?? "")
        return false
    }

    private func loadWebsite(from rawInput: String) {
        do {
            let resolvedURL = try CanvasHTTPSURLPolicy.url(from: rawInput)
            urlTextField.text = resolvedURL.absoluteString
            urlTextField.resignFirstResponder()
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
        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alertController.addAction(
            UIAlertAction(title: "OK", style: .default)
        )
        present(alertController, animated: true)
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

        urlTextField.text = resolvedURL.absoluteString
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
