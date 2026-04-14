# 20260414_093411_phase2_ios_editor_shell_record

## 记录说明

本记录基于本次 `phase 2` 的实际 `git status`、`git diff --stat`、当前代码状态与构建结果整理，不包含原始 `git diff` 文本。

本次业务代码实际涉及 `3` 个 iOS 文件：

- `MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示本次工作区只有 `3` 个 phase2 相关变更：`1` 个新增文件、`2` 个已修改文件
- `git diff --stat` 显示两个已修改 controller 的净改动规模为 `2 files changed, 72 insertions(+), 104 deletions(-)`
- `git diff --no-index --stat -- /dev/null "MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift"` 显示新增壳层文件规模为 `1 file changed, 189 insertions(+)`
- `xcodebuild build -destination "generic/platform=iOS"` 已通过，说明本次 iOS 壳层抽取在编译层面成立
- `ReadLints` 检查这 `3` 个 iOS 文件时未发现新增 lint 问题

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对现有计划 `.md` 文件的改写

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date '+%Y%m%d_%H%M%S'
#
# 实际输出:
# 20260414_093411
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 记录写入本文件前的真实工作区状态，确认 phase2 只涉及 3 个 iOS 文件。
git status --short --branch
#
# 实际输出:
# ## feat/cross-platform-input-indicator
#  M MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
#  M MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
# ?? MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计两个现有 iOS 编辑器页面迁移到壳层后的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift"
#
# 实际输出:
# .../iOS/iOSGIFFrameImportViewController.swift      | 98 +++++++++-------------
# .../iOSVideoDisplayFrameEditorViewController.swift | 78 ++++++++---------
# 2 files changed, 72 insertions(+), 104 deletions(-)
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --no-index --stat
# 功能说明: 统计新增 iOS 公共编辑器壳层文件的真实改动规模。
git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift"
#
# 实际输出:
# .../Platform/iOS/iOSCanvasEditorShellView.swift    | 189 +++++++++++++++++++++
# 1 file changed, 189 insertions(+)
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证本次 iOS 壳层抽取后的工程仍可面向 iOS 成功编译。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

## 本次修改的真实目标

这一步落实的是计划里的 `phase 2`：先在 `iOS` 端抽出可复用的编辑器壳层，然后把 `GIF` 与 `Video` 两个现有页面迁移上去。

真实目标不是增加新功能，而是解决当前架构里的重复布局根因：

1. 不再让 `iOSGIFFrameImportViewController` 自己持有标题、取消、导入这套 header chrome。
2. 不再让 `iOSVideoDisplayFrameEditorViewController` 自己重复持有标题、关闭按钮和顶栏安全区布局。
3. 把顶栏标题、左右 accessory button 和内容容器抽成一个复用壳层。
4. 保留两个页面各自原有的业务逻辑、交互、提交和弹出方式不变，只更换承载结构。

## 修改一：新增 iOS 公共编辑器壳层

### 修改前

修改前，`Platform/iOS` 下不存在一个统一承载编辑器顶栏与内容区的公共壳层；`GIF` 和 `Video` 页面都各自定义一套 `titleLabel`、按钮和顶部布局。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift
// 函数名/符号名: 新增前不存在
// 功能说明: 修改前仓库中没有 iOS 端的公共编辑器壳层视图，公共 chrome 只能分散在各个 editor controller 内部重复实现。
// 文件状态: 不存在
```

### 修改后

新增 `iOSCanvasEditorShellView`，把标题、左右按钮和内容容器做成一个复用视图，并支持 `centered` / `leading` 两种标题对齐模式。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift
// 函数名/符号名: iOSCanvasEditorShellTitleAlignment / iOSCanvasEditorShellView
// 功能说明: 新增可复用的 iOS 编辑器壳层，把公共 header chrome 和内容容器从具体 controller 中抽离出来。
#if os(iOS)
import UIKit

enum iOSCanvasEditorShellTitleAlignment {
    case centered
    case leading
}

final class iOSCanvasEditorShellView: UIView {
    private enum Layout {
        static let titleTopInset: CGFloat = 20
        static let horizontalInset: CGFloat = 24
        static let titleAccessorySpacing: CGFloat = 12
    }

