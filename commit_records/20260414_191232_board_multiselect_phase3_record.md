# 20260414_191232 图板多选阶段3改动记录

本记录基于本轮实际工作区状态整理，参考了 `date`、`git status --short`、`git diff --stat`、`git diff`、当前文件内容、`ReadLints` 与 `xcodebuild` 结果；不直接粘贴原始 `git diff`，而是按“修改前 / 修改后”的方式归纳 phase3 实际落地内容。

## 当前 Changes 快照

```bash
# 命令: date +%Y%m%d_%H%M%S
# 说明: 本记录文件名使用的时间戳
20260414_191232
```

```bash
# 命令: git status --short
# 说明: 创建本记录前工作区中的全部 changes；这里同时包含 tracked 修改和新增未跟踪文件
 M .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
 M MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
 M MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
 M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
?? MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift
?? MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
```

```bash
# 命令: git diff --stat
# 说明: tracked 文件的 diff 体量概览；这条命令不会显示新增未跟踪文件
.../plans/board-multiselect-plan_96ecdbb5.plan.md  |   2 +-
.../Shared/Toolbar/CanvasToolbarState.swift        |   1 +
.../Shared/Toolbar/CanvasToolbarStateBuilder.swift |  15 ++
.../iOS/Canvas/iOSCanvasToolbarHostView.swift      |  18 +-
.../iOS/Canvas/iOSCanvasViewportView.swift         |   8 +-
.../Platform/iOS/iOSViewController.swift           | 220 ++++++++++++--------
.../macOS/Canvas/macOSCanvasToolbarHostView.swift  |  18 +-
.../macOS/Canvas/macOSCanvasViewportView.swift     |  20 +-
.../Platform/macOS/macOSViewController.swift       | 227 +++++++++++++--------
9 files changed, 350 insertions(+), 179 deletions(-)
```

当前 `git diff --stat` 不会显示的 phase3 新增文件：

- `MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift`
- `MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift`
- `MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift`

## 1. 工具条状态契约新增 `multiSelect` 项

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数: CanvasToolbarItemID
// 说明: 旧枚举没有多选按钮，builder 也没有多选模式输入。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case save
    case text
    case importMedia
    case undo
    case redo
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: mainToolbarState(session:saveState:placement:isImportEnabled:showsBackground:includesHistoryItems:)
// 说明: 旧工具条顺序只有 history / crop / save / text / import，没有 checklist 开关。
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
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数: CanvasToolbarItemID
// 说明: 新增 .multiSelect，作为 iOS / macOS 共享的 toolbar item ID。
enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case multiSelect
    case save
    case text
    case importMedia
    case undo
    case redo
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数: mainToolbarState(session:saveState:placement:isMultiSelectModeActive:isImportEnabled:showsBackground:includesHistoryItems:) / multiSelectItemState(isActive:)
// 说明: builder 新增多选模式输入，并在 crop 后插入 checklist 按钮状态。
func mainToolbarState(
    session: CanvasEditorSession,
    saveState: CanvasSaveState,
    placement: CanvasToolbarPlacement,
    isMultiSelectModeActive: Bool = false,
    isImportEnabled: Bool = true,
    showsBackground: Bool = true,
    includesHistoryItems: Bool = false
) -> CanvasToolbarState {
    var itemStates: [CanvasToolbarItemState] = []
    if includesHistoryItems {
        itemStates.append(contentsOf: historyItemStates(session: session))
    }
    if shouldShowCropItem(session: session) {
        itemStates.append(cropItemState(session: session))
    }
    itemStates.append(
        multiSelectItemState(isActive: isMultiSelectModeActive)
    )
    itemStates.append(saveItemState(saveState: saveState))
    itemStates.append(textItemState(session: session))
    itemStates.append(importItemState(isEnabled: isImportEnabled))
    ...
}

