# 20260323_184329_boardlist_rename_phase4_more_button_anchor_record

## 记录范围

- 记录内容：
  1. 在 `iOS` / `macOS` 的 BoardList cell/item 中加入三点“更多操作”按钮。
  2. 为两端 cell/item 增加 anchor rect 回调，并把点击事件接到 controller 的 `presentRenameActionPanel(...)`。
  3. 同步更新 BoardList rename 实施计划中的 `cell-item-more-button` 状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `.cursor/plans/boardlist_rename_flow_07528e2b.plan.md`
- 本记录不包含：
  - 标题内联编辑控件
  - rename 提交与 `BoardStore.renameBoard(...)` 调用
  - rename 后回顶与显式滚动恢复
  - git commit / push

## 修改一：在 iOS Grid/List cell 中加入三点按钮与 anchor rect 回调

### 修改前

- `iOSBoardCollectionViewCell` 只有 `previewView`、`placeholderIconView`、`titleLabel`。
- `configure(...)` 也只接收 `entry`、`previewContent`、`displayMode` 三个参数，没有按钮点击回调或 anchor rect 输出能力。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: 属性定义 / configure(with:previewContent:displayMode:) / setupView() / setupConstraints()
// 功能说明: 修改前 iOS cell 只负责缩略图与标题展示，没有更多操作按钮，也没有将点击位置回传给 controller 的能力。
private let previewView = iOSBoardPreviewView()
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
private let titleLabel: UILabel = {
    let label = UILabel()
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .label
    label.numberOfLines = 2
    label.lineBreakMode = .byTruncatingTail
    return label
}()

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.text = entry.title
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
    contentView.layoutIfNeeded()
}