    let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 28, weight: .semibold)
        return label
    }()

    let leadingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        var configuration = UIButton.Configuration.plain()
        configuration.title = ""
        button.configuration = configuration
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    let trailingButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    let contentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
```

壳层里最关键的不是单纯把控件挪到一起，而是把“标题对齐模式”“按钮隐藏时的零尺寸约束”“contentView 与 header 的关系”都收口成统一接口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSCanvasEditorShellView.swift
// 函数名/符号名: init(titleAlignment:) / configureTitle(_:alignment:) / setLeadingButtonHidden(_:) / setTrailingButtonHidden(_:) / updateTitleAlignment()
// 功能说明: 新增壳层的布局与行为入口，让 GIF 和 Video 页面可以复用同一套 header 结构，但保留不同的标题对齐与按钮显隐策略。
    private var contentTopToTitleConstraint: NSLayoutConstraint!
    private var leadingButtonZeroWidthConstraint: NSLayoutConstraint!
    private var leadingButtonZeroHeightConstraint: NSLayoutConstraint!
    private var trailingButtonZeroWidthConstraint: NSLayoutConstraint!
    private var trailingButtonZeroHeightConstraint: NSLayoutConstraint!
    private var centeredTitleConstraints: [NSLayoutConstraint] = []
    private var leadingTitleConstraints: [NSLayoutConstraint] = []
    private var titleAlignment: iOSCanvasEditorShellTitleAlignment

    init(
        titleAlignment: iOSCanvasEditorShellTitleAlignment
    ) {
        self.titleAlignment = titleAlignment
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .systemBackground
        addSubview(titleLabel)
        addSubview(leadingButton)
        addSubview(trailingButton)
        addSubview(contentView)

        // 先创建通用约束，再根据标题对齐模式切换不同的 title 约束组。
        contentTopToTitleConstraint = contentView.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor
        )
        contentTopToTitleConstraint.priority = .defaultHigh
        // ... 省略其余按钮零尺寸约束与 title 对齐约束创建 ...
        updateTitleAlignment()
    }

    func configureTitle(
        _ title: String,
        alignment: iOSCanvasEditorShellTitleAlignment
    ) {
        titleLabel.text = title
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

- 给 iOS 端现有编辑器页提供了统一的外层 chrome 承载结构。
- 把 header / safe area / 内容容器的重复布局从具体 controller 中抽离出来。
- 为后续 `phase 4` 的网页页预留了复用壳层，而不是继续复制第三套布局。

## 修改二：GIF 选帧页迁移到壳层

### 修改前

迁移前，`iOSGIFFrameImportViewController` 自己维护标题、取消、导入按钮和整套顶栏约束；它既负责选帧业务，又负责 header chrome。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 函数名/符号名: titleLabel / cancelButton / importButton / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前 GIF 页自己持有并布局 header chrome，controller 同时承担公共外壳与页面业务。
private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 28, weight: .semibold)
    label.text = "Import GIF Frames"
    return label
}()
private let cancelButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.plain()
    configuration.title = "Cancel"
    button.configuration = configuration
    return button
}()
private let importButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private func setupViewHierarchy() {
    view.addSubview(titleLabel)
    view.addSubview(cancelButton)
    view.addSubview(importButton)
    view.addSubview(summaryLabel)
    view.addSubview(collectionView)
}

private func setupConstraints() {
    let safeArea = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        titleLabel.topAnchor.constraint(
            equalTo: safeArea.topAnchor,
            constant: Layout.titleTopInset
        ),
        titleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
        cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        importButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        summaryLabel.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor,
            constant: Layout.summaryTopSpacing
        )
        // ... 省略其余约束 ...
    ])
}
```

### 修改后

迁移后，GIF 页不再持有独立的标题与左右按钮，而是改为通过 `shellView` 暴露的 `leadingButton` / `trailingButton` 接线，并把自己的内容挂到 `shellView.contentView` 下。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 函数名/符号名: shellView / cancelButton / importButton / loadView()
// 功能说明: 修改后 GIF 页把公共 chrome 交给壳层，只保留选帧页自己的 summary 与 collection 业务视图。
private let shellView = iOSCanvasEditorShellView(
    titleAlignment: .centered
)

private var cancelButton: UIButton {
    shellView.leadingButton
}

private var importButton: UIButton {
    shellView.trailingButton
}

override func loadView() {
    view = shellView
}
```

页面初始化流程也从“直接给根 view 上色并布局 header”改成“先配置壳层，再挂接自己的业务内容区”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 函数名/符号名: viewDidLoad() / configureShell() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后 GIF 页把标题、按钮文案和内容容器入口交给壳层，自己的布局只处理 summary 与 collection。
override func viewDidLoad() {
    super.viewDidLoad()
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

    var configuration = UIButton.Configuration.plain()
    configuration.title = "Cancel"
    cancelButton.configuration = configuration
}

private func setupViewHierarchy() {
    shellView.contentView.addSubview(summaryLabel)
    shellView.contentView.addSubview(collectionView)
}

private func setupConstraints() {
    let contentView = shellView.contentView
    let safeArea = contentView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        summaryLabel.topAnchor.constraint(
            equalTo: contentView.topAnchor,
            constant: Layout.summaryTopSpacing
        ),
        collectionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        collectionView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        collectionView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
}
```

