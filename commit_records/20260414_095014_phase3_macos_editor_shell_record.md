# 20260414_095014_phase3_macos_editor_shell_record

## 记录说明

本记录基于本次 `phase 3` 的实际 `git status`、`git diff --stat`、当前代码状态与构建结果整理，不包含原始 `git diff` 文本。

本次业务代码实际涉及 `3` 个 macOS 文件：

- `MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前只有 `1` 个新增文件与 `2` 个已修改文件，全部属于本次 `phase 3`
- `git diff --stat` 显示两个现有 macOS 页面迁移到壳层后的净改动规模为 `2 files changed, 66 insertions(+), 101 deletions(-)`
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift"` 显示新增壳层文件规模为 `1 file changed, 194 insertions(+)`
- `xcodebuild build -destination "platform=macOS"` 已通过，说明本次 macOS 壳层抽取在编译层面成立
- 本次读取的 IDE lints 没有报告这 `3` 个 macOS 文件的新问题

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对已有 `.md` 文件的修改

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date '+%Y%m%d_%H%M%S'
#
# 实际输出:
# 20260414_095014
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 记录写入本文件前的真实工作区状态，确认 phase3 只涉及 3 个 macOS 文件。
git status --short --branch
#
# 实际输出:
# ## feat/cross-platform-input-indicator
#  M MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
#  M MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
# ?? MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计两个现有 macOS 编辑器页面迁移到壳层后的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift"
#
# 实际输出:
# .../macOS/macOSGIFFrameImportViewController.swift  | 99 ++++++++--------------
# ...acOSVideoDisplayFrameEditorViewController.swift | 68 +++++++--------
# 2 files changed, 66 insertions(+), 101 deletions(-)
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --no-index --stat
# 功能说明: 统计新增 macOS 公共编辑器壳层文件的真实改动规模。
git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift"
#
# 实际输出:
# .../macOS/macOSCanvasEditorShellView.swift         | 194 +++++++++++++++++++++
# 1 file changed, 194 insertions(+)
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证本次 macOS 壳层抽取后的工程仍可面向 macOS 成功编译。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

## 本次修改的真实目标

这一步落实的是计划里的 `phase 3`：在 `macOS` 端复用和 `iOS` 相同的抽壳思路，把 `GIF` 与 `Video` 两个 sheet 页面里的公共 chrome 收束起来。

真实目标不是新增功能，而是消除现有 macOS 页面结构的重复根因：

1. 不再让 `macOSGIFFrameImportViewController` 自己持有标题、取消、导入这一套 sheet 顶栏控件。
2. 不再让 `macOSVideoDisplayFrameEditorViewController` 自己重复持有标题、取消按钮和顶栏安全区布局。
3. 把标题、左右按钮、内容容器和统一 `preferredContentSize` 抽成可复用的 `macOSCanvasEditorShellView`。
4. 保留 `presentAsSheet(...)`、键盘快捷键、首次聚焦 `timeSlider`、GIF/Video 业务逻辑与错误提示不变。

## 修改一：新增 macOS 公共编辑器壳层

### 修改前

修改前，`Platform/macOS` 下不存在一个统一承载编辑器顶栏与内容区的公共壳层；`GIF` 和 `Video` 页面都各自定义一套 `titleLabel`、按钮与顶部布局。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift
// 函数名/符号名: 新增前不存在
// 功能说明: 修改前仓库中没有 macOS 端的公共编辑器壳层视图，公共 chrome 只能散落在各个 editor controller 中重复实现。
// 文件状态: 不存在
```

### 修改后

新增 `macOSCanvasEditorShellView`，统一承载标题、左右按钮、内容容器，并收口 `centered` / `leading` 两种标题对齐模式与统一的默认 sheet 尺寸。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift
// 函数名/符号名: macOSCanvasEditorShellTitleAlignment / macOSCanvasEditorShellView
// 功能说明: 新增可复用的 macOS 编辑器壳层，把公共标题栏与内容容器从具体 controller 中抽离出来。
#if os(macOS)
import AppKit

enum macOSCanvasEditorShellTitleAlignment {
    case centered
    case leading
}

final class macOSCanvasEditorShellView: NSView {
    private enum Layout {
        static let titleTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 24
        static let titleAccessorySpacing: CGFloat = 12
    }

    static let defaultPreferredContentSize = CGSize(width: 760, height: 620)

    let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    let leadingButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    let trailingButton: NSButton = {
        let button = NSButton(title: "", target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.controlSize = .large
        button.bezelStyle = .rounded
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    let contentView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
```

