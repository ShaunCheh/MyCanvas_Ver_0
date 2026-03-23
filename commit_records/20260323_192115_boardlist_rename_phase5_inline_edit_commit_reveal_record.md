# 20260323_192115_boardlist_rename_phase5_inline_edit_commit_reveal_record

## 记录范围

- 记录内容：
  1. 为 `iOS` / `macOS` 的 BoardList cell/item 增加标题内联编辑控件。
  2. 在两端 controller 中接上 rename 提交、错误提示、聚焦恢复、排序回顶后的显式滚动恢复。
  3. 同步更新 BoardList rename 实施计划中的 `inline-rename-flow` 状态。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `.cursor/plans/boardlist_rename_flow_07528e2b.plan.md`
- 本记录不包含：
  - `Grid/List` 的手工运行时回归验证
  - git commit / push

## 修改一：iOS cell 从静态标题升级为内联编辑标题

### 修改前

- `iOSBoardCollectionViewCell` 已经有三点按钮，但标题仍然只有 `titleLabel`。
- `configure(...)` 只能接收更多操作回调，不能表达“当前是否处于 rename 编辑态”，也不能把编辑后的标题提交给 controller。
- `applyPresentationStyle(_:)` 只负责 board / placeholder 的展示切换，没有“标题 label 与编辑输入框互斥显示”的逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: 类声明 / configure(with:previewContent:displayMode:onMoreActionsRequested:) / setupView() / applyPresentationStyle(_:)
// 功能说明: 修改前 iOS cell 只能展示标题与更多按钮，Rename 还不能把标题切换成可编辑输入框。
final class iOSBoardCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "iOSBoardCollectionViewCell"

    typealias MoreActionsHandler = (UUID, CGRect, UIView) -> Void

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()
    private let moreButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "More Actions"
        return button
    }()

    private var onMoreActionsRequested: MoreActionsHandler?

    func configure(
        with entry: BoardListEntry,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode,
        onMoreActionsRequested: MoreActionsHandler? = nil
    ) {
        representedBoardID = entry.boardID
        representedRevisionToken = entry.revisionToken
        titleLabel.text = entry.title
        self.onMoreActionsRequested = onMoreActionsRequested
        previewView.apply(content: previewContent)
        applyPresentation(for: entry, displayMode: displayMode)
    }

    private func setupView() {
        contentView.addSubview(previewView)
        contentView.addSubview(placeholderIconView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(moreButton)
    }

    private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
        previewView.isHidden = false
        placeholderIconView.isHidden = true
        moreButton.isHidden = true

        switch presentationStyle {
        case .boardGrid:
            moreButton.isHidden = false
            NSLayoutConstraint.activate(gridConstraints)
        case .boardList:
            moreButton.isHidden = false
            NSLayoutConstraint.activate(listConstraints)
        case .placeholderGrid:
            previewView.isHidden = true
            placeholderIconView.isHidden = false
            NSLayoutConstraint.activate(placeholderGridConstraints)
        case .placeholderList:
            previewView.isHidden = true
            placeholderIconView.isHidden = false
            NSLayoutConstraint.activate(placeholderListConstraints)
        }
    }
}
```

### 修改后

- 新增 `UITextFieldDelegate`、`RenameSubmitHandler`、`titleTextField` 和编辑态状态字段。
- `configure(...)` 增加 `isEditingTitle` 与 `onRenameSubmitted`，controller 现在可以声明当前 cell 是否处于 rename 模式。
- 新增 `beginTitleEditing()`，在 cell 出现在屏幕后主动聚焦，并自动全选原标题。
- 新增 `applyTitleEditingAppearance()`，让 `titleLabel` 与 `titleTextField` 在同一标题区域互斥显示，同时在编辑期间隐藏三点按钮。
- `textFieldShouldReturn(_:)` + `textFieldDidEndEditing(_:)` 负责在 iOS 端以“回车 / 失焦提交”的方式结束 rename。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: 类声明 / configure(...) / beginTitleEditing() / applyTitleEditingAppearance() / UITextFieldDelegate
// 功能说明: 修改后 iOS cell 自己承载标题编辑 UI，并把提交后的标题通过回调上送给 controller。
final class iOSBoardCollectionViewCell: UICollectionViewCell, UITextFieldDelegate {
    typealias MoreActionsHandler = (UUID, CGRect, UIView) -> Void
    typealias RenameSubmitHandler = (UUID, String) -> Void

    private let titleLabel: UILabel = { /* ... */ }()
    private let titleTextField: UITextField = {
        let textField = UITextField()
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .label
        textField.borderStyle = .roundedRect
        textField.returnKeyType = .done
        textField.clearButtonMode = .never
        textField.isHidden = true
        return textField
    }()

    private var representedTitle: String?
    private var onRenameSubmitted: RenameSubmitHandler?
    private var currentPresentationStyle: PresentationStyle = .boardGrid
    private var isTitleEditingActive = false
    private var didHandleCurrentTitleEditEnd = false

    func configure(
        with entry: BoardListEntry,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode,
        isEditingTitle: Bool = false,
        onMoreActionsRequested: MoreActionsHandler? = nil,
        onRenameSubmitted: RenameSubmitHandler? = nil
    ) {
        representedBoardID = entry.boardID
        representedTitle = entry.title
        representedRevisionToken = entry.revisionToken
        titleLabel.text = entry.title
        titleTextField.text = entry.title
        isTitleEditingActive = isEditingTitle
        didHandleCurrentTitleEditEnd = false
        self.onMoreActionsRequested = onMoreActionsRequested
        self.onRenameSubmitted = onRenameSubmitted
        previewView.apply(content: previewContent)
        applyPresentation(for: entry, displayMode: displayMode)
        contentView.layoutIfNeeded()
    }

    func beginTitleEditing() {
        guard
            isTitleEditingActive,
            titleTextField.isHidden == false
        else {
            return
        }

        didHandleCurrentTitleEditEnd = false
        titleTextField.becomeFirstResponder()
        DispatchQueue.main.async { [weak self] in
            self?.selectAllTitleTextIfNeeded()
        }
    }

    private func applyTitleEditingAppearance() {
        let shouldShowTitleEditor = isTitleEditingActive && isEditablePresentation
        titleLabel.isHidden = shouldShowTitleEditor
        titleTextField.isHidden = !shouldShowTitleEditor

        if shouldShowTitleEditor {
            moreButton.isHidden = true
            titleTextField.text = representedTitle
            return
        }

        moreButton.isHidden = onMoreActionsRequested == nil
    }

    private func commitTitleEditIfNeeded() {
        guard
            isTitleEditingActive,
            didHandleCurrentTitleEditEnd == false,
            let representedBoardID
        else {
            return
        }

        didHandleCurrentTitleEditEnd = true
        onRenameSubmitted?(representedBoardID, titleTextField.text ?? representedTitle ?? "")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        commitTitleEditIfNeeded()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: setupConstraints()
// 功能说明: 修改后内联编辑仍然只覆盖标题区域，不改变 preview 区域和 card 尺寸。
gridConstraints = [
    previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
    previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    previewView.heightAnchor.constraint(equalToConstant: 120),
    titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
    titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
    titleTextField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
    titleTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    titleTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleTextField.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
]

listConstraints = [
    previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    previewView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    previewView.widthAnchor.constraint(equalToConstant: 72),
    previewView.heightAnchor.constraint(equalToConstant: 72),
    titleLabel.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
    titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
    titleTextField.leadingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: 12),
    titleTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleTextField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
]
```