func multiSelectItemState(isActive: Bool) -> CanvasToolbarItemState {
    CanvasToolbarItemState(
        id: .multiSelect,
        systemImageName: "checklist",
        isActive: isActive,
        accessibilityLabel: "Multi-select",
        accessibilityValue: isActive ? "On" : "Off",
        visualRole: isActive ? .accent : .neutral
    )
}
```

## 2. 工具条 host 让中性态按钮可读，并接入 `checklist` 图标规格

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数: applyAppearance(_:to:) / symbolConfiguration(for:)
// 说明: 旧实现默认把所有启用态按钮前景色都设成白色，中性态按钮并不适合直接复用。
configuration.baseForegroundColor = preservesVisualRole
    ? .white
    : .secondaryLabel

switch itemID {
case .save, .undo, .redo:
    return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
case .importMedia:
    return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
case .crop, .text:
    return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数: applyAppearance(_:to:) / foregroundColor(for:) / symbolConfiguration(for:)
// 说明: neutral 按钮改用 label 色，multiSelect 复用 crop/text 的符号尺寸；macOS host 做了对称修改。
configuration.baseForegroundColor = preservesVisualRole
    ? foregroundColor(for: itemState.visualRole)
    : .secondaryLabel

private func foregroundColor(
    for visualRole: CanvasToolbarItemVisualRole
) -> UIColor {
    switch visualRole {
    case .neutral:
        return .label
    case .accent,
         .success,
         .warning,
         .danger:
        return .white
    }
}

switch itemID {
case .save, .undo, .redo:
    return UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
case .importMedia:
    return UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
case .crop, .multiSelect, .text:
    return UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
}
```

## 3. 点击选择决策从 controller 内联分支抽成共享 resolver

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handlePrimaryPointerUp(at:)
// 说明: 旧实现把单选、空白清空、文本重入全部直接写在 controller 里；iOS / macOS 各自维护一套。
case .selectedItemBody, .unselectedItemBody:
    if let itemID = pressContext.targetItemID,
       releasedItemID == itemID
    {
        clickTarget = "item"
        affectedItemID = itemID
        selectItem(
            withID: itemID,
            recordHistory: true
        )
        if previousSelectedItemID != itemID {
            clickResult = "item_selected"
            didTriggerPressedRefresh = true
        } else {
            if case .selectedItemBody = pressContext.targetKind,
               beginTextEditIfPossible(for: itemID)
            {
                clickResult = "text_edit_began"
                didTriggerPressedRefresh = true
            }
        }
    }
case .blank:
    if releasedItemID == nil {
        affectedItemID = previousSelectedItemID
        clearSelectionIfNeeded(recordHistory: true)
        if previousSelectedItemID != nil {
            clickResult = "item_deselected"
            didTriggerPressedRefresh = true
        }
    }
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Input/CanvasClickSelectionResolver.swift
// 函数: resolve(pressTargetKind:pressedItemID:releasedItemID:selection:isPersistentMultiSelectModeEnabled:pressedModifiers:releasedModifiers:)
// 说明: 新 resolver 把普通单选、toolbar 多选、macOS Command+Click、空白清空统一收口；多选语义下不会自动进入文本编辑。
struct CanvasPointerModifiers: Equatable, Sendable {
    var isCommandPressed = false
    var isShiftPressed = false
    var isOptionPressed = false
    var isControlPressed = false

    static let none = Self()
    ...
}

enum CanvasClickSelectionAction: Equatable {
    case none
    case selectSingle(itemID: CanvasItemID)
    case toggleMembership(itemID: CanvasItemID)
    case clearSelection
    case attemptTextEdit(itemID: CanvasItemID)
}