private func setupView() {
    contentView.layer.cornerRadius = 12
    contentView.layer.masksToBounds = true

    previewView.translatesAutoresizingMaskIntoConstraints = false
    placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(previewView)
    contentView.addSubview(placeholderIconView)
    contentView.addSubview(titleLabel)
}

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
    ]

    listConstraints = [
        previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        previewView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        previewView.widthAnchor.constraint(equalToConstant: 72),
        previewView.heightAnchor.constraint(equalToConstant: 72),
        titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
    ]
}
```

### 修改后

- 新增 `MoreActionsHandler` 类型别名和 `onMoreActionsRequested` 闭包。
- 新增 `moreButton`，图标使用 `ellipsis`。
- `configure(...)` 增加 `onMoreActionsRequested` 参数，controller 现在可以把按钮点击回调注入进来。
- Grid 模式把按钮放右上角，List 模式放标题右侧，placeholder 模式隐藏按钮。
- 新增 `handleMoreButtonTap()`，把 `boardID + anchorRect + sourceView` 回传给 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: 属性定义 / configure(with:previewContent:displayMode:onMoreActionsRequested:) / setupView() / setupConstraints()
// 功能说明: 修改后 iOS cell 开始承载三点按钮，并把点击位置转成 anchor rect 回调给 controller。
typealias MoreActionsHandler = (UUID, CGRect, UIView) -> Void

private let moreButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.accessibilityLabel = "More Actions"
    button.tintColor = .secondaryLabel

    var configuration = UIButton.Configuration.plain()
    configuration.image = UIImage(systemName: "ellipsis")
    configuration.contentInsets = NSDirectionalEdgeInsets(
        top: 6,
        leading: 6,
        bottom: 6,
        trailing: 6
    )
    configuration.baseForegroundColor = .secondaryLabel
    button.configuration = configuration
    return button
}()

private var onMoreActionsRequested: MoreActionsHandler?

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode,
    onMoreActionsRequested: MoreActionsHandler? = nil
) {
    cancelThumbnailRequest()
    representedBoardID = entry.boardID
    representedRevisionToken = entry.revisionToken
    titleLabel.text = entry.title
    self.onMoreActionsRequested = onMoreActionsRequested
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
    contentView.layoutIfNeeded()
}

private func setupView() {
    contentView.layer.cornerRadius = 12
    contentView.layer.masksToBounds = true

    previewView.translatesAutoresizingMaskIntoConstraints = false
    placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    moreButton.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(previewView)
    contentView.addSubview(placeholderIconView)
    contentView.addSubview(titleLabel)
    contentView.addSubview(moreButton)
    contentView.bringSubviewToFront(moreButton)
    moreButton.addTarget(self, action: #selector(handleMoreButtonTap), for: .touchUpInside)
}

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        moreButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        moreButton.widthAnchor.constraint(equalToConstant: 32),
        moreButton.heightAnchor.constraint(equalToConstant: 32),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
    ]

    listConstraints = [
        previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        previewView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        previewView.widthAnchor.constraint(equalToConstant: 72),
        previewView.heightAnchor.constraint(equalToConstant: 72),
        titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
        titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        moreButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        moreButton.widthAnchor.constraint(equalToConstant: 32),
        moreButton.heightAnchor.constraint(equalToConstant: 32)
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: applyPresentationStyle(_:) / handleMoreButtonTap()
// 功能说明: 修改后 iOS cell 会在 board 模式显示按钮、placeholder 模式隐藏按钮，并将按钮所在 rect 回传给 controller 作为 panel anchor。
private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
    NSLayoutConstraint.deactivate(
        gridConstraints +
            listConstraints +
            placeholderGridConstraints +
            placeholderListConstraints
    )

    previewView.isHidden = false
    placeholderIconView.isHidden = true
    moreButton.isHidden = true

    switch presentationStyle {
    case .boardGrid:
        titleLabel.textAlignment = .center
        moreButton.isHidden = false
        NSLayoutConstraint.activate(gridConstraints)
    case .boardList:
        titleLabel.textAlignment = .left
        moreButton.isHidden = false
        NSLayoutConstraint.activate(listConstraints)
    case .placeholderGrid:
        titleLabel.textAlignment = .center
        previewView.isHidden = true
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(placeholderGridConstraints)
    case .placeholderList:
        titleLabel.textAlignment = .left
        previewView.isHidden = true
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(placeholderListConstraints)
    }
}

@objc
private func handleMoreButtonTap() {
    guard let representedBoardID else {
        return
    }

    let anchorRect = contentView.convert(
        moreButton.bounds,
        from: moreButton
    )
    onMoreActionsRequested?(
        representedBoardID,
        anchorRect.standardized,
        contentView
    )
}
```

## 修改二：在 macOS Grid/List item 中加入三点按钮与 anchor rect 回调

### 修改前

- `macOSBoardCollectionItem` 也只有 preview / placeholder / title 三部分。
- `configure(...)` 同样没有按钮回调参数，Grid/List 布局里也没有预留三点按钮位置。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: 属性定义 / configure(with:previewContent:displayMode:) / setupView() / setupConstraints()
// 功能说明: 修改前 macOS item 只负责展示 board 缩略图和标题，没有更多操作按钮，也没有 anchor rect 回调。
private let previewView = macOSBoardPreviewView()
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
private let titleLabel: NSTextField = {
    let label = NSTextField(wrappingLabelWithString: "")
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .labelColor
    label.maximumNumberOfLines = 2
    label.lineBreakMode = .byTruncatingTail
    return label
}()

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode
) {
    cancelThumbnailRequest()
    representedEntryID = entry.id
    representedBoardID = entry.boardID
    representedTitle = entry.title
    representedDisplayMode = displayMode
    representedRevisionToken = entry.revisionToken
    titleLabel.stringValue = entry.title
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
    view.layoutSubtreeIfNeeded()
}