## 修改二：macOS item 增加内联编辑、提交与 Esc 取消

### 修改前

- `macOSBoardCollectionItem` 也已经有三点按钮，但标题仍然只是 `titleLabel`。
- `configure(...)` 只能接收 `onMoreActionsRequested`，没有 `rename 提交 / 取消` 回调。
- `AppKit` 侧还没有接入 `Return` / `Esc` 的编辑命令处理。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: 类声明 / configure(with:previewContent:displayMode:onMoreActionsRequested:)
// 功能说明: 修改前 macOS item 只能展示标题和更多按钮，Rename 还不能进入可编辑状态。
final class macOSBoardCollectionItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("macOSBoardCollectionItem")

    typealias MoreActionsHandler = (UUID, CGRect, NSView) -> Void

    private let titleLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        return label
    }()
    private let moreButton: NSButton = {
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More Actions")
        return button
    }()

    private var onMoreActionsRequested: MoreActionsHandler?

    func configure(
        with entry: BoardListEntry,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode,
        onMoreActionsRequested: MoreActionsHandler? = nil
    ) {
        representedEntryID = entry.id
        representedBoardID = entry.boardID
        representedTitle = entry.title
        representedDisplayMode = displayMode
        representedRevisionToken = entry.revisionToken
        self.onMoreActionsRequested = onMoreActionsRequested
        titleLabel.stringValue = entry.title
        previewView.apply(content: previewContent)
        applyPresentation(for: entry, displayMode: displayMode)
    }
}
```

### 修改后

- 类声明改为 `NSTextFieldDelegate`，新增 `RenameSubmitHandler`、`RenameCancelHandler` 和 `TitleEditEndDisposition`。
- `titleTextField` 与 `titleLabel` 同区切换，保持 card 的 preview 和外层尺寸不变。
- `beginTitleEditing()` 会把焦点交给 field editor，并自动全选标题。
- `control(_:textView:doCommandBy:)` 负责在 macOS 侧区分 `Return` 提交与 `Esc` 取消。
- `controlTextDidEndEditing(_:)` 根据前一个命令决定走 `commitTitleEditIfNeeded()` 或 `cancelTitleEditIfNeeded()`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: 类声明 / configure(...) / beginTitleEditing() / control(_:textView:doCommandBy:) / controlTextDidEndEditing(_:)
// 功能说明: 修改后 macOS item 拥有和 iOS 对等的内联编辑能力，并额外支持 Esc 取消 rename。
final class macOSBoardCollectionItem: NSCollectionViewItem, NSTextFieldDelegate {
    typealias MoreActionsHandler = (UUID, CGRect, NSView) -> Void
    typealias RenameSubmitHandler = (UUID, String) -> Void
    typealias RenameCancelHandler = (UUID) -> Void

    private enum TitleEditEndDisposition {
        case unspecified
        case commit
        case cancel
    }

    private let titleTextField: NSTextField = {
        let textField = NSTextField(string: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .labelColor
        textField.isHidden = true
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        return textField
    }()

    private var onRenameSubmitted: RenameSubmitHandler?
    private var onRenameCancelled: RenameCancelHandler?
    private var isTitleEditingActive = false
    private var didHandleCurrentTitleEditEnd = false
    private var pendingTitleEditEndDisposition: TitleEditEndDisposition = .unspecified

    func configure(
        with entry: BoardListEntry,
        previewContent: BoardPreviewContent,
        displayMode: BoardListDisplayMode,
        isEditingTitle: Bool = false,
        onMoreActionsRequested: MoreActionsHandler? = nil,
        onRenameSubmitted: RenameSubmitHandler? = nil,
        onRenameCancelled: RenameCancelHandler? = nil
    ) {
        representedBoardID = entry.boardID
        representedTitle = entry.title
        representedDisplayMode = displayMode
        representedRevisionToken = entry.revisionToken
        self.onMoreActionsRequested = onMoreActionsRequested
        self.onRenameSubmitted = onRenameSubmitted
        self.onRenameCancelled = onRenameCancelled
        isTitleEditingActive = isEditingTitle
        didHandleCurrentTitleEditEnd = false
        pendingTitleEditEndDisposition = .unspecified
        titleLabel.stringValue = entry.title
        titleTextField.stringValue = entry.title
        previewView.apply(content: previewContent)
        applyPresentation(for: entry, displayMode: displayMode)
        view.layoutSubtreeIfNeeded()
    }

    func beginTitleEditing() {
        guard
            isTitleEditingActive,
            titleTextField.isHidden == false
        else {
            return
        }

        didHandleCurrentTitleEditEnd = false
        pendingTitleEditEndDisposition = .unspecified
        view.window?.makeFirstResponder(titleTextField)
        DispatchQueue.main.async { [weak self] in
            guard
                let self,
                self.isTitleEditingActive
            else {
                return
            }

            self.view.window?.makeFirstResponder(self.titleTextField)
            (self.view.window?.fieldEditor(true, for: self.titleTextField) as? NSTextView)?
                .selectAll(nil)
        }
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            pendingTitleEditEndDisposition = .commit
            view.window?.makeFirstResponder(nil)
            return true
        }

        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            pendingTitleEditEndDisposition = .cancel
            view.window?.makeFirstResponder(nil)
            return true
        }

        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as AnyObject? === titleTextField else {
            return
        }

        let disposition = pendingTitleEditEndDisposition
        pendingTitleEditEndDisposition = .unspecified

        switch disposition {
        case .unspecified, .commit:
            commitTitleEditIfNeeded()
        case .cancel:
            cancelTitleEditIfNeeded()
        }
    }
}
```