struct CanvasClickSelectionResolver: Sendable {
    func resolve(
        pressTargetKind: CanvasPointerTargetKind,
        pressedItemID: CanvasItemID?,
        releasedItemID: CanvasItemID?,
        selection: CanvasInteractionState,
        isPersistentMultiSelectModeEnabled: Bool,
        pressedModifiers: CanvasPointerModifiers,
        releasedModifiers: CanvasPointerModifiers
    ) -> CanvasClickSelectionDecision {
        ...
        if selectionMode(
            isPersistentMultiSelectModeEnabled: isPersistentMultiSelectModeEnabled,
            pressedModifiers: pressedModifiers,
            releasedModifiers: releasedModifiers
        ) == .toggleMembership {
            return CanvasClickSelectionDecision(
                target: "item",
                affectedItemID: itemID,
                action: .toggleMembership(itemID: itemID)
            )
        }

        if case .selectedItemBody = pressTargetKind,
           selection.singleSelectedItemID == itemID
        {
            return CanvasClickSelectionDecision(
                target: "item",
                affectedItemID: itemID,
                action: .attemptTextEdit(itemID: itemID)
            )
        }

        return CanvasClickSelectionDecision(
            target: "item",
            affectedItemID: itemID,
            action: .selectSingle(itemID: itemID)
        )
    }

    private func selectionMode(...) -> CanvasClickSelectionMode {
        let mergedModifiers = pressedModifiers.merging(releasedModifiers)
        if isPersistentMultiSelectModeEnabled || mergedModifiers.isCommandPressed {
            return .toggleMembership
        }
        return .replaceSelection
    }
}
```

## 4. viewport 输入链路开始透传 pointer modifiers

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数: onPointerDown / onPointerUp / mouseDown(with:) / mouseUp(with:)
// 说明: 旧链路只上传 location，controller 拿不到 Command 键状态。
var onPointerDown: ((CGPoint) -> Void)?
var onPointerUp: ((CGPoint) -> Void)?

override func mouseDown(with event: NSEvent) {
    ...
    onPointerDown?(location)
}

override func mouseUp(with event: NSEvent) {
    ...
    onPointerUp?(location)
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数: onPointerDown / onPointerUp / mouseDown(with:) / mouseUp(with:) / pointerModifiers(for:)
// 说明: macOS 现在把 NSEvent.ModifierFlags 归一化成共享的 CanvasPointerModifiers；iOS 端对称地传 .none。
var onPointerDown: ((CGPoint, CanvasPointerModifiers) -> Void)?
var onPointerUp: ((CGPoint, CanvasPointerModifiers) -> Void)?

override func mouseDown(with event: NSEvent) {
    ...
    onPointerDown?(location, pointerModifiers(for: event.modifierFlags))
}

override func mouseUp(with event: NSEvent) {
    ...
    onPointerUp?(location, pointerModifiers(for: event.modifierFlags))
}

private func pointerModifiers(
    for modifierFlags: NSEvent.ModifierFlags
) -> CanvasPointerModifiers {
    let normalizedFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
    return CanvasPointerModifiers(
        isCommandPressed: normalizedFlags.contains(.command),
        isShiftPressed: normalizedFlags.contains(.shift),
        isOptionPressed: normalizedFlags.contains(.option),
        isControlPressed: normalizedFlags.contains(.control)
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数: onPointerDown / onPointerUp / beginPrimaryPointerTracking(with:) / touchesEnded(_:with:)
// 说明: iOS 复用同一闭包签名，但始终显式传 .none，保证 controller 不再依赖平台事件枚举。
var onPointerDown: ((CGPoint, CanvasPointerModifiers) -> Void)?
var onPointerUp: ((CGPoint, CanvasPointerModifiers) -> Void)?

private func beginPrimaryPointerTracking(with touch: UITouch) {
    ...
    onPointerDown?(location, .none)
}

override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    ...
    if let pointerUpLocation {
        onPointerUp?(pointerUpLocation, .none)
    }
}
```

## 5. iOS controller 接入多选开关，并消费共享点击决策

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: toolbarButtonsByID / setupCanvasViewport() / makeToolbarState()
// 说明: 旧 iOS controller 没有 multiSelectButton，也没有把 toolbar 状态和点击语义关联起来。
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

canvasViewportView.onPointerDown = { [weak self] location in
    ...
    self?.handlePrimaryPointerDown(at: location)
}
canvasViewportView.onPointerUp = { [weak self] location in
    ...
    self?.handlePrimaryPointerUp(at: location)
}