同时，缩略图 grid 的安全区底部计算也不再依赖整个 controller 根视图，而是对齐到壳层内容区：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 函数名/符号名: updateCollectionLayout()
// 功能说明: 修改后 collection 的底部 inset 以壳层内容区的 safe area 为准，避免公共 chrome 改造后仍然引用旧根视图。
private func updateCollectionLayout() {
    let selectionGrid = editorContext.selectionGrid
    let safeAreaInsets = shellView.contentView.safeAreaInsets
    collectionViewLayout.sectionInset = UIEdgeInsets(
        top: selectionGrid.contentInsets.top,
        left: selectionGrid.contentInsets.leading,
        bottom: selectionGrid.contentInsets.bottom + safeAreaInsets.bottom,
        right: selectionGrid.contentInsets.trailing
    )
    // ... 省略其余 itemSize 计算 ...
}
```

### 这一改动解决了什么

- GIF 页不再重复实现顶栏 chrome。
- GIF 页的 controller 职责被收窄到“选帧业务 + 内容区布局”。
- 中间标题、左 Cancel、右 Import 的现有视觉结构被保留下来，只是来源从本地控件切换成了壳层。

## 修改三：Video 显示帧页迁移到壳层

### 修改前

迁移前，`iOSVideoDisplayFrameEditorViewController` 也自己持有标题与关闭按钮，并在 `setupConstraints()` 里直接把 player/time slider/timeline 挂到标题栏下方。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: titleLabel / closeButton / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前 Video 页和 GIF 页一样，也在 controller 内部重复持有一套 header chrome。
private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 28, weight: .semibold)
    label.text = "Set Display Frame"
    return label
}()
private let closeButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.plain()
    configuration.title = "Close"
    button.configuration = configuration
    return button
}()

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
        titleLabel.topAnchor.constraint(
            equalTo: safeArea.topAnchor,
            constant: 20
        ),
        titleLabel.leadingAnchor.constraint(
            equalTo: safeArea.leadingAnchor,
            constant: 24
        ),
        closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        closeButton.trailingAnchor.constraint(
            equalTo: safeArea.trailingAnchor,
            constant: -24
        ),
        playerView.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor,
            constant: 24
        )
        // ... 省略其余时间轴与提交按钮约束 ...
    ])
}
```

### 修改后

迁移后，Video 页改为用 `shellView` 承载标题与关闭按钮，但保留它原有的“标题靠左、Close 在右”的交互样式；页面自己的 player / timeline / commit button 仍由原 controller 管理。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: shellView / closeButton / loadView()
// 功能说明: 修改后 Video 页复用公共壳层，但保留 leading 标题和 trailing Close 按钮的现有结构。
private let shellView = iOSCanvasEditorShellView(
    titleAlignment: .leading
)

private var closeButton: UIButton {
    shellView.trailingButton
}

override func loadView() {
    view = shellView
}
```

Video 页的初始化和约束起点也随之变化：先配置壳层，再把 player / timeline 等业务视图挂进 `contentView`，约束起点从 `titleLabel.bottomAnchor` 改成 `contentView.topAnchor`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 函数名/符号名: viewDidLoad() / configureShell() / setupViewHierarchy() / setupConstraints()
// 功能说明: 修改后 Video 页把公共顶栏移交给壳层，原有播放器与时间线业务视图只关注内容区。
override func viewDidLoad() {
    super.viewDidLoad()
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

    var configuration = UIButton.Configuration.plain()
    configuration.title = "Close"
    closeButton.configuration = configuration
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
        playerView.topAnchor.constraint(
            equalTo: contentView.topAnchor,
            constant: 24
        ),
        playerView.leadingAnchor.constraint(
            equalTo: safeArea.leadingAnchor,
            constant: 24
        ),
        playerView.trailingAnchor.constraint(
            equalTo: safeArea.trailingAnchor,
            constant: -24
        )
        // ... 省略其余 player/time/timeline 约束 ...
    ])
}
```

### 这一改动解决了什么

- Video 页也不再重复实现公共顶栏。
- `Set Display Frame` 页保留了既有的标题靠左和 Close 按钮行为，没有被 GIF 页的居中标题方案强行同化。
- 具体的播放、拖动时间轴、提交当前帧图片逻辑仍留在原 controller，没有被抽象层侵入。

## 与当前 changes 的对应关系

从当前工作区状态看，这次 `phase 2` 的真实业务改动就是：

1. 新增 `iOSCanvasEditorShellView.swift`
2. 修改 `iOSGIFFrameImportViewController.swift`
3. 修改 `iOSVideoDisplayFrameEditorViewController.swift`

而且这 3 个文件的职责边界是清晰的：

- 新文件负责公共 chrome
- 两个旧文件负责迁移接入
- 没有修改 `iOSViewController.swift`
- 没有修改 `macOS` 代码
- 没有修改 `Canvas` 领域层

## 验证结论

这次 `phase 2` 我实际完成并验证到的部分是：

1. iOS 公共编辑器壳层已新增。
2. GIF iOS 页已迁移到壳层。
3. Video iOS 页已迁移到壳层。
4. iOS 工程编译通过。
5. 这 3 个文件的本地 lint 检查未发现新增问题。

尚未在本记录中声称已经完成的部分：

- iPhone 真机/模拟器上的手动视觉回归
- macOS 对应壳层抽取
- 网页页本身的实现

## 结论

本次 `phase 2` 的真实结果是：iOS 端已经完成公共编辑器壳层抽取，并将现有 `GIF` 与 `Video` 编辑页迁移到这一壳层上，达成“先解决布局重复根因，再继续后续网页页接入”的目标；同时没有改动页面自身的业务状态机、提交流程和弹出方式。
