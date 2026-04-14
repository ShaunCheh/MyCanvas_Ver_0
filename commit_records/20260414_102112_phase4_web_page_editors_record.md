# 20260414_102112_phase4_web_page_editors_record

## 记录说明

本记录对应 `phase4`：在前面抽出的 editor shell 基础上，分别实现 iOS / macOS 网页编辑页，并补齐 macOS 沙盒下网页加载所需的出站网络权限。

本记录基于以下真实依据整理：

- 当前工作区 `git status`
- `phase4` 相关文件的 `git diff --stat` 与当前代码状态
- 双平台 `xcodebuild build` 结果

本记录不包含：

- 原始 `git diff` 文本
- toolbar 接线
- commit / push

当前工作区里除 `phase4` 代码文件外，还存在一个 `.md` 状态项：

- `.cursor/plans/工具栏网页弹层_c7d06c44.plan.md`

该状态会在取证区原样记录，但本文件的主体说明仍只聚焦 `phase4` 的实现代码。

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本次记录文件使用的时间戳前缀。
date '+%Y%m%d_%H%M%S'
#
# 实际输出:
# 20260414_102112
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git -c core.quotepath=false status --short --branch
# 功能说明: 记录写入本文件前的真实工作区状态，保留当前 changes 的全貌。
git -c core.quotepath=false status --short --branch
#
# 实际输出:
# ## feat/cross-platform-input-indicator
#  M .cursor/plans/工具栏网页弹层_c7d06c44.plan.md
#  M MyCanvas_Ver_0.xcodeproj/project.pbxproj
# ?? MyCanvas_Ver_0/MyCanvas_Ver_0.macOS.entitlements
# ?? MyCanvas_Ver_0/Platform/iOS/iOSWebPageEditorViewController.swift
# ?? MyCanvas_Ver_0/Platform/macOS/macOSWebPageEditorViewController.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat / git diff --no-index --stat
# 功能说明: 统计 phase4 相关实现文件的真实改动规模；已跟踪文件用 git diff，新增文件用 /dev/null 对比。
git diff --stat -- "MyCanvas_Ver_0.xcodeproj/project.pbxproj"
git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/MyCanvas_Ver_0.macOS.entitlements"
git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Platform/iOS/iOSWebPageEditorViewController.swift"
git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Platform/macOS/macOSWebPageEditorViewController.swift"
#
# 实际输出:
#  MyCanvas_Ver_0.xcodeproj/project.pbxproj                       |   2 ++
#  1 file changed, 2 insertions(+)
#
#  .../null => MyCanvas_Ver_0/MyCanvas_Ver_0.macOS.entitlements |  12 ++++++++++++
#  1 file changed, 12 insertions(+)
#
#  .../iOS/iOSWebPageEditorViewController.swift                 | 285 +++++++++++++++++++++
#  1 file changed, 285 insertions(+)
#
#  .../macOS/macOSWebPageEditorViewController.swift             | 288 +++++++++++++++++++++
#  1 file changed, 288 insertions(+)
```

## 本次 phase4 的真实目标

这一步不是接 toolbar，而是先把“网页弹层本身”做成可用闭环，验证前面抽出的 shell 确实能承载第三类页面。

本次真实目标有四个：

1. iOS 新增一个复用 `iOSCanvasEditorShellView` 的网页编辑页。
2. macOS 新增一个复用 `macOSCanvasEditorShellView` 的网页编辑页。
3. 两个平台都支持 URL 输入、回车加载、`CanvasHTTPSURLPolicy` 校验、`WKWebView` 内嵌加载与错误提示。
4. macOS 在 App Sandbox 下补齐 `com.apple.security.network.client`，从根因上避免“界面存在但无法联网加载”的假完成。

## 修改一：新增 iOS 网页编辑页

### 修改前

`iOS` 端还没有独立的网页编辑页；仓库里不存在 `iOSWebPageEditorViewController.swift`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSWebPageEditorViewController.swift
// 函数名/符号名: 新增前不存在
// 功能说明: 修改前 iOS 端没有基于 editor shell 的网页弹层实现，无法承载 URL 输入与内嵌网页加载。
// 文件状态: 不存在
```

### 修改后

