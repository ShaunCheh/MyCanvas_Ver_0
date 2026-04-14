# 20260414_103632_phase5_toolbar_browser_wiring_record

## 记录说明

本记录对应 `phase5`：把网页能力接入现有 `toolbar state -> host view -> platform view controller` 链路。

本记录基于以下真实依据整理：

- `date` 生成的时间戳
- 写入本记录前的 `git status`
- `phase5` 相关文件的 `git diff --stat`
- 当前工作区中这 5 个文件的实际代码状态
- iOS / macOS 双平台 `xcodebuild build` 结果

本次 `phase5` 的代码主体涉及以下 `5` 个文件：

- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

写入本记录前，当前工作区还存在一个与本次主体无关但真实存在的状态项：

- `.cursor/plans/工具栏网页弹层_c7d06c44.plan.md`

本记录会如实保留这条状态，但下面的“修改前 / 修改后”主体只聚焦本次 `phase5` 代码接线。

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本次 phase5 记录文件的时间戳前缀。
date '+%Y%m%d_%H%M%S'
#
# 实际输出:
# 20260414_103632
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
#  M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
#  M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
#  M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
#  M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
#  M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计 phase5 相关代码文件的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift" \
  "MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift" \
  "MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
#
# 实际输出:
#  .../Shared/Toolbar/CanvasToolbarState.swift        |  1 +
#  .../Shared/Toolbar/CanvasToolbarStateBuilder.swift | 10 ++++++++
#  .../iOS/Canvas/iOSCanvasToolbarHostView.swift      |  2 ++
#  .../Platform/iOS/iOSViewController.swift           | 29 ++++++++++++++++++++-
#  .../Platform/macOS/macOSViewController.swift       | 30 +++++++++++++++++++++-
#  5 files changed, 70 insertions(+), 2 deletions(-)
```

## 本次 phase5 的真实目标

这一步不是继续做网页页本身，而是把前一步已经实现好的网页页接到现有 toolbar 入口上，同时保持既有 toolbar 策略不变。

本次真实目标有四个：

1. 在 shared toolbar 状态里新增浏览器按钮语义。
2. 让主 toolbar 在非 `reading mode` 下渲染出 Safari 风格入口。
3. 把该入口接入 iOS / macOS 现有 controller，沿用现有 editor 弹层互斥逻辑。
4. 保持 `reading mode` 下 toolbar 仍然整体隐藏，不给浏览器按钮单独开口子。

## 修改一：shared toolbar 状态新增浏览器按钮 ID

### 修改前

修改前，`CanvasToolbarItemID` 没有浏览器按钮的枚举值，因此 toolbar 状态层根本无法表达“网页按钮”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/符号名: CanvasToolbarItemID
// 功能说明: 修改前 toolbar item 枚举只覆盖 crop/save/text/import/undo/redo，不包含网页入口。
import CoreGraphics
import Foundation

enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case save
    case text
    case importMedia
    case undo
    case redo
}
```

### 修改后

修改后，`CanvasToolbarItemID` 新增 `.browser`，让 toolbar 的 shared state 可以稳定表达这个新入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/符号名: CanvasToolbarItemID
// 功能说明: 修改后新增 browser 枚举值，把网页入口提升为 shared toolbar state 的一等 item。
import CoreGraphics
import Foundation

enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case save
    case text
    case importMedia
    case browser
    case undo
    case redo
}
```

### 这部分改动解决了什么

- shared toolbar 终于能表达“网页按钮”这个 item。
- 后面的 builder、host view、platform controller 都可以围绕统一的 `.browser` ID 接线，而不是各平台各自硬编码。

## 修改二：builder 把浏览器按钮接入主 toolbar，同时保持 reading mode 现状不变

### 修改前

修改前，`CanvasToolbarStateBuilder.mainToolbarState(...)` 在非 `reading mode` 下只会把 `importMedia` 追加到主 toolbar，之后直接返回；而在 `reading mode` 下，仍然是直接返回空 items。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/符号名: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:includesHistoryItems:)
// 功能说明: 修改前 builder 只把 import 挂入主 toolbar，reading mode 仍然通过空 items 整体隐藏 toolbar。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))

    return CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
}
```

### 修改后

修改后，builder 在保留原有 `reading mode` 空 toolbar 返回逻辑的前提下，新增 `browserItemState()`，并把浏览器按钮追加到 `importMedia` 后面。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/符号名: mainToolbarState(...) / browserItemState()
// 功能说明: 修改后主 toolbar 在 import 后追加浏览器按钮，但 reading mode 下仍然沿用空 items 逻辑，不为浏览器单独开口子。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    guard session.isReadingModeActive == false else {
        return CanvasToolbarState(
            placement: placement,
            items: [],
            showsBackground: showsBackground
        )
    }

    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))
    itemStates.append(browserItemState())

    return CanvasToolbarState(
        placement: placement,
        items: itemStates,
        showsBackground: showsBackground
    )
}