private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        includesHistoryItems: true
    )
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: toolbarButtonsByID / setupMultiSelectButton() / handleMultiSelectButtonTap() / setupCanvasViewport() / makeToolbarState()
// 说明: iOS 端新增多选按钮、局部状态和 modifier-aware 输入闭包，再把 toolbar active 态喂回 builder。
private let multiSelectButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}()

private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .undo: undoButton,
        .redo: redoButton,
        .crop: cropButton,
        .multiSelect: multiSelectButton,
        .save: saveButton,
        .text: textButton,
        .importMedia: importButton
    ]
}

private var isMultiSelectModeActive = false {
    didSet {
        guard oldValue != isMultiSelectModeActive else {
            return
        }

        dismissContextMenu()
        renderToolbar()
    }
}

private func setupMultiSelectButton() {
    multiSelectButton.addTarget(
        self,
        action: #selector(handleMultiSelectButtonTap),
        for: .touchUpInside
    )
    renderToolbar()
}

@objc
private func handleMultiSelectButtonTap() {
    commitActiveTextEditIfNeeded()
    isMultiSelectModeActive.toggle()
}

canvasViewportView.onPointerDown = { [weak self] location, modifiers in
    ...
    self?.handlePrimaryPointerDown(at: location, modifiers: modifiers)
}
canvasViewportView.onPointerUp = { [weak self] location, modifiers in
    ...
    self?.handlePrimaryPointerUp(at: location, modifiers: modifiers)
}

private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        isMultiSelectModeActive: isMultiSelectModeActive,
        includesHistoryItems: true
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数: handlePrimaryPointerUp(at:modifiers:) / toggleSelectionMembership(of:recordHistory:) / executeClickSelectionDecision(_:)
// 说明: controller 不再手写点选分支，而是执行共享决策结果；toggle membership 直接走 command lane。
private func handlePrimaryPointerUp(
    at location: CGPoint,
    modifiers: CanvasPointerModifiers
) {
    ...
    let previousInteractionState = interactionState
    let clickDecision = clickSelectionResolver.resolve(
        pressTargetKind: pressContext.targetKind,
        pressedItemID: pressContext.targetItemID,
        releasedItemID: releasedItemID,
        selection: previousInteractionState,
        isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
        pressedModifiers: pressedModifiers,
        releasedModifiers: modifiers
    )
    let executionResult = executeClickSelectionDecision(clickDecision)
    ...
}

private func toggleSelectionMembership(
    of itemID: CanvasItemID,
    recordHistory: Bool = false
) {
    performCommand(
        .toggleSelectionMembership(
            itemID: itemID,
            recordHistory: recordHistory
        )
    )
}