## 修改三：iOS controller 把 Rename 从“只切编辑态”补成完整提交流

### 修改前

- `displayMode` 切换时直接手工 `updateCollectionLayout() + reloadData() + syncCollectionSelection()`。
- `performBoardAction(.rename)` 只做 `editingBoardID = boardID`，没有提交 rename、失败提示、回顶后的显式滚动恢复。
- `cell.configure(...)` 也还没有 `isEditingTitle` 和 `onRenameSubmitted` 两个输入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: displayMode.didSet / reloadBoardList() / performBoardAction(_:) / collectionView(_:cellForItemAt:)
// 功能说明: 修改前 iOS controller 只把 Rename 动作映射成 editingBoardID，不负责真正的 rename 提交和可见性恢复。
private var displayMode: BoardListDisplayMode = .grid {
    didSet {
        guard oldValue != displayMode else {
            return
        }

        updateCollectionLayout()
        collectionView.reloadData()
        syncCollectionSelection()
    }
}

private func reloadBoardList() {
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    syncCollectionSelection()
}

private func performBoardAction(_ actionID: BoardListActionID) {
    let boardID = actionPanelState?.boardID
    dismissActionPanel()

    switch actionID {
    case .rename:
        editingBoardID = boardID
        reloadBoardList()
    }
}

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

