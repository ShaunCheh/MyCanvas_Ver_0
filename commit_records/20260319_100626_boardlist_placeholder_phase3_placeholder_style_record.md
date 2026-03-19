# 20260319_100626_boardlist_placeholder_phase3_placeholder_style_record

## 记录范围

- 记录目标：落实 `BoardList` 占位项方案的阶段 3，把 `New Board` 占位项真正绘制成独立样式。
- 本阶段目的 1：让占位项在 `Grid` 模式下显示为空矩形卡片，并在预览区中心显示 `+` 图标。
- 本阶段目的 2：让占位项在 `List` 模式下显示为空行，而不是继续伪装成一个缩略图行。
- 本阶段目的 3：把 placeholder 的样式状态机固化在双端 cell/item 内部，而不是污染 shared preview / thumbnail 链。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本记录不包含：阶段 4 的交互细化。
- 本记录不包含：shared preview renderer 改造。
- 本记录不包含：git commit。

## 修改一：双端 cell/item 新增 placeholder 专属的展示状态机

### 修改前

- 双端 cell/item 都只有真实 board 的 grid/list 两种布局语义。
- `configure(...)` 虽然在阶段 2 已经切到 `BoardListEntry`，但视觉上仍然只有：
- previewView
- titleLabel
- `displayMode` 只会切换：
- `gridConstraints`
- `listConstraints`
- 这意味着 placeholder 仍然只是“空 preview + New Board 标题”的临时形态，没有真正表现出“创建入口”的样子。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.configure(with:previewContent:displayMode:) / applyDisplayMode(_:)
// 功能说明: 修改前 macOS cell 只按 board 的 grid/list 两套布局切换，没有 placeholder 的专属展示状态。
private let previewView = macOSBoardPreviewView()
private let titleLabel: NSTextField = {
    let label = NSTextField(wrappingLabelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .labelColor
    label.maximumNumberOfLines = 2
    label.lineBreakMode = .byTruncatingTail
    return label
}()

private var gridConstraints: [NSLayoutConstraint] = []
private var listConstraints: [NSLayoutConstraint] = []

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.stringValue = entry.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
}

private func applyDisplayMode(_ displayMode: BoardListDisplayMode) {
    NSLayoutConstraint.deactivate(gridConstraints + listConstraints)

    switch displayMode {
    case .grid:
        titleLabel.alignment = .center
        NSLayoutConstraint.activate(gridConstraints)
    case .list:
        titleLabel.alignment = .left
        NSLayoutConstraint.activate(listConstraints)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.configure(with:previewContent:displayMode:) / applyDisplayMode(_:)
// 功能说明: 修改前 iOS cell 同样没有 placeholder 的独立状态，只会在真实 board 的 grid/list 约束之间切换。
private let previewView = iOSBoardPreviewView()
private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .label
    label.numberOfLines = 2
    label.lineBreakMode = .byTruncatingTail
    return label
}()

private var gridConstraints: [NSLayoutConstraint] = []
private var listConstraints: [NSLayoutConstraint] = []

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.text = entry.title
    previewView.apply(content: previewContent)
    applyDisplayMode(displayMode)
}
```

### 修改后

- 双端 cell/item 都新增 `PresentationStyle`：
- `boardGrid`
- `boardList`
- `placeholderGrid`
- `placeholderList`
- `configure(...)` 不再直接按 `displayMode` 决定约束，而是先根据：
- `entry.isPlaceholder`
- `displayMode`
- 推导出最终 `PresentationStyle`
- 然后统一走 `applyPresentationStyle(...)`。
- 这样占位项样式从阶段 3 开始就成为一个真正的独立状态，而不是继续靠 `.empty` 假装。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.PresentationStyle / applyPresentation(for:displayMode:) / resolvePresentationStyle(for:displayMode:)
// 功能说明: 修改后 macOS 把 board / placeholder 和 grid / list 的组合显式收口成四种展示状态，避免样式分支继续散落。
private enum PresentationStyle {
    case boardGrid
    case boardList
    case placeholderGrid
    case placeholderList
}

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.stringValue = entry.title
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
}

private func applyPresentation(
    for entry: BoardListEntry,
    displayMode: BoardListDisplayMode
) {
    applyPresentationStyle(
        resolvePresentationStyle(
            for: entry,
            displayMode: displayMode
        )
    )
}

private func resolvePresentationStyle(
    for entry: BoardListEntry,
    displayMode: BoardListDisplayMode
) -> PresentationStyle {
    switch (entry.isPlaceholder, displayMode) {
    case (false, .grid):
        return .boardGrid
    case (false, .list):
        return .boardList
    case (true, .grid):
        return .placeholderGrid
    case (true, .list):
        return .placeholderList
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.PresentationStyle / applyPresentation(for:displayMode:) / resolvePresentationStyle(for:displayMode:)
// 功能说明: 修改后 iOS cell 与 macOS 保持同一套四态展示模型，后续阶段 4 不需要再回头拆布局状态机。
private enum PresentationStyle {
    case boardGrid
    case boardList
    case placeholderGrid
    case placeholderList
}

private func applyPresentation(
    for entry: BoardListEntry,
    displayMode: BoardListDisplayMode
) {
    applyPresentationStyle(
        resolvePresentationStyle(
            for: entry,
            displayMode: displayMode
        )
    )
}

private func resolvePresentationStyle(
    for entry: BoardListEntry,
    displayMode: BoardListDisplayMode
) -> PresentationStyle {
    switch (entry.isPlaceholder, displayMode) {
    case (false, .grid):
        return .boardGrid
    case (false, .list):
        return .boardList
    case (true, .grid):
        return .placeholderGrid
    case (true, .list):
        return .placeholderList
    }
}
```