func browserItemState() -> CanvasToolbarItemState {
    CanvasToolbarItemState(
        id: .browser,
        systemImageName: "safari",
        accessibilityLabel: "Open website",
        visualRole: .accent
    )
}
```

### 这部分改动解决了什么

- 浏览器按钮成为主 toolbar 的正式一部分。
- 顺序上和 `importMedia` 相邻，符合本次 phase5 计划。
- `reading mode` 仍然整体隐藏 toolbar，没有发生策略回退。

## 修改三：iOS host 为 Safari 图标补尺寸分支

### 修改前

修改前，`iOSCanvasToolbarHostView.symbolConfiguration(for:)` 只区分 `save/undo/redo`、`importMedia`、`crop/text` 三组，没有 `browser` 分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/符号名: symbolConfiguration(for:)
// 功能说明: 修改前 iOS toolbar host 没有针对浏览器按钮的专用 SF Symbol 尺寸分支。
private func symbolConfiguration(
    for itemID: CanvasToolbarItemID
) -> UIImage.SymbolConfiguration {
    switch itemID {
    case .save, .undo, .redo:
        return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    case .importMedia:
        return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    case .crop, .text:
        return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    }
}
```

### 修改后

修改后，iOS host 为 `.browser` 明确指定一档单独的 symbol 配置，避免它直接落到已有分支里导致视觉比例不协调。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/符号名: symbolConfiguration(for:)
// 功能说明: 修改后为 browser 按钮补独立 symbol 尺寸配置，保证 Safari 图标和现有 toolbar 按钮视觉一致。
private func symbolConfiguration(
    for itemID: CanvasToolbarItemID
) -> UIImage.SymbolConfiguration {
    switch itemID {
    case .save, .undo, .redo:
        return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    case .importMedia:
        return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    case .browser:
        return UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
    case .crop, .text:
        return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
    }
}
```

### 这部分改动解决了什么

- iOS toolbar 上的 Safari 图标不会复用错误的尺寸配置。
- 新按钮在视觉上和现有 toolbar 风格保持一致。

## 修改四：iOS controller 把浏览器按钮接进现有 toolbar 注册与弹层互斥链路

### 修改前

修改前，`iOSViewController` 只有 `importButton`，没有 `browserButton`；`toolbarButtonsByID` 也没有 `.browser`；`viewDidLoad()` 和 `setup...Button()` 里更没有浏览器按钮的注册入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: importButton / toolbarButtonsByID / viewDidLoad() / setupImportButton()
// 功能说明: 修改前 iOS controller 只注册 import/save/crop/text/undo/redo，没有网页按钮接线。
private let importButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    updatePreparedToolbarPlacement()
    setupTextEditorOverlay()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupTextButton()
    setupUndoButton()
    setupRedoButton()
    setupBackButton()
    setupWorkspaceModeButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
    applyTransitionInteractionFreeze()
}

private func setupImportButton() {
    importButton.addTarget(self, action: #selector(handleImportButtonTap), for: .touchUpInside)
    renderToolbar()
}
```

修改前也没有网页 editor 的展示入口，只有 GIF / Video editor 的现有弹层函数。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: presentGIFFrameImportEditor(for:)
// 功能说明: 修改前 iOS 侧只有 GIF/Video editor 的 present 入口，没有网页 editor 的互斥弹层入口。
private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    do {
        let editorContext = try editorSession.gifFrameImportEditorContext(
            for: itemID
        )
        let editorViewController = iOSGIFFrameImportViewController(
            editorContext: editorContext
        ) { [weak self] frameIndices in
            guard let self else {
                throw iOSGIFFrameImportFlowError.presenterUnavailable
            }

            try self.performGIFFrameImport(
                for: itemID,
                frameIndices: frameIndices
            )
        }
        present(editorViewController, animated: true)
    } catch {
        presentGIFFrameImportEditorError(
            message: error.localizedDescription
        )
    }
}
```

### 修改后

修改后，`iOSViewController` 新增 `browserButton`，并把它接进 `toolbarButtonsByID`、`viewDidLoad()` 与 `setupBrowserButton()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: browserButton / toolbarButtonsByID / viewDidLoad() / setupBrowserButton()
// 功能说明: 修改后 iOS controller 把浏览器按钮接进 toolbar 注册链路，并在初始化阶段和 import 按钮同级完成 setup。
private let browserButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton,
        .browser: browserButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    updatePreparedToolbarPlacement()
    setupTextEditorOverlay()
    setupImportButton()
    setupBrowserButton()
    setupSaveButton()
    setupCropButton()
    setupTextButton()
    setupUndoButton()
    setupRedoButton()
    setupBackButton()
    setupWorkspaceModeButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
    applyTransitionInteractionFreeze()
}