### 修改后

- `displayMode` 改为统一走 `reloadBoardList()`，把“重载列表 + 恢复选中 + 显式滚动 + 自动聚焦”收敛到一个入口。
- 新增 `indexPath(for:)`、`boardTitle(for:)`、`normalizedBoardTitle(_:)`，为 rename 提交和 reveal 提供基础查询。
- 新增 `commitRename(boardID:title:)`，调用 `BoardStore.renameBoard(...)`，成功后设置 `selectedEntryID` 与 `pendingRevealBoardID` 并刷新列表；失败则复用 `UIAlertController` 提示。
- 新增 `focusTitleEditorIfNeeded()` / `revealPendingBoardIfNeeded()`，让进入编辑态和 rename 后回顶都能恢复可见性。
- `cell.configure(...)` 增加 `isEditingTitle` 与 `onRenameSubmitted`，并在编辑期间临时移除更多操作回调，避免同时再弹出新的 action panel。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: displayMode.didSet / reloadBoardList() / performBoardAction(_:) / commitRename(boardID:title:)
// 功能说明: 修改后 iOS controller 把 Rename 变成完整流：进入编辑、提交持久化、失败反馈、刷新后保持选中并滚到可见区域。
private var displayMode: BoardListDisplayMode = .grid {
    didSet {
        guard oldValue != displayMode else {
            return
        }

        reloadBoardList()
    }
}

private func reloadBoardList() {
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    syncCollectionSelection()
    revealPendingBoardIfNeeded()
    focusTitleEditorIfNeeded()
}

private func performBoardAction(_ actionID: BoardListActionID) {
    let boardID = actionPanelState?.boardID
    dismissActionPanel()

    switch actionID {
    case .rename:
        guard let boardID else {
            return
        }

        selectedEntryID = .board(boardID)
        pendingRevealBoardID = nil
        editingBoardID = boardID
        reloadBoardList()
    }
}