壳层里最关键的不只是新增了 view，而是把“标题对齐”“按钮显隐时的零尺寸约束”“内容区顶边与标题栏的关系”都做成统一机制。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSCanvasEditorShellView.swift
// 函数名/符号名: init(titleAlignment:) / configureTitle(_:alignment:) / setLeadingButtonHidden(_:) / setTrailingButtonHidden(_:) / updateTitleAlignment()
// 功能说明: 新增壳层布局入口，让 GIF 和 Video 页面复用同一套 header 结构，但保持不同的标题对齐和按钮策略。
    private var contentTopToTitleConstraint: NSLayoutConstraint!
    private var leadingButtonZeroWidthConstraint: NSLayoutConstraint!
    private var leadingButtonZeroHeightConstraint: NSLayoutConstraint!
    private var trailingButtonZeroWidthConstraint: NSLayoutConstraint!
    private var trailingButtonZeroHeightConstraint: NSLayoutConstraint!
    private var centeredTitleConstraints: [NSLayoutConstraint] = []
    private var leadingTitleConstraints: [NSLayoutConstraint] = []
    private var titleAlignment: macOSCanvasEditorShellTitleAlignment

    init(
        titleAlignment: macOSCanvasEditorShellTitleAlignment
    ) {
        self.titleAlignment = titleAlignment
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        addSubview(titleLabel)
        addSubview(leadingButton)
        addSubview(trailingButton)
        addSubview(contentView)

        // 先创建按钮零尺寸约束与标题对齐约束，再根据标题模式激活对应约束组。
        contentTopToTitleConstraint = contentView.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor
        )
        contentTopToTitleConstraint.priority = .defaultHigh
        // ... 省略其余 centered / leading 标题约束创建 ...
        updateTitleAlignment()
    }

    func configureTitle(
        _ title: String,
        alignment: macOSCanvasEditorShellTitleAlignment
    ) {
        titleLabel.stringValue = title
        titleAlignment = alignment
        updateTitleAlignment()
    }

    func setLeadingButtonHidden(_ hidden: Bool) {
        leadingButton.isHidden = hidden
        leadingButtonZeroWidthConstraint.isActive = hidden
        leadingButtonZeroHeightConstraint.isActive = hidden
    }

    func setTrailingButtonHidden(_ hidden: Bool) {
        trailingButton.isHidden = hidden
        trailingButtonZeroWidthConstraint.isActive = hidden
        trailingButtonZeroHeightConstraint.isActive = hidden
    }
```

### 这一改动解决了什么

- 给 macOS 端两个现有 editor sheet 提供了统一的公共壳层。
- 把 header / safe area / 内容容器从页面业务 controller 中抽离。
- 为后续网页页接入预留了和 iOS 对称的壳层基础。

## 修改二：GIF 选帧页迁移到壳层

### 修改前

迁移前，`macOSGIFFrameImportViewController` 自己维护标题、取消、导入按钮和整套顶栏约束；controller 同时承担公共外壳与选帧业务。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 函数名/符号名: titleLabel / cancelButton / importButton / loadView() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前 GIF 页自己持有并布局 sheet 顶栏，公共 chrome 和页面业务耦合在同一个 controller 里。
private let titleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "Import GIF Frames")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 24, weight: .semibold)
    return label
}()
private let cancelButton: NSButton = {
    let button = NSButton(title: "Cancel", target: nil, action: nil)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.controlSize = .large
    button.bezelStyle = .rounded
    button.keyEquivalent = "\u{1b}"
    return button
}()
private let importButton: NSButton = {
    let button = NSButton(title: "Import", target: nil, action: nil)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.controlSize = .large
    button.bezelStyle = .rounded
    button.keyEquivalent = "\r"
    return button
}()

override func loadView() {
    view = NSView()
}

private func setupViewHierarchy() {
    view.addSubview(titleLabel)
    view.addSubview(cancelButton)
    view.addSubview(importButton)
    view.addSubview(summaryLabel)
    view.addSubview(collectionScrollView)
}

private func setupConstraints() {
    let safeArea = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(
            equalTo: safeArea.topAnchor,
            constant: Layout.titleTopInset
        ),
        titleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
        summaryLabel.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor,
            constant: Layout.summaryTopSpacing
        )
        // ... 省略其余按钮与 collection 约束 ...
    ])
}
```