private func setupView() {
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.masksToBounds = true

    previewView.translatesAutoresizingMaskIntoConstraints = false
    placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewView)
    view.addSubview(placeholderIconView)
    view.addSubview(titleLabel)
}
```

### 修改后

- 新增 `MoreActionsHandler` 类型别名、`moreButton` 和 `onMoreActionsRequested`。
- `configure(...)` 增加 `onMoreActionsRequested` 参数。
- Grid 模式按钮位于右上角，List 模式按钮位于标题右侧；placeholder 模式隐藏。
- `handleMoreButtonClick(_:)` 会把 `boardID + anchorRect + sourceView` 回传给 controller。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: 属性定义 / configure(with:previewContent:displayMode:onMoreActionsRequested:) / setupView() / setupConstraints()
// 功能说明: 修改后 macOS item 与 iOS 对齐：新增三点按钮，并把按钮点击锚点上送到 controller。
typealias MoreActionsHandler = (UUID, CGRect, NSView) -> Void

private let moreButton: NSButton = {
    let button = NSButton()
    button.translatesAutoresizingMaskIntoConstraints = false
    button.isBordered = false
    button.setButtonType(.momentaryChange)
    button.image = NSImage(
        systemSymbolName: "ellipsis",
        accessibilityDescription: "More Actions"
    )
    button.imagePosition = .imageOnly
    button.contentTintColor = .secondaryLabelColor
    button.bezelStyle = .regularSquare
    return button
}()

private var onMoreActionsRequested: MoreActionsHandler?

func configure(
    with entry: BoardListEntry,
    previewContent: BoardPreviewContent,
    displayMode: BoardListDisplayMode,
    onMoreActionsRequested: MoreActionsHandler? = nil
) {
    cancelThumbnailRequest()
    representedEntryID = entry.id
    representedBoardID = entry.boardID
    representedTitle = entry.title
    representedDisplayMode = displayMode
    representedRevisionToken = entry.revisionToken
    self.onMoreActionsRequested = onMoreActionsRequested
    titleLabel.stringValue = entry.title
    previewView.apply(content: previewContent)
    applyPresentation(
        for: entry,
        displayMode: displayMode
    )
    view.layoutSubtreeIfNeeded()
}

private func setupView() {
    view.wantsLayer = true
    view.layer?.cornerRadius = 12
    view.layer?.masksToBounds = true

    previewView.translatesAutoresizingMaskIntoConstraints = false
    placeholderIconView.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    moreButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewView)
    view.addSubview(placeholderIconView)
    view.addSubview(titleLabel)
    view.addSubview(moreButton)
    moreButton.target = self
    moreButton.action = #selector(handleMoreButtonClick(_:))
}

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        moreButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        moreButton.widthAnchor.constraint(equalToConstant: 32),
        moreButton.heightAnchor.constraint(equalToConstant: 32),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
    ]

    listConstraints = [
        previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        previewView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        previewView.widthAnchor.constraint(equalToConstant: 72),
        previewView.heightAnchor.constraint(equalToConstant: 72),
        titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
        titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        moreButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        moreButton.widthAnchor.constraint(equalToConstant: 32),
        moreButton.heightAnchor.constraint(equalToConstant: 32)
    ]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: applyPresentationStyle(_:) / handleMoreButtonClick(_:)
// 功能说明: 修改后 macOS item 在 board 模式显示三点按钮，并将按钮的当前 frame 回传给 controller 作为面板锚点。
private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
    NSLayoutConstraint.deactivate(
        gridConstraints +
            listConstraints +
            placeholderGridConstraints +
            placeholderListConstraints
    )

    previewView.isHidden = false
    placeholderIconView.isHidden = true
    moreButton.isHidden = true

    switch presentationStyle {
    case .boardGrid:
        titleLabel.alignment = .center
        moreButton.isHidden = false
        NSLayoutConstraint.activate(gridConstraints)
    case .boardList:
        titleLabel.alignment = .left
        moreButton.isHidden = false
        NSLayoutConstraint.activate(listConstraints)
    case .placeholderGrid:
        titleLabel.alignment = .center
        previewView.isHidden = true
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(placeholderGridConstraints)
    case .placeholderList:
        titleLabel.alignment = .left
        previewView.isHidden = true
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(placeholderListConstraints)
    }
}

@objc
private func handleMoreButtonClick(_ sender: NSButton) {
    guard let representedBoardID else {
        return
    }

    let anchorRect = view.convert(
        sender.bounds,
        from: sender
    )
    onMoreActionsRequested?(
        representedBoardID,
        anchorRect.standardized,
        view
    )
}
```