private func commitRename(boardID: UUID, title: String) {
    guard editingBoardID == boardID else {
        return
    }

    let normalizedTitle = normalizedBoardTitle(title)
    if boardTitle(for: boardID) == normalizedTitle {
        editingBoardID = nil
        pendingRevealBoardID = nil
        reloadBoardList()
        return
    }

    do {
        try BoardStore.renameBoard(id: boardID, title: normalizedTitle)
        editingBoardID = nil
        selectedEntryID = .board(boardID)
        pendingRevealBoardID = boardID
        refreshBookmarkStatus()
    } catch {
        presentRenameError(error)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名: focusTitleEditorIfNeeded() / revealPendingBoardIfNeeded() / collectionView(_:cellForItemAt:)
// 功能说明: 修改后 iOS controller 会在 cell 渲染后自动聚焦编辑框，并在 rename 导致排序变化后把目标 board 显式滚回可见区域。
private func focusTitleEditorIfNeeded() {
    guard let editingBoardID else {
        return
    }

    guard let indexPath = indexPath(for: editingBoardID) else {
        self.editingBoardID = nil
        return
    }

    DispatchQueue.main.async { [weak self] in
        self?.focusTitleEditor(at: indexPath, boardID: editingBoardID)
    }
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        return
    }

    collectionView.layoutIfNeeded()
    collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
    pendingRevealBoardID = nil
}

let moreActionsHandler: iOSBoardCollectionViewCell.MoreActionsHandler?
if editingBoardID == nil {
    moreActionsHandler = { [weak self] boardID, anchorRect, sourceView in
        self?.presentRenameActionPanel(
            for: boardID,
            anchorRect: anchorRect,
            from: sourceView
        )
    }
} else {
    moreActionsHandler = nil
}

cell.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode,
    isEditingTitle: entry.boardID.map { $0 == editingBoardID } ?? false,
    onMoreActionsRequested: moreActionsHandler,
    onRenameSubmitted: { [weak self] boardID, title in
        self?.commitRename(boardID: boardID, title: title)
    }
)
```

## 修改四：macOS controller 接入提交、取消与回顶后的滚动恢复

### 修改前

- `reloadBoardList()` 只负责 `reloadData + syncCollectionSelection + trace log`。
- `performBoardAction(.rename)` 同样只会设置 `editingBoardID`，没有提交 rename / 取消 rename 的控制器路径。
- `item.configure(...)` 还没有 `isEditingTitle`、`onRenameSubmitted`、`onRenameCancelled`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: reloadBoardList() / performBoardAction(_:) / collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改前 macOS controller 只会切换编辑态，没有真正落地 rename 提交、取消与滚动恢复。
private func reloadBoardList() {
    logSelectionTrace("reloadBoardListBegin", extra: "entries=\(entries.count)")
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    syncCollectionSelection()
    logSelectionTrace("reloadBoardListEnd", extra: "entries=\(entries.count)")
}

private func performBoardAction(_ actionID: BoardListActionID) {
    let boardID = actionPanelState?.boardID
    dismissActionPanel()

    switch actionID {
    case .rename:
        editingBoardID = boardID
        reloadBoardList()
    }
}

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

### 修改后

- `reloadBoardList()` 增加 `revealPendingBoardIfNeeded()` 与 `focusTitleEditorIfNeeded()`。
- 新增 `commitRename(boardID:title:)` 与 `cancelRename(boardID:)`；其中 `commitRename` 调 `BoardStore.renameBoard(...)`，`cancelRename` 负责撤销当前编辑态并重载列表。
- 新增 `presentRenameError(_:)`，复用现有 `NSAlert` 反馈 rename 失败，并在错误弹窗关闭后重新聚焦编辑框。
- 新增 `focusTitleEditor(at:boardID:)` 与 `revealBoard(at:boardID:)`，在 `NSCollectionView` 中通过 `scrollToItems(... .nearestVerticalEdge)` 恢复目标 item 的可见性。
- `item.configure(...)` 现在会把提交和取消回调一起注入到 `macOSBoardCollectionItem` 中。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: reloadBoardList() / performBoardAction(_:) / commitRename(boardID:title:) / cancelRename(boardID:)
// 功能说明: 修改后 macOS controller 负责完整的 rename 生命周期，并和 AppKit item 的 Return / Esc 行为对接。
private func reloadBoardList() {
    logSelectionTrace("reloadBoardListBegin", extra: "entries=\(entries.count)")
    collectionView.reloadData()
    updateCollectionVisibility()
    updateDisplayModeControlState()
    updateCollectionLayout()
    syncCollectionSelection()
    revealPendingBoardIfNeeded()
    focusTitleEditorIfNeeded()
    logSelectionTrace("reloadBoardListEnd", extra: "entries=\(entries.count)")
}

private func performBoardAction(_ actionID: BoardListActionID) {
    let boardID = actionPanelState?.boardID
    dismissActionPanel()

    switch actionID {
    case .rename:
        guard let boardID else {
            return
        }

        selectedEntryID = .board(boardID)
        pendingRevealBoardID = nil
        editingBoardID = boardID
        reloadBoardList()
    }
}

private func commitRename(boardID: UUID, title: String) {
    guard editingBoardID == boardID else {
        return
    }

    let normalizedTitle = normalizedBoardTitle(title)
    if boardTitle(for: boardID) == normalizedTitle {
        editingBoardID = nil
        pendingRevealBoardID = nil
        reloadBoardList()
        return
    }

    do {
        try BoardStore.renameBoard(id: boardID, title: normalizedTitle)
        editingBoardID = nil
        selectedEntryID = .board(boardID)
        pendingRevealBoardID = boardID
        refreshBookmarkStatus()
    } catch {
        presentRenameError(error)
    }
}

private func cancelRename(boardID: UUID) {
    guard editingBoardID == boardID else {
        return
    }

    editingBoardID = nil
    pendingRevealBoardID = nil
    reloadBoardList()
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名: focusTitleEditor(at:boardID:) / revealBoard(at:boardID:) / presentRenameError(_:) / collectionView(_:itemForRepresentedObjectAt:)
// 功能说明: 修改后 macOS controller 会在 item 可见后恢复焦点，并在排序回顶后把目标 board 明确滚回可见区域。
private func focusTitleEditor(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard editingBoardID == boardID else {
        return
    }

    collectionView.layoutSubtreeIfNeeded()
    collectionView.scrollToItems(
        at: Set([indexPath]),
        scrollPosition: .nearestVerticalEdge
    )
    collectionScrollView.layoutSubtreeIfNeeded()
    collectionView.layoutSubtreeIfNeeded()

    guard let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem else {
        return
    }

    item.beginTitleEditing()
}

private func revealBoard(
    at indexPath: IndexPath,
    boardID: UUID
) {
    guard pendingRevealBoardID == boardID else {
        return
    }

    collectionView.layoutSubtreeIfNeeded()
    collectionView.scrollToItems(
        at: Set([indexPath]),
        scrollPosition: .nearestVerticalEdge
    )
    pendingRevealBoardID = nil
}

private func presentRenameError(_ error: Error) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Unable to Rename Board"
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")

    if let window = view.window {
        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.focusTitleEditorIfNeeded()
        }
    } else {
        alert.runModal()
        focusTitleEditorIfNeeded()
    }
}

item.configure(
    with: entry,
    previewContent: previewContent,
    displayMode: displayMode,
    isEditingTitle: entry.boardID.map { $0 == editingBoardID } ?? false,
    onMoreActionsRequested: moreActionsHandler,
    onRenameSubmitted: { [weak self] boardID, title in
        self?.commitRename(boardID: boardID, title: title)
    },
    onRenameCancelled: { [weak self] boardID in
        self?.cancelRename(boardID: boardID)
    }
)
```