## 修改二：Grid 模式下给 placeholder 加入居中 `+` 图标，形成空矩形卡片

### 修改前

- 占位项在 `Grid` 下只是沿用真实 board 的卡片骨架。
- preview 区虽然是空的，但没有任何明确的创建语义。
- 用户看到的只是“一个没内容的格子”，不是“可以点的新建入口”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.setupView() / setupConstraints()
// 功能说明: 修改前 macOS 的 Grid 布局里只有 previewView 和 titleLabel，没有 placeholder 图标层。
private func setupView() {
    previewView.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewView)
    view.addSubview(titleLabel)
}

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.setupView() / setupConstraints()
// 功能说明: 修改前 iOS 的 Grid 布局也没有单独的 placeholder 图标，只能显示一个空 preview 壳。
private func setupView() {
    previewView.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(previewView)
    contentView.addSubview(titleLabel)
}
```

### 修改后

- 双端都新增 `placeholderIconView`。
- `Grid` 下：
- 继续复用 preview 壳层
- 在 preview 中心叠一个 `+`
- 标题居中对齐，继续显示 `New Board`
- 这样形成的视觉就是“空矩形卡片 + 中心图标 + 标题”，符合占位入口语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.placeholderIconView / placeholderGridIconConstraints / applyPresentationStyle(_:)
// 功能说明: 修改后 macOS 在 Grid placeholder 上叠加居中的 plus 图标，把空 preview 壳层明确转成创建卡片。
private let placeholderIconView: NSImageView = {
    let configuration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
    let image = NSImage(
        systemSymbolName: "plus",
        accessibilityDescription: BoardListEntry.newBoardTitle
    )?.withSymbolConfiguration(configuration)
    let imageView = NSImageView(image: image ?? NSImage())
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.contentTintColor = .controlAccentColor
    imageView.isHidden = true
    return imageView
}()

placeholderGridIconConstraints = [
    placeholderIconView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
    placeholderIconView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
    placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
    placeholderIconView.heightAnchor.constraint(equalToConstant: 22)
]

case .placeholderGrid:
    titleLabel.alignment = .center
    placeholderIconView.isHidden = false
    NSLayoutConstraint.activate(gridConstraints + placeholderGridIconConstraints)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.placeholderIconView / placeholderGridIconConstraints / applyPresentationStyle(_:)
// 功能说明: 修改后 iOS 的 Grid placeholder 与 macOS 保持一致，使用 preview 中央的 plus 图标强化“新建入口”语义。
private let placeholderIconView: UIImageView = {
    let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
    let imageView = UIImageView(
        image: UIImage(
            systemName: "plus",
            withConfiguration: configuration
        )
    )
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = .systemBlue
    imageView.isHidden = true
    return imageView
}()

placeholderGridIconConstraints = [
    placeholderIconView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
    placeholderIconView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
    placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
    placeholderIconView.heightAnchor.constraint(equalToConstant: 22)
]

case .placeholderGrid:
    titleLabel.textAlignment = .center
    placeholderIconView.isHidden = false
    NSLayoutConstraint.activate(gridConstraints + placeholderGridIconConstraints)
```

## 修改三：List 模式下让 placeholder 变成空行，而不是继续显示缩略图框

### 修改前