### 修改后

迁移后，GIF 页不再持有独立的标题与左右按钮，而是改成通过 `shellView` 暴露的 `leadingButton` / `trailingButton` 接线，并把内容区挂进 `shellView.contentView`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 函数名/符号名: shellView / cancelButton / importButton / loadView()
// 功能说明: 修改后 GIF 页把公共 chrome 交给壳层，只保留 summary 与 collection 的业务内容。
private let shellView = macOSCanvasEditorShellView(
    titleAlignment: .centered
)

private var cancelButton: NSButton {
    shellView.leadingButton
}

private var importButton: NSButton {
    shellView.trailingButton
}

override func loadView() {
    view = shellView
}
```

页面初始化与布局起点也从“自己管理根 view + 顶栏”改成“先配置壳层，再只处理内容区”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 函数名/符号名: viewDidLoad() / configureShell() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后 GIF 页把标题、按钮文案和默认 sheet 尺寸交给壳层，自己的布局只负责 summary 与 scroll content。
override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = macOSCanvasEditorShellView.defaultPreferredContentSize
    configureShell()
    setupViewHierarchy()
    setupConstraints()
    configureButtons()
    applyInitialState()
}

private func configureShell() {
    shellView.configureTitle(
        "Import GIF Frames",
        alignment: .centered
    )
    shellView.setLeadingButtonHidden(false)
    shellView.setTrailingButtonHidden(false)

    cancelButton.title = "Cancel"
    cancelButton.keyEquivalent = "\u{1b}"
    importButton.keyEquivalent = "\r"
}

private func setupViewHierarchy() {
    shellView.contentView.addSubview(summaryLabel)
    shellView.contentView.addSubview(collectionScrollView)
}

private func setupConstraints() {
    let contentView = shellView.contentView
    let safeArea = contentView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        summaryLabel.topAnchor.constraint(
            equalTo: contentView.topAnchor,
            constant: Layout.summaryTopSpacing
        ),
        collectionScrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        collectionScrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        collectionScrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
}
```

### 这一改动解决了什么

- GIF 页不再重复实现一套 macOS 顶栏 chrome。
- 选帧业务与公共外壳职责分离。
- 现有“居中标题 + 左 Cancel + 右 Import”的 sheet 结构保留不变，只是来源从本地控件切换成壳层。

## 修改三：Video 显示帧页迁移到壳层

### 修改前

迁移前，`macOSVideoDisplayFrameEditorViewController` 也自己持有标题与取消按钮，并在 `setupConstraints()` 里把 player / slider / timeline 直接挂到标题栏下方。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: titleLabel / closeButton / loadView() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前 Video 页和 GIF 页一样，也在 controller 内部重复维护一套 sheet 顶栏。
private let titleLabel: NSTextField = {
    let label = NSTextField(labelWithString: "Set Display Frame")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 24, weight: .semibold)
    return label
}()
private let closeButton: NSButton = {
    let button = NSButton(title: "Cancel", target: nil, action: nil)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.controlSize = .large
    button.bezelStyle = .rounded
    button.keyEquivalent = "\u{1b}"
    return button
}()

override func loadView() {
    view = NSView()
}

private func setupViewHierarchy() {
    playerView.addSubview(playPauseButton)
    view.addSubview(titleLabel)
    view.addSubview(closeButton)
    view.addSubview(playerView)
    view.addSubview(currentTimeLabel)
    view.addSubview(timeSlider)
    view.addSubview(durationLabel)
    view.addSubview(timelineView)
    view.addSubview(setDisplayFrameButton)
}

private func setupConstraints() {
    let safeArea = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20),
        titleLabel.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 24),
        closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        closeButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -24),
        playerView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24)
        // ... 省略其余播放器与时间线约束 ...
    ])
}
```

### 修改后

迁移后，Video 页改为用 `shellView` 承载标题与右侧 `Cancel`，但保留它原有的“标题靠左、首次聚焦 timeSlider”的行为；播放器与时间线逻辑仍由原 controller 管理。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: shellView / closeButton / loadView()
// 功能说明: 修改后 Video 页复用公共壳层，但保留 leading 标题和 trailing Cancel 按钮的现有 sheet 结构。
private let shellView = macOSCanvasEditorShellView(
    titleAlignment: .leading
)

private var closeButton: NSButton {
    shellView.trailingButton
}

override func loadView() {
    view = shellView
}
```