## 修改三：在 iOS / macOS controller 中把按钮回调接到 `presentRenameActionPanel(...)`

### 修改前

- 两端 controller 在 `cellForItemAt` / `itemForRepresentedObjectAt` 中调用 `configure(...)` 时，只传基础展示参数。
- 即使 controller 在 Phase 3 已经有 `presentRenameActionPanel(...)`，修改前也没有任何 cell/item 会触发它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: collectionView(_:cellForItemAt:)
// 功能说明: 修改前 iOS controller 只把 entry、preview 和 displayMode 传给 cell，不会接收三点按钮点击回调。
cell.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改前 macOS controller 同样没有把更多操作回调注入 item，因此 action panel 入口还未打通。
item.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode
)
```

### 修改后

- 两端 controller 都在 `configure(...)` 时传入 `onMoreActionsRequested` 闭包。
- 闭包内部直接调用 Phase 3 已有的 `presentRenameActionPanel(...)`，把 `boardID`、`anchorRect` 和 `sourceView` 原样转交。
- 至此，“三点按钮 -> controller -> action panel” 这条链已经打通。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: collectionView(_:cellForItemAt:)
// 功能说明: 修改后 iOS controller 在配置 cell 时注入三点按钮回调，点击后可直接弹出 rename action panel。
cell.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode,
    onMoreActionsRequested: { [weak self] boardID, anchorRect, sourceView in
        self?.presentRenameActionPanel(
            for: boardID,
            anchorRect: anchorRect,
            from: sourceView
        )
    }
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改后 macOS controller 也把三点按钮回调接到了现有的 presentRenameActionPanel(...)，两端行为对齐。
item.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode,
    onMoreActionsRequested: { [weak self] boardID, anchorRect, sourceView in
        self?.presentRenameActionPanel(
            for: boardID,
            anchorRect: anchorRect,
            from: sourceView
        )
    }
)
```

## 修改四：同步计划文件中的 Phase 4 完成状态

### 修改前

- BoardList rename 计划里，`cell-item-more-button` 仍是 `pending`。
- 这会让“按钮和回调链已经落地”和“计划状态还未完成”之间出现偏差。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改前，Phase 4 的 cell-item-more-button 任务仍标记为 pending。
todos:
  - id: cell-item-more-button
    content: 在 iOS/macOS Grid/List cell/item 中加入三点按钮与回调锚点
    status: pending
```

### 修改后

- 将 `cell-item-more-button` 标记为 `completed`。
- 这只是实施进度同步，不改变运行时逻辑。

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（计划 frontmatter）
# 功能说明: 修改后，Phase 4 的 cell-item-more-button 任务已与当前代码实现同步为 completed。
todos:
  - id: cell-item-more-button
    content: 在 iOS/macOS Grid/List cell/item 中加入三点按钮与回调锚点
    status: completed
```

## 当前边界说明

- 本次 Phase 4 已经让三点按钮出现，并能通过 controller 弹出 action panel。
- 但 action panel 里的 `Rename` 目前还只会把控制器切到 `editingBoardID` 状态，真正的标题内联编辑控件还没有接入。
- 因此当前行为是：“按钮可见、面板可弹”，但“点击 `Rename` 进入编辑态”要等后续 Phase 5。

## 验证情况

- `ReadLints` 检查：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift` 无新增 linter 问题。
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift` 无新增 linter 问题。
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift` 无新增 linter 问题。
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift` 无新增 linter 问题。
- 类型检查：
  - 已执行 `xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift`
  - 结果通过。

## 当前阶段结论

- Phase 4 已完成：BoardList 的 Grid/List 入口现在已经具备三点按钮，并能把点击锚点传到 controller 打开 action panel。
- 下一阶段可以直接实施 Phase 5，把 `Rename` 动作真正接到标题内联编辑流。 