private func executeClickSelectionDecision(
    _ decision: CanvasClickSelectionDecision
) -> (result: String, didTriggerPressedRefresh: Bool) {
    switch decision.action {
    case let .selectSingle(itemID):
        selectItem(withID: itemID, recordHistory: true)
        ...
    case let .toggleMembership(itemID):
        let wasSelected = interactionStateBefore.selectedItemIDs.contains(itemID)
        toggleSelectionMembership(of: itemID, recordHistory: true)
        ...
    case .clearSelection:
        clearSelectionIfNeeded(recordHistory: true)
        ...
    case let .attemptTextEdit(itemID):
        if beginTextEditIfPossible(for: itemID) {
            return ("text_edit_began", true)
        }
        return ("selection_unchanged", false)
    case .none:
        return ("selection_unchanged", false)
    }
}
```

## 6. macOS controller 接入 `Command+Click`，并与 iOS 共用同一选择语义

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handlePrimaryPointerDown(at:) / handlePrimaryPointerUp(at:)
// 说明: 旧 macOS controller 只能看到 location，无法区分普通 click 和 Command+Click；点击结果仍是内联单选逻辑。
private func handlePrimaryPointerDown(at location: CGPoint) {
    ...
    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext
    )
}

private func handlePrimaryPointerUp(at location: CGPoint) {
    ...
    switch pressContext.targetKind {
    case .selectedItemBody, .unselectedItemBody:
        ...
        selectItem(withID: itemID, recordHistory: true)
        ...
    case .blank:
        clearSelectionIfNeeded(recordHistory: true)
    ...
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: handlePrimaryPointerDown(at:modifiers:) / handlePrimaryPointerUp(at:modifiers:) / describe(pointerModifiers:)
// 说明: macOS 现在把 Command 状态写进 pressed state，并把它和 toolbar 多选模式一起交给共享 resolver。
private func handlePrimaryPointerDown(
    at location: CGPoint,
    modifiers: CanvasPointerModifiers
) {
    print(
        "[Canvas macOS][PrimaryPointerInput] " +
        "phase=down " +
        "location=\(describe(point: location)) " +
        "worldPoint=\(describe(point: camera.viewportToWorld(location))) " +
        "selection=\(describe(selectionState: interactionState)) " +
        "pointerModifiers=\(describe(pointerModifiers: modifiers)) " +
        ...
    )
    let pressContext = resolvePointerPressContext(at: location)
    pointerDragState = .pressed(
        pressedLocation: location,
        pressContext: pressContext,
        pointerModifiers: modifiers
    )
}

private func handlePrimaryPointerUp(
    at location: CGPoint,
    modifiers: CanvasPointerModifiers
) {
    ...
    let clickDecision = clickSelectionResolver.resolve(
        pressTargetKind: pressContext.targetKind,
        pressedItemID: pressContext.targetItemID,
        releasedItemID: releasedItemID,
        selection: previousInteractionState,
        isPersistentMultiSelectModeEnabled: isMultiSelectModeActive,
        pressedModifiers: pressedModifiers,
        releasedModifiers: modifiers
    )
    let executionResult = executeClickSelectionDecision(clickDecision)
    ...
}

private func describe(pointerModifiers: CanvasPointerModifiers) -> String {
    "command=\(pointerModifiers.isCommandPressed) " +
    "shift=\(pointerModifiers.isShiftPressed) " +
    "option=\(pointerModifiers.isOptionPressed) " +
    "control=\(pointerModifiers.isControlPressed)"
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: setupMultiSelectButton() / handleMultiSelectButtonClick() / makeToolbarState()
// 说明: macOS 端 toolbar 多选开关与 iOS 同步，状态同样通过 builder 输出。
private func setupMultiSelectButton() {
    multiSelectButton.target = self
    multiSelectButton.action = #selector(handleMultiSelectButtonClick)
    renderToolbar()
}

@objc
private func handleMultiSelectButtonClick() {
    commitActiveTextEditIfNeeded()
    isMultiSelectModeActive.toggle()
}

private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: toolbarPreferredPlacement(),
        isMultiSelectModeActive: isMultiSelectModeActive,
        includesHistoryItems: true
    )
}
```

## 7. phase3 新增专项测试

### 修改前

phase3 开始前，工作区里没有专门验证“共享点击决策器”和“toolbar `multiSelect` 状态输出”的测试文件。

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests.swift
// 函数: testResolveUsesPersistentMultiSelectModeToToggleMembership() / testResolveUsesCommandClickToToggleMembership() / testResolvePrefersTextEditOnlyForSoleSelectedItem()
// 说明: 覆盖 toolbar 多选模式、macOS Command+Click、空白清空，以及“只有唯一选中文本才允许 text edit re-entry”。
@MainActor
final class CanvasClickSelectionResolverTests: XCTestCase {
    private let resolver = CanvasClickSelectionResolver()

    func testResolveUsesPersistentMultiSelectModeToToggleMembership() {
        ...
        XCTAssertEqual(
            decision.action,
            .toggleMembership(itemID: tappedItemID)
        )
    }