private func setupBrowserButton() {
    browserButton.addTarget(self, action: #selector(handleBrowserButtonTap), for: .touchUpInside)
    renderToolbar()
}
```

同时，iOS 侧新增了浏览器按钮点击处理与网页页展示入口，并沿用现有 `presentedViewController == nil` 的弹层互斥判断，不会绕开已有 editor 的互斥语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/符号名: handleBrowserButtonTap() / presentWebPageEditor()
// 功能说明: 修改后浏览器按钮点击沿用现有 modal 互斥判断，先提交活跃文本编辑，再全屏弹出网页页。
@objc
private func handleBrowserButtonTap() {
    presentWebPageEditor()
}

private func presentWebPageEditor() {
    guard presentedViewController == nil else {
        return
    }

    commitActiveTextEditIfNeeded()
    let editorViewController = iOSWebPageEditorViewController()
    present(editorViewController, animated: true)
}
```

### 这部分改动解决了什么

- iOS toolbar 现在真正能显示和响应浏览器按钮。
- 按钮点击不会另起一套 UI 逻辑，而是沿用现有 modal 呈现和互斥约束。
- 文本编辑态下先提交当前编辑，再打开网页页，避免状态冲突。

## 修改五：macOS controller 把浏览器按钮接进现有 toolbar 注册与 sheet 互斥链路

### 修改前

修改前，`macOSViewController` 同样只有 `importButton`，没有 `browserButton`；`toolbarButtonsByID` 和 `viewDidLoad()` 的 setup 顺序里都没有浏览器按钮。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: importButton / toolbarButtonsByID / viewDidLoad() / setupImportButton()
// 功能说明: 修改前 macOS controller 只把 import/save/crop/text/undo/redo 接进 toolbar，没有网页按钮入口。
private let importButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    updatePreparedToolbarPlacement()
    setupTextEditorOverlay()
    setupImportButton()
    setupSaveButton()
    setupCropButton()
    setupTextButton()
    setupUndoButton()
    setupRedoButton()
    setupBackButton()
    setupWorkspaceModeButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
    applyTransitionInteractionFreeze()
}

private func setupImportButton() {
    importButton.target = self
    importButton.action = #selector(handleImportButtonClick)
    renderToolbar()
}
```

修改前同样只有 GIF / Video 的 sheet 入口，网页页没有 controller 层互斥接线。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: presentGIFFrameImportEditor(for:)
// 功能说明: 修改前 macOS 侧只有 GIF/Video editor 的 sheet 呈现入口，没有网页页入口。
private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    do {
        let editorContext = try editorSession.gifFrameImportEditorContext(
            for: itemID
        )
        let editorViewController = macOSGIFFrameImportViewController(
            editorContext: editorContext
        ) { [weak self] frameIndices in
            guard let self else {
                throw macOSGIFFrameImportFlowError.presenterUnavailable
            }

            try self.performGIFFrameImport(
                for: itemID,
                frameIndices: frameIndices
            )
        }
        presentAsSheet(editorViewController)
    } catch {
        presentGIFFrameImportEditorError(
            message: error.localizedDescription
        )
    }
}
```

### 修改后

修改后，`macOSViewController` 新增 `browserButton`，把它注册进 `toolbarButtonsByID`，并在 `viewDidLoad()` 时和 import 按钮相邻完成 setup。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: browserButton / toolbarButtonsByID / viewDidLoad() / setupBrowserButton()
// 功能说明: 修改后 macOS controller 把浏览器按钮接进 toolbar 注册链路，并在现有 setup 顺序里紧跟 import 按钮完成初始化。
private let browserButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton,
        .browser: browserButton
    ]
}

override func viewDidLoad() {
    super.viewDidLoad()
    setupViewHierarchy()
    setupConstraints()
    updatePreparedToolbarPlacement()
    setupTextEditorOverlay()
    setupImportButton()
    setupBrowserButton()
    setupSaveButton()
    setupCropButton()
    setupTextButton()
    setupUndoButton()
    setupRedoButton()
    setupBackButton()
    setupWorkspaceModeButton()
    setupMiniMapView()
    setupContextMenuHostView()
    restoreInitialBoardState()
    setupCanvasViewport()
    applyTransitionInteractionFreeze()
}