新增 `iOSWebPageEditorViewController`，直接复用 `iOSCanvasEditorShellView`，保留从下往上全屏弹出的既有 editor 呈现方式，但把右侧主按钮隐藏，仅保留左侧 `Close`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSWebPageEditorViewController.swift
// 函数名/符号名: iOSWebPageEditorViewController / init() / viewDidLoad() / viewDidAppear(_:) / configureShell()
// 功能说明: 新增 iOS 网页页，复用 editor shell 承载 URL 输入框与 WKWebView，并在首次展示时默认聚焦输入框。
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
}
#endif
```

URL 输入与加载逻辑没有走系统浏览器，而是直接在当前页内调用 `WKWebView.load(...)`；同时所有用户输入与顶层导航都统一走 `CanvasHTTPSURLPolicy`，从根因上保证只允许 `https://`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSWebPageEditorViewController.swift
// 函数名/符号名: textFieldShouldReturn(_:) / loadWebsite(from:) / webView(_:decidePolicyFor:decisionHandler:) / webView(_:didFinish:)
// 功能说明: 按回车立即加载网页；加载前统一做 HTTPS 校验；target=_blank 与顶层跳转都被收束在应用内 web view 中处理。
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
```

### 这部分改动解决了什么

- iOS 端第一次具备了独立网页页，而不是把网页能力散落到 controller 外部。
- 进入页面默认聚焦 URL 输入框，输入后按回车立即加载。
- 顶层导航和用户输入共用 `CanvasHTTPSURLPolicy`，避免 `http://`、非法 scheme 或空 host 漏网。

## 修改二：新增 macOS 网页编辑页

### 修改前

`macOS` 端同样不存在网页编辑页；仓库里没有 `macOSWebPageEditorViewController.swift`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSWebPageEditorViewController.swift
// 函数名/符号名: 新增前不存在
// 功能说明: 修改前 macOS 端没有网页 sheet controller，无法在既有 editor shell 内输入 URL 并内嵌加载网页。
// 文件状态: 不存在
```

### 修改后

新增 `macOSWebPageEditorViewController`，复用 `macOSCanvasEditorShellView`。页面结构和 iOS 对齐：标题居中、左侧 `Close`、右侧主按钮隐藏、内容区包含 URL 输入框与 `WKWebView`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSWebPageEditorViewController.swift
// 函数名/符号名: macOSWebPageEditorViewController / viewDidLoad() / viewDidAppear() / configureShell()
// 功能说明: 新增 macOS 网页页，复用 editor shell 承载 URL 输入与 WKWebView，并在首次展示后把焦点交给输入框。
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
}
#endif
```