    func testResolveUsesCommandClickToToggleMembership() {
        ...
        XCTAssertEqual(
            decision.action,
            .toggleMembership(itemID: tappedItemID)
        )
    }

    func testResolvePrefersTextEditOnlyForSoleSelectedItem() {
        ...
        XCTAssertEqual(
            decision.action,
            .attemptTextEdit(itemID: tappedItemID)
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests.swift
// 函数: testMainToolbarStateIncludesMultiSelectItem() / testMainToolbarStateReflectsActiveMultiSelectMode()
// 说明: 覆盖 checklist 按钮插入顺序、accessibility 值和 active visual role；过程中补齐了 throws 声明以通过 XCTUnwrap 编译。
@MainActor
final class CanvasToolbarStateBuilderTests: XCTestCase {
    func testMainToolbarStateIncludesMultiSelectItem() throws {
        ...
        XCTAssertEqual(
            state.items.map(\.id),
            [.undo, .redo, .crop, .multiSelect, .save, .text, .importMedia]
        )
        ...
        XCTAssertEqual(multiSelectItem.accessibilityValue, "Off")
        XCTAssertEqual(multiSelectItem.visualRole, .neutral)
    }

    func testMainToolbarStateReflectsActiveMultiSelectMode() throws {
        ...
        XCTAssertEqual(multiSelectItem.accessibilityValue, "On")
        XCTAssertEqual(multiSelectItem.visualRole, .accent)
        XCTAssertTrue(multiSelectItem.isActive)
    }
}
```

## 8. 计划状态同步

```yaml
# 文件路径: .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
# 位置: YAML front matter.todos[phase3-toolbar-input]
# 说明: 当前 changes 中，这一项已从 pending 同步为 completed。
- id: phase3-toolbar-input
  content: 接入 iOS/macOS 多选工具条开关，并完成 macOS Command+Click 与共享点击决策器。
  status: pending
```

```yaml
# 文件路径: .cursor/plans/board-multiselect-plan_96ecdbb5.plan.md
# 位置: YAML front matter.todos[phase3-toolbar-input]
# 说明: 当前 changes 中，这一项已从 pending 同步为 completed。
- id: phase3-toolbar-input
  content: 接入 iOS/macOS 多选工具条开关，并完成 macOS Command+Click 与共享点击决策器。
  status: completed
```

## 9. 验证与结果

`ReadLints`：

- 本次改动文件无 linter 错误。

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests
# 结果: 失败
# 说明: 当前 MyCanvas_Ver_0Tests target 不支持 iphonesimulator，测试没有进入执行阶段。
xcodebuild: error: Failed to build project MyCanvas_Ver_0 with scheme MyCanvas_Ver_0.: Cannot test target “MyCanvas_Ver_0Tests” on “iPhone 17”: MyCanvas_Ver_0Tests does not support iPhone 17’s platform: com.apple.platform.iphonesimulator
```

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests
# 第一次结果: 失败
# 说明: 新增测试里的 XCTUnwrap 需要 throws，随后已在 CanvasToolbarStateBuilderTests.swift 中补齐。
Testing failed:
    Errors thrown from here are not handled
```

```bash
# 命令: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasClickSelectionResolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasToolbarStateBuilderTests
# 第二次结果: 失败
# 说明: 新增生产代码和新增测试已经编译进入 macOS test 流程，最终仍被既有工程配置问题阻塞。
error: Your target is built for macOS but contains embedded content built for the iOS platform (Add To Canvas.appex), which is not allowed.
```

## 小结

phase3 这轮真正落地的是三件事：

- toolbar 共享状态里新增 `multiSelect`，两端都能显示并刷新 active 态。
- 点击选择语义从 controller 内联分支收敛到 `CanvasClickSelectionResolver`，普通单选 / toolbar 多选 / `Command+Click` / 空白清空统一由共享逻辑判定。
- macOS 输入链路把 modifier flags 透传到了 controller，因此 `Command+Click` 不再是平台特例硬编码，而是与 toolbar 多选模式共享同一条选择决策路径。