private func setupBrowserButton() {
    browserButton.target = self
    browserButton.action = #selector(handleBrowserButtonClick)
    renderToolbar()
}
```

同时，macOS 新增浏览器按钮点击处理和 `presentWebPageEditor()`，并继续沿用现有 `presentedViewControllers?.isEmpty != false` 的 sheet 互斥判断。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/符号名: handleBrowserButtonClick() / presentWebPageEditor()
// 功能说明: 修改后浏览器按钮点击沿用现有 sheet 互斥判断，先提交活跃文本编辑，再把网页页以 sheet 方式展示出来。
@objc
private func handleBrowserButtonClick() {
    presentWebPageEditor()
}

private func presentWebPageEditor() {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    commitActiveTextEditIfNeeded()
    let editorViewController = macOSWebPageEditorViewController()
    presentAsSheet(editorViewController)
}
```

### 这部分改动解决了什么

- macOS toolbar 现在和 iOS 一样具备浏览器按钮入口。
- 新入口没有绕开现有 sheet 互斥判断。
- 网页页的打开方式继续和已有 GIF / Video editor 一致，仍然是 `presentAsSheet(...)`。

## 修改范围说明：macOS host 本次没有改

本次 `phase5` 没有修改 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`。真实原因不是遗漏，而是当前 macOS host 直接按 `itemState.systemImageName` 生成符号图标，不像 iOS host 那样按 `itemID` 分尺寸分支，所以这一步无需在 macOS host 里额外补一个 `.browser` case。

## 验证结果

### 构建验证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 iOS target 在接入 toolbar 浏览器按钮后仍然可以成功构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 macOS target 在接入 toolbar 浏览器按钮后仍然可以成功构建。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

### 构建时观察到的 warning

下面这些 warning 在本次构建输出里真实存在；本记录只如实保留，不把它们都算作本次 `phase5` 新增问题。

```bash
# 文件路径: iOS 构建输出 /Users/shaun/.cursor/projects/Users-shaun-Library-Mobile-Documents-com-apple-CloudDocs-Develop-MyCanvas-Ver-0/agent-tools/b8343838-9781-40ad-a988-684a428f8507.txt
# 函数名/命令名: xcodebuild build 输出摘录
# 功能说明: iOS 构建通过，但仍存在工程里的既有 warning。
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift:34:102: warning: main actor-isolated conformance of 'CanvasImageAssetReference' to 'Hashable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode
2026-04-14 10:30:00.427 appintentsmetadataprocessor[14913:2494783] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```

```bash
# 文件路径: macOS 构建输出 /Users/shaun/.cursor/projects/Users-shaun-Library-Mobile-Documents-com-apple-CloudDocs-Develop-MyCanvas-Ver-0/agent-tools/e783c3dc-0635-4776-917b-1db5d3aec885.txt
# 函数名/命令名: xcodebuild build 输出摘录
# 功能说明: macOS 构建通过，但输出里仍保留若干既有 warning。
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift:2476:52: warning: main actor-isolated conformance of 'CanvasToolbarTransitionDirection' to 'Equatable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift:2477:40: warning: main actor-isolated conformance of 'CanvasToolbarTransitionStage' to 'Equatable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode
/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift:34:102: warning: main actor-isolated conformance of 'CanvasImageAssetReference' to 'Hashable' cannot be used in nonisolated context; this is an error in the Swift 6 language mode
2026-04-14 10:30:03.731 appintentsmetadataprocessor[14972:2495042] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```

### 本地检查结论

本次 `phase5` 修改完成后，针对以下文件的 IDE lint 检查没有发现新增问题：

- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 结论

本次 `phase5` 的真实结果是：

1. shared toolbar 状态新增了 `.browser`。
2. `CanvasToolbarStateBuilder` 会在非 `reading mode` 的主 toolbar 里追加 Safari 风格按钮。
3. iOS host 为新按钮补了专用 SF Symbol 尺寸配置。
4. iOS / macOS controller 都把浏览器按钮接入了现有 toolbar 注册与点击分发链路。
5. iOS 继续用 `presentedViewController == nil`，macOS 继续用 `presentedViewControllers?.isEmpty != false`，没有绕开既有 editor 弹层互斥约束。
6. 双平台构建通过。

本阶段尚未完成的部分：

- `phase6` 里的 targeted tests
- toolbar 布局基线回归测试更新
- GIF / Video / Browser 三类弹层的手工回归记录