## 修改五：同步更新计划文件状态

### 修改前

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（plan todos）
# 功能说明: 修改前 Phase 5 的“标题内联编辑流”仍处于 pending。
- id: inline-rename-flow
  content: 为 iOS/macOS cell/item 加入标题内联编辑，并接上提交/取消/聚焦逻辑
  status: pending
```

### 修改后

```yaml
# 文件路径: .cursor/plans/boardlist_rename_flow_07528e2b.plan.md
# 函数名: N/A（plan todos）
# 功能说明: 修改后 Phase 5 的“标题内联编辑流”已完成；仍未完成的部分只剩运行时回归验证。
- id: inline-rename-flow
  content: 为 iOS/macOS cell/item 加入标题内联编辑，并接上提交/取消/聚焦逻辑
  status: completed
```

## 验证结果

- `ReadLints`
  - 检查文件：
    - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
    - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
    - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
    - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - 结果：无 linter 错误。
- `swiftc` typecheck
  - 命令：

```bash
xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift
```

  - 结果：通过。

## 当前状态

- `Rename -> 标题内联编辑 -> 提交/取消 -> 刷新列表 -> 保持选中并滚回可见区域` 的代码路径已经接通。
- `iOS` 当前提交方式是 `Return` 或失去焦点时提交。
- `macOS` 当前提交方式是 `Return` 提交，`Esc` 取消，失去焦点默认按提交路径处理。
- `.cursor/plans/boardlist_rename_flow_07528e2b.plan.md` 中 `inline-rename-flow` 已标记为 `completed`。
- `reveal-and-verify` 仍保持 `pending`，原因是手工运行时回归验证尚未执行。