Video 页的初始化和约束起点也随之变化：先配置壳层，再把 player / timeline 等内容视图挂进 `contentView`，约束起点从 `titleLabel.bottomAnchor` 改成 `contentView.topAnchor`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: viewDidLoad() / configureShell() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后 Video 页把公共顶栏移交给壳层，原有播放器、时间线和提交按钮只关注内容区布局。
override func viewDidLoad() {
    super.viewDidLoad()
    preferredContentSize = macOSCanvasEditorShellView.defaultPreferredContentSize
    configureShell()
    configureTimelineView()
    configureButtons()
    configurePlayer()
    setupViewHierarchy()
    setupConstraints()
    applyInitialState()
}

private func configureShell() {
    shellView.configureTitle(
        "Set Display Frame",
        alignment: .leading
    )
    shellView.setLeadingButtonHidden(true)
    shellView.setTrailingButtonHidden(false)

    closeButton.title = "Cancel"
    closeButton.keyEquivalent = "\u{1b}"
}

private func setupViewHierarchy() {
    playerView.addSubview(playPauseButton)
    shellView.contentView.addSubview(playerView)
    shellView.contentView.addSubview(currentTimeLabel)
    shellView.contentView.addSubview(timeSlider)
    shellView.contentView.addSubview(durationLabel)
    shellView.contentView.addSubview(timelineView)
    shellView.contentView.addSubview(setDisplayFrameButton)
}

private func setupConstraints() {
    let contentView = shellView.contentView
    let safeArea = contentView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        playerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
        playerView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 24),
        playerView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -24),
        timelineView.topAnchor.constraint(equalTo: currentTimeLabel.bottomAnchor, constant: 18),
        setDisplayFrameButton.bottomAnchor.constraint(
            lessThanOrEqualTo: safeArea.bottomAnchor,
            constant: -20
        )
        // ... 省略其余 player / slider / timeline 约束 ...
    ])
}
```

首次进入页面后把焦点给 `timeSlider` 的既有行为没有动，仍然保留在原 controller：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: viewDidAppear()
// 功能说明: 保留既有的首次聚焦行为，确保抽壳后 sheet 的键盘交互语义不回退。
override func viewDidAppear() {
    super.viewDidAppear()
    guard hasPerformedInitialSeek == false else {
        return
    }

    hasPerformedInitialSeek = true
    seekPreview(
        to: previewState.snapshot.currentTimeSeconds,
        pausePlayback: true,
        updateSlider: true,
        updateTimeline: true
    )
    view.window?.makeFirstResponder(timeSlider)
}
```

### 这一改动解决了什么

- Video 页不再重复实现公共顶栏。
- `Set Display Frame` 页保留了原来的标题靠左、右侧 `Cancel` 和首次聚焦 `timeSlider` 行为。
- 播放、拖动时间轴、提交显示帧图片这些业务逻辑没有被抽象层侵入。

## 与当前 changes 的对应关系

从当前工作区状态看，这次 `phase 3` 的真实业务改动就是：

1. 新增 `macOSCanvasEditorShellView.swift`
2. 修改 `macOSGIFFrameImportViewController.swift`
3. 修改 `macOSVideoDisplayFrameEditorViewController.swift`

而且这 `3` 个文件的职责边界是清晰的：

- 新文件负责公共 chrome
- 两个旧文件负责迁移接入
- 没有修改 `macOSViewController.swift`
- 没有修改 `iOS` 代码
- 没有修改 `Canvas` 领域层

## 验证结论

这次 `phase 3` 实际完成并验证到的部分是：

1. macOS 公共编辑器壳层已新增。
2. GIF macOS 页已迁移到壳层。
3. Video macOS 页已迁移到壳层。
4. macOS 工程编译通过。
5. 这 `3` 个文件的本地 lint 检查未发现新增问题。

尚未在本记录中声称已经完成的部分：

- macOS 上的手工视觉回归
- 网页页本身的实现
- toolbar 浏览器按钮接线

## 结论

本次 `phase 3` 的真实结果是：macOS 端已经完成公共编辑器壳层抽取，并将现有 `GIF` 与 `Video` 编辑页迁移到这一壳层上，达成“先解决 sheet 页面布局重复根因，再继续后续网页页接入”的目标；同时没有改动页面自身的业务状态机、提交流程、快捷键语义与 `presentAsSheet(...)` 入口。