- 占位项在 `List` 模式下完全复用真实 board 的 list 布局：
- 左侧固定 `72x72 previewView`
- 右侧是标题
- 即便 preview 为空，看起来也还是一条“空缩略图行”，而不是一个“空行式新建入口”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.listConstraints / applyDisplayMode(_:)
// 功能说明: 修改前 macOS 的 List 模式不区分 placeholder 和真实 board，左侧总是保留 72x72 preview。
listConstraints = [
    previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    previewView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    previewView.widthAnchor.constraint(equalToConstant: 72),
    previewView.heightAnchor.constraint(equalToConstant: 72),
    titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
]
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.listConstraints / applyDisplayMode(_:)
// 功能说明: 修改前 iOS 的 List 模式同样总是保留左侧 previewView，placeholder 看起来只是空缩略图。
listConstraints = [
    previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    previewView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    previewView.widthAnchor.constraint(equalToConstant: 72),
    previewView.heightAnchor.constraint(equalToConstant: 72),
    titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
]
```

### 修改后

- 双端都新增 `placeholderListConstraints`。
- `List` 下的 placeholder：
- 直接隐藏 `previewView`
- 左侧改成一个行级 `+` 图标
- 右侧继续显示 `New Board`
- 这让它从“空缩略图行”变成了真正的“空行式创建入口”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.placeholderListConstraints / applyPresentationStyle(_:)
// 功能说明: 修改后 macOS 的 List placeholder 直接隐藏 previewView，改为 plus 图标加标题的空行结构。
placeholderListConstraints = [
    placeholderIconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
    placeholderIconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
    placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
    titleLabel.leadingAnchor.constraint(equalTo: placeholderIconView.trailingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
]

case .placeholderList:
    titleLabel.alignment = .left
    previewView.isHidden = true
    placeholderIconView.isHidden = false
    NSLayoutConstraint.activate(placeholderListConstraints)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.placeholderListConstraints / applyPresentationStyle(_:)
// 功能说明: 修改后 iOS 的 List placeholder 也不再显示缩略图框，而是改成加号图标加标题的一条空行。
placeholderListConstraints = [
    placeholderIconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
    placeholderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
    placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
    titleLabel.leadingAnchor.constraint(equalTo: placeholderIconView.trailingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
]

case .placeholderList:
    titleLabel.textAlignment = .left
    previewView.isHidden = true
    placeholderIconView.isHidden = false
    NSLayoutConstraint.activate(placeholderListConstraints)
```

## 修改四：复用重置时补齐 placeholder 可见性恢复，避免样式串用

### 修改前

- `prepareForReuse()` 只会：
- 取消 thumbnail request
- 清空 `representedBoardID / representedRevisionToken`
- 清空标题
- 把 preview 置成 `.empty`
- 如果直接在 cell 内引入 placeholder 图标和隐藏 preview 的逻辑，而不补复用重置，就会出现真实 board 复用到 placeholder 样式的问题。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.prepareForReuse()
// 功能说明: 修改前 macOS 复用重置只覆盖真实 board 相关状态，还没有 placeholder 可见性恢复逻辑。
override func prepareForReuse() {
    super.prepareForReuse()
    cancelThumbnailRequest()
    representedBoardID = nil
    representedRevisionToken = nil
    titleLabel.stringValue = ""
    previewView.apply(content: .empty)
}
```

### 修改后

- 双端 `prepareForReuse()` 都补上：
- `previewView.isHidden = false`
- `placeholderIconView.isHidden = true`
- 这样即使一个 placeholder cell 被复用成真实 board，也不会残留图标或错误隐藏 preview。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.prepareForReuse()
// 功能说明: 修改后 macOS 会在复用时显式恢复 previewView 与 placeholderIconView 的默认可见性，避免样式串用。
override func prepareForReuse() {
    super.prepareForReuse()
    cancelThumbnailRequest()
    representedBoardID = nil
    representedRevisionToken = nil
    titleLabel.stringValue = ""
    previewView.isHidden = false
    placeholderIconView.isHidden = true
    previewView.apply(content: .empty)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.prepareForReuse()
// 功能说明: 修改后 iOS 复用时也同步恢复 preview 与 placeholder 图标的默认状态，保证 board / placeholder 之间切换不串样式。
override func prepareForReuse() {
    super.prepareForReuse()
    cancelThumbnailRequest()
    representedBoardID = nil
    representedRevisionToken = nil
    titleLabel.text = nil
    previewView.isHidden = false
    placeholderIconView.isHidden = true
    previewView.apply(content: .empty)
}
```

## 阶段结果

- 阶段 3 完成后，`New Board` 已经不再只是“空 preview + 标题”的临时占位，而是双端都有独立视觉语义的创建入口。
- `Grid` 下是空矩形卡片 + 中心 `+` 图标 + `New Board`。
- `List` 下是空行 + 行级 `+` 图标 + `New Board`。
- 这次实现仍然把 placeholder 样式限制在双端 cell/item 内部，没有改动 shared preview / thumbnail 管线，为后续阶段 4 的交互细化保留了清晰边界。

## 验证情况

- 已对以下文件执行 lint 检查，未发现新增问题：
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本次没有执行工程级编译验证。