macOS 端和 iOS 的差异主要体现在回车处理和 sheet 交互：这里用 `control(_:textView:doCommandBy:)` 拦截回车，保留 `Esc` 关闭 sheet；而网页加载、顶层导航校验、页内跳转拦截仍复用同一套 HTTPS 约束。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSWebPageEditorViewController.swift
// 函数名/符号名: control(_:textView:doCommandBy:) / loadWebsite(from:) / webView(_:decidePolicyFor:decisionHandler:) / presentError(title:message:)
// 功能说明: 回车触发加载、Esc 关闭 sheet、导航统一做 HTTPS 校验，错误提示复用 macOS 现有 NSAlert sheet 模式。
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

    if navigationAction.targetFrame == nil {
        webView.load(URLRequest(url: requestURL))
        decisionHandler(.cancel)
        return
    }

    decisionHandler(.allow)
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
```

### 这部分改动解决了什么

- macOS 端也形成了和 iOS 对称的网页页实现。
- 回车加载、Esc 关闭、默认聚焦输入框都符合现有 macOS editor 的交互风格。
- 错误提示继续走 `NSAlert` sheet，而不是引入一套新交互。

## 修改三：为 macOS 沙盒补齐网络客户端权限

### 修改前

修改前，工程虽然启用了 `ENABLE_APP_SANDBOX = YES`，但 `project.pbxproj` 没有给 macOS 构建配置挂任何显式 entitlements 文件，因此网页页即便编译成功，也可能在沙盒下缺少出站网络能力。

```c
/* 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
 * 函数名/符号名: XCBuildConfiguration Debug / Release
 * 功能说明: 修改前 macOS 构建配置没有挂接专用 entitlements 文件，沙盒能力只能依赖现有默认签名内容。
 */
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
CODE_SIGN_STYLE = Automatic;
CURRENT_PROJECT_VERSION = 1;
DEVELOPMENT_TEAM = JWWZTL2S7W;
ENABLE_APP_SANDBOX = YES;
ENABLE_HARDENED_RUNTIME = YES;
ENABLE_PREVIEWS = YES;
ENABLE_USER_SELECTED_FILES = readwrite;
GENERATE_INFOPLIST_FILE = YES;
```

```xml
<!-- 文件路径: MyCanvas_Ver_0/MyCanvas_Ver_0.macOS.entitlements -->
<!-- 函数名/符号名: 新增前不存在 -->
<!-- 功能说明: 修改前仓库中不存在显式的 macOS entitlements 文件，也就没有地方显式声明 network client 权限。 -->
<!-- 文件状态: 不存在 -->
```

### 修改后

在 `project.pbxproj` 的 Debug / Release 配置里，为 `sdk=macosx*` 显式挂上 `MyCanvas_Ver_0.macOS.entitlements`，把权限声明和网页功能绑定到同一阶段里落地。

```c
/* 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
 * 函数名/符号名: XCBuildConfiguration Debug / Release
 * 功能说明: 修改后为 macOS 构建配置显式挂接 entitlements 文件，确保网页页在 App Sandbox 下具备出站网络能力。
 */
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
CODE_SIGN_STYLE = Automatic;
"CODE_SIGN_ENTITLEMENTS[sdk=macosx*]" = MyCanvas_Ver_0/MyCanvas_Ver_0.macOS.entitlements;
CURRENT_PROJECT_VERSION = 1;
DEVELOPMENT_TEAM = JWWZTL2S7W;
ENABLE_APP_SANDBOX = YES;
ENABLE_HARDENED_RUNTIME = YES;
ENABLE_PREVIEWS = YES;
ENABLE_USER_SELECTED_FILES = readwrite;
GENERATE_INFOPLIST_FILE = YES;
```

新增的 entitlements 文件只声明当前功能真正需要的几项能力：App Sandbox、本来已有的用户选中文件读写，以及本次网页加载需要的 `com.apple.security.network.client`。

```xml
<!-- 文件路径: MyCanvas_Ver_0/MyCanvas_Ver_0.macOS.entitlements -->
<!-- 函数名/符号名: com.apple.security.app-sandbox / com.apple.security.files.user-selected.read-write / com.apple.security.network.client -->
<!-- 功能说明: 新增 macOS 显式 entitlements 文件，把网页页需要的出站网络能力固化到签名配置里。 -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
```

### 这部分改动解决了什么

- 从根因上补齐了 macOS 网页页真正需要的出站网络权限。
- 避免出现“控制器能编译、界面能弹出，但 `WKWebView` 在沙盒下无法正常联网”的伪完成状态。

## 验证结果

### 构建验证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 macOS target 在接入网页页与显式 entitlements 后仍可成功编译。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 iOS target 在新增网页页后仍可成功编译。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

### 签名产物校验

macOS 编译产物生成的 `.xcent` 中已经出现 `com.apple.security.network.client = true`，说明新增 entitlements 已经真正进入签名链路，而不是只停留在工程文本里。

```xml
<!-- 文件路径: DerivedData/.../MyCanvas_Ver_0.app.xcent -->
<!-- 函数名/符号名: com.apple.security.network.client -->
<!-- 功能说明: 构建产物中的实际签名权限，验证 network client 权限已被写入 macOS app 的 xcent。 -->
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.get-task-allow</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
```

### 构建时观察到的非本次新增问题

`xcodebuild` 输出里还存在两条与本次 `phase4` 不直接相关的 warning：

1. `MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift` 的 `main actor-isolated conformance of 'CanvasImageAssetReference' to 'Hashable' cannot be used in nonisolated context`
2. `appintentsmetadataprocessor` 的 `Metadata extraction skipped. No AppIntents.framework dependency found.`

本次记录只如实保留它们，不把它们计入 `phase4` 新增问题。

## 结论

本次 `phase4` 的真实结果是：

1. 新增了 `iOSWebPageEditorViewController`。
2. 新增了 `macOSWebPageEditorViewController`。
3. 两个平台都支持 URL 输入、回车加载、HTTPS 校验、页内 `WKWebView` 加载与错误提示。
4. macOS 补齐了显式 `entitlements` 与 `com.apple.security.network.client`。
5. 双平台编译通过。

还没有在本阶段完成的部分：

- toolbar 按钮接线
- reading mode 下 toolbar 入口控制
- 相关回归测试与手工 UI 验证记录
