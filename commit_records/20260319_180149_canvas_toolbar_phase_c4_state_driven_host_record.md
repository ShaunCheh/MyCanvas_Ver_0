# 20260319_180149_canvas_toolbar_phase_c4_state_driven_host_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段C-阶段4` 的实际代码变更。
- 本次实际产物：
- 扩展共享 `CanvasToolbarItemState`，补齐 `preservesVisualRoleWhenDisabled`，让 `Save.saving` 这类“禁用但仍需保留强调色”的状态可以被共享层准确表达。
- 扩展共享 `CanvasToolbarStateBuilder`，新增 `mainToolbarState(...)` 与 `importItemState(...)`，把 `Crop / Save / Import` 汇总成完整主工具栏共享状态。
- 让 `iOSCanvasToolbarHostView` / `macOSCanvasToolbarHostView` 从“只负责安装现成按钮”升级为“直接消费共享 `CanvasToolbarState` 渲染按钮顺序、轴向、背景和样式”。
- 收缩 `iOS/macOS` 控制器中 `Crop / Save / Import` 的样式拼装逻辑；控制器只保留共享状态生成、action 绑定、平台副作用与停靠刷新。
- 本次未执行：
- 未把 `undo/redo` history 组并入 `CanvasToolbarState.items`。
- 未修改 `BoardSaveCoordinator`、`FolderBookmarkStore` 等保存底层逻辑。
- 未进入 `阶段D` 的统一 overlay/layout context 设计。
- 未执行 git commit。

## 本次变更文件

- 修改：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- 修改：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- 到 `C3` 为止，共享层虽然已经具备 `Crop`、`Save` 的 item state 构建能力，但还没有一条完整的 `main toolbar state` 汇总入口。
- `Import` 仍完全停留在平台控制器私有样式逻辑中；host 并不知道 “toolbar 当前应该显示哪些 item、按什么顺序、每个 item 应该是什么视觉状态”。
- `iOS/macOS` 的 `toolbar host` 只接受按钮实例数组并做安装与布局，不消费共享状态，因此控制器仍持有 `applyImportButtonAppearance`、`applySaveButtonAppearance`、`applyCropButtonAppearance` 这一类样式拼装代码。
- 共享 `CanvasToolbarItemState` 缺少“按钮禁用时是否仍保留视觉角色”的表达位，导致像 `Save.saving` 这种“disabled but accent-colored” 的语义不能完整落在共享层。

### Shared ItemState 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarItemState
// 功能说明: 修改前共享 ToolbarItemState 只能表达 isEnabled / visualRole，但不能表达“禁用时是否仍保留视觉角色”。
import Foundation

struct CanvasToolbarItemState: Hashable, Sendable {
    var id: CanvasToolbarItemID
    var systemImageName: String
    var isEnabled: Bool
    var isActive: Bool
    var accessibilityLabel: String
    var accessibilityValue: String?
    var visualRole: CanvasToolbarItemVisualRole

    init(
        id: CanvasToolbarItemID,
        systemImageName: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        visualRole: CanvasToolbarItemVisualRole = .neutral
    ) {
        self.id = id
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.visualRole = visualRole
    }
}
```

### Shared Builder 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/类型名: CanvasToolbarStateBuilder / cropItemState(...) / saveItemState(...)
// 功能说明: 修改前 Builder 只能分别构建 Crop 和 Save item state，还没有主工具栏整体状态，也没有 Import item state。
import Foundation

struct CanvasToolbarStateBuilder {
    private let commandCatalog = CanvasCommandCatalog()

    func cropItemState(session: CanvasEditorSession) -> CanvasToolbarItemState {
        let descriptor = commandCatalog.descriptor(
            for: .crop,
            session: session
        )
        return cropItemState(from: descriptor)
    }

    func cropItemState(from descriptor: CanvasCommandDescriptor) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .crop,
            systemImageName: descriptor.systemImageName,
            isEnabled: descriptor.isEnabled,
            isActive: descriptor.isActive,
            accessibilityLabel: descriptor.title == "Done" ? "Done cropping" : "Crop",
            visualRole: descriptor.isActive ? .warning : .accent
        )
    }

    func saveItemState(saveState: CanvasSaveState) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .save,
            systemImageName: saveState.systemImageName,
            isEnabled: saveState.isEnabled,
            accessibilityLabel: "Save board",
            accessibilityValue: saveState.accessibilityValue,
            visualRole: saveState.visualRole
        )
    }
}
```

### iOS Host 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: installButtons(_:) / updateDockEdgeLayout()
// 功能说明: 修改前 iOS host 只负责接收按钮实例数组并安装到 stack view，样式和显示顺序都由控制器预先决定。
func installButtons(_ buttons: [UIButton]) {
    buttons.forEach { button in
        guard button.superview !== buttonsStackView else {
            return
        }

        button.removeFromSuperview()
        buttonsStackView.addArrangedSubview(button)
        ensureSquareSize(for: button)
    }
}

private func updateDockEdgeLayout() {
    buttonsStackView.axis = dockEdge.prefersHorizontalButtonLayout
        ? .horizontal
        : .vertical
    buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
        ? .center
        : .trailing
}
```

### macOS Host 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: installButtons(_:) / updateDockEdgeLayout()
// 功能说明: 修改前 macOS host 也只承担安装与排布职责，不消费任何共享 ToolbarState。
func installButtons(_ buttons: [NSButton]) {
    buttons.forEach { button in
        guard button.superview !== buttonsStackView else {
            return
        }

        button.removeFromSuperview()
        buttonsStackView.addArrangedSubview(button)
        ensureSquareSize(for: button)
    }
}

private func updateDockEdgeLayout() {
    buttonsStackView.orientation = dockEdge.prefersHorizontalButtonLayout
        ? .horizontal
        : .vertical
    buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
        ? .centerY
        : .trailing
}
```

### iOS Controller 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: toolbarButtons / installToolbarButtons() / updatePreparedToolbarDockEdge()
// 功能说明: 修改前 iOS 控制器需要自己维护按钮数组，并把现成按钮交给 host 安装；dock edge 变化时也只是把 edge 值转发给 host。
private var toolbarButtons: [UIButton] {
    [cropButton, saveButton, importButton]
}

private func installToolbarButtons() {
    toolbarHostView.installButtons(toolbarButtons)
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: applyImportButtonAppearance() / applySaveButtonAppearance(itemState:) / applyCropButtonAppearance(itemState:)
// 功能说明: 修改前 iOS 控制器仍直接拼接主工具栏三按钮的图标、颜色和可访问性文本。
private func applyImportButtonAppearance() {
    applyToolbarIconButtonAppearance(
        to: importButton,
        systemImageName: "plus",
        backgroundColor: .systemBlue,
        accessibilityLabel: "Import image",
        symbolPointSize: 20,
        symbolWeight: .bold
    )
}

private func applySaveButtonAppearance(
    itemState: CanvasToolbarItemState
) {
    applyToolbarIconButtonAppearance(
        to: saveButton,
        systemImageName: itemState.systemImageName,
        backgroundColor: toolbarBackgroundColor(for: itemState.visualRole),
        accessibilityLabel: itemState.accessibilityLabel,
        accessibilityValue: itemState.accessibilityValue,
        isEnabled: itemState.isEnabled
    )
}

private func applyCropButtonAppearance(
    itemState: CanvasToolbarItemState
) {
    applyToolbarIconButtonAppearance(
        to: cropButton,
        systemImageName: itemState.systemImageName,
        backgroundColor: itemState.isEnabled
            ? toolbarBackgroundColor(for: itemState.visualRole)
            : .systemGray3,
        accessibilityLabel: itemState.accessibilityLabel,
        accessibilityValue: itemState.accessibilityValue,
        isEnabled: itemState.isEnabled
    )
}
```

### macOS Controller 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: toolbarButtons / installToolbarButtons() / updatePreparedToolbarDockEdge()
// 功能说明: 修改前 macOS 控制器同样自己维护主工具栏按钮数组，再交给 host 做安装。
private var toolbarButtons: [NSButton] {
    [cropButton, saveButton, importButton]
}

private func installToolbarButtons() {
    toolbarHostView.installButtons(toolbarButtons)
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: applyImportButtonAppearance() / applySaveButtonAppearance(itemState:) / applyCropButtonAppearance(itemState:)
// 功能说明: 修改前 macOS 控制器也直接维护主工具栏三按钮的视觉和可访问性拼装。
private func applyImportButtonAppearance() {
    applyToolbarIconButtonAppearance(
        to: importButton,
        systemImageName: "plus",
        backgroundColor: .systemBlue,
        foregroundColor: .white,
        accessibilityLabel: "Import image",
        isEnabled: true
    )
}

private func applySaveButtonAppearance(
    itemState: CanvasToolbarItemState
) {
    applyToolbarIconButtonAppearance(
        to: saveButton,
        systemImageName: itemState.systemImageName,
        backgroundColor: toolbarBackgroundColor(for: itemState.visualRole),
        foregroundColor: .white,
        accessibilityLabel: itemState.accessibilityLabel,
        accessibilityValue: itemState.accessibilityValue,
        isEnabled: itemState.isEnabled
    )
}

private func applyCropButtonAppearance(
    itemState: CanvasToolbarItemState
) {
    applyToolbarIconButtonAppearance(
        to: cropButton,
        systemImageName: itemState.systemImageName,
        backgroundColor: itemState.isEnabled
            ? toolbarBackgroundColor(for: itemState.visualRole)
            : .quaternaryLabelColor.withAlphaComponent(0.35),
        foregroundColor: itemState.isEnabled ? .white : .secondaryLabelColor,
        accessibilityLabel: itemState.accessibilityLabel,
        isEnabled: itemState.isEnabled
    )
}
```

## 修改后

- 共享 `CanvasToolbarItemState` 现在可以表达 “disabled but keeps color role” 的语义，避免 `Save.saving` 这种状态在 host 渲染时被误灰化。
- `CanvasToolbarStateBuilder.mainToolbarState(...)` 统一输出主工具栏的 `Crop / Save / Import` 三项，控制器不再分别组织这三项的样式输入。
- 双端 host 都新增 `registerButtons(...)` 和 `render(_ state: CanvasToolbarState)`，并在内部统一完成：
- item 顺序同步
- 轴向切换
- icon-only 样式渲染
- 颜色映射
- disabled / accessibility 处理
- 双端控制器现在只保留：
- 按钮实例与 action 绑定
- 共享 state 生成
- 停靠边切换
- 平台导入流程与错误弹窗
- 主工具栏的样式拼装已经实质下沉到 host，不再散落在控制器里。

### Shared ItemState 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarItemState / preservesVisualRoleWhenDisabled
// 功能说明: C4 之后，共享 item state 可以表达“按钮禁用时是否仍保留视觉角色”，用于 Save.saving 等特殊状态。
import Foundation

struct CanvasToolbarItemState: Hashable, Sendable {
    var id: CanvasToolbarItemID
    var systemImageName: String
    var isEnabled: Bool
    var isActive: Bool
    var accessibilityLabel: String
    var accessibilityValue: String?
    var visualRole: CanvasToolbarItemVisualRole
    var preservesVisualRoleWhenDisabled: Bool

    init(
        id: CanvasToolbarItemID,
        systemImageName: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        visualRole: CanvasToolbarItemVisualRole = .neutral,
        preservesVisualRoleWhenDisabled: Bool = false
    ) {
        self.id = id
        self.systemImageName = systemImageName
        self.isEnabled = isEnabled
        self.isActive = isActive
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.visualRole = visualRole
        self.preservesVisualRoleWhenDisabled = preservesVisualRoleWhenDisabled
    }
}
```

### Shared Builder 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/类型名: mainToolbarState(...) / saveItemState(saveState:) / importItemState(isEnabled:)
// 功能说明: C4 之后，共享 Builder 可以直接产出主工具栏完整 state，并把 Import 也纳入共享状态链。
import Foundation

struct CanvasToolbarStateBuilder {
    private let commandCatalog = CanvasCommandCatalog()

    func mainToolbarState(
        session: CanvasEditorSession,
        saveState: CanvasSaveState,
        placement: CanvasToolbarPlacement,
        isImportEnabled: Bool = true,
        showsBackground: Bool = true
    ) -> CanvasToolbarState {
        CanvasToolbarState(
            placement: placement,
            items: [
                cropItemState(session: session),
                saveItemState(saveState: saveState),
                importItemState(isEnabled: isImportEnabled)
            ],
            showsBackground: showsBackground
        )
    }

    func saveItemState(saveState: CanvasSaveState) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .save,
            systemImageName: saveState.systemImageName,
            isEnabled: saveState.isEnabled,
            accessibilityLabel: "Save board",
            accessibilityValue: saveState.accessibilityValue,
            visualRole: saveState.visualRole,
            preservesVisualRoleWhenDisabled: saveState == .saving
        )
    }

    func importItemState(isEnabled: Bool = true) -> CanvasToolbarItemState {
        CanvasToolbarItemState(
            id: .importImage,
            systemImageName: "plus",
            isEnabled: isEnabled,
            accessibilityLabel: "Import image",
            visualRole: .accent
        )
    }
}
```

### iOS Host 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: registerButtons(_:) / render(_:) / syncButtons(with:) / applyAppearance(_:to:)
// 功能说明: C4 之后，iOS host 成为主工具栏共享 state 的直接渲染边界，内部统一决定顺序、轴向和单按钮外观。
private var registeredButtons: [CanvasToolbarItemID: UIButton] = [:]
private var preferredAxisOverride: CanvasToolbarAxis?

func registerButtons(_ buttons: [CanvasToolbarItemID: UIButton]) {
    registeredButtons = buttons
    buttons.values.forEach { button in
        ensureSquareSize(for: button)
    }
}

func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.dockEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}

private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
    let orderedButtons: [UIButton] = itemStates.compactMap { itemState in
        guard let button = registeredButtons[itemState.id] else {
            return nil
        }
        applyAppearance(itemState, to: button)
        return button
    }

    buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
        buttonsStackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    orderedButtons.forEach { button in
        buttonsStackView.addArrangedSubview(button)
    }
}

private func applyAppearance(
    _ itemState: CanvasToolbarItemState,
    to button: UIButton
) {
    let preservesVisualRole = itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
    button.isEnabled = itemState.isEnabled

    var configuration = button.configuration ?? UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = symbolConfiguration(
        for: itemState.id
    )
    configuration.image = UIImage(systemName: itemState.systemImageName)
    configuration.title = nil
    configuration.imagePadding = 0
    configuration.baseBackgroundColor = preservesVisualRole
        ? backgroundColor(for: itemState.visualRole)
        : .systemGray3
    configuration.baseForegroundColor = preservesVisualRole
        ? .white
        : .secondaryLabel
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.accessibilityLabel = itemState.accessibilityLabel
    button.accessibilityValue = itemState.accessibilityValue
}
```

### macOS Host 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: registerButtons(_:) / render(_:) / syncButtons(with:) / applyAppearance(_:to:)
// 功能说明: C4 之后，macOS host 同样直接渲染共享 ToolbarState，并在 host 内完成 icon-only、tooltip 与颜色落地。
private var registeredButtons: [CanvasToolbarItemID: NSButton] = [:]
private var preferredAxisOverride: CanvasToolbarAxis?

func registerButtons(_ buttons: [CanvasToolbarItemID: NSButton]) {
    registeredButtons = buttons
    buttons.values.forEach { button in
        ensureSquareSize(for: button)
    }
}

func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.dockEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}

private func syncButtons(with itemStates: [CanvasToolbarItemState]) {
    let orderedButtons: [NSButton] = itemStates.compactMap { itemState in
        guard let button = registeredButtons[itemState.id] else {
            return nil
        }
        applyAppearance(itemState, to: button)
        return button
    }

    buttonsStackView.arrangedSubviews.forEach { arrangedSubview in
        buttonsStackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    orderedButtons.forEach { button in
        buttonsStackView.addArrangedSubview(button)
    }
}

private func applyAppearance(
    _ itemState: CanvasToolbarItemState,
    to button: NSButton
) {
    let preservesVisualRole = itemState.isEnabled || itemState.preservesVisualRoleWhenDisabled
    let foregroundColor: NSColor = preservesVisualRole ? .white : .secondaryLabelColor
    let accessibilityDescription: String
    if let accessibilityValue = itemState.accessibilityValue {
        accessibilityDescription = "\(itemState.accessibilityLabel) (\(accessibilityValue))"
    } else {
        accessibilityDescription = itemState.accessibilityLabel
    }

    button.title = ""
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.wantsLayer = true
    button.layer?.cornerRadius = 12
    button.layer?.borderWidth = 1
    button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.24).cgColor
    button.layer?.backgroundColor = (preservesVisualRole
        ? backgroundColor(for: itemState.visualRole)
        : NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
    ).cgColor
    button.contentTintColor = foregroundColor
    button.toolTip = accessibilityDescription
    button.image = NSImage(
        systemSymbolName: itemState.systemImageName,
        accessibilityDescription: accessibilityDescription
    )
    button.isEnabled = itemState.isEnabled
}
```

### iOS Controller 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: toolbarButtonsByID / saveButtonState / registerToolbarButtons() / updatePreparedToolbarDockEdge()
// 功能说明: C4 之后，iOS 控制器不再传递按钮数组和样式参数，而是维护按钮 id 映射和共享状态刷新入口。
private var toolbarButtonsByID: [CanvasToolbarItemID: UIButton] {
    [
        .crop: cropButton,
        .save: saveButton,
        .importImage: importButton
    ]
}

private var saveButtonState: CanvasSaveState = .idle {
    didSet {
        renderToolbar()
    }
}

private func registerToolbarButtons() {
    toolbarHostView.registerButtons(toolbarButtonsByID)
}

private func updatePreparedToolbarDockEdge() {
    renderToolbar()
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: makeToolbarState() / renderToolbar() / updateInlineEditButtonsAppearance()
// 功能说明: C4 之后，iOS 控制器通过共享 Builder 生成主工具栏状态，并把渲染完全交给 host。
private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: CanvasToolbarPlacement(dockEdge: toolbarDockEdge)
    )
}

private func renderToolbar() {
    guard isViewLoaded else {
        return
    }

    toolbarHostView.render(makeToolbarState())
}

private func updateInlineEditButtonsAppearance() {
    renderToolbar()
    updateHistoryButtonsAppearance()
}
```

### macOS Controller 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: toolbarButtonsByID / saveButtonState / registerToolbarButtons() / updatePreparedToolbarDockEdge()
// 功能说明: C4 之后，macOS 控制器也改为用共享 state 驱动 host，而不是直接驱动按钮外观。
private var toolbarButtonsByID: [CanvasToolbarItemID: NSButton] {
    [
        .crop: cropButton,
        .save: saveButton,
        .importImage: importButton
    ]
}

private var saveButtonState: CanvasSaveState = .idle {
    didSet {
        renderToolbar()
    }
}

private func registerToolbarButtons() {
    toolbarHostView.registerButtons(toolbarButtonsByID)
}

private func updatePreparedToolbarDockEdge() {
    renderToolbar()
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: makeToolbarState() / renderToolbar() / updateInlineEditButtonsAppearance()
// 功能说明: C4 之后，macOS 控制器只负责生成共享 ToolbarState 与触发刷新，主工具栏视觉完全交给 host。
private func makeToolbarState() -> CanvasToolbarState {
    toolbarStateBuilder.mainToolbarState(
        session: editorSession,
        saveState: saveButtonState,
        placement: CanvasToolbarPlacement(dockEdge: toolbarDockEdge)
    )
}

private func renderToolbar() {
    guard isViewLoaded else {
        return
    }

    toolbarHostView.render(makeToolbarState())
}

private func updateInlineEditButtonsAppearance() {
    renderToolbar()
}
```

## 阶段C4完成情况

- 已完成：共享层新增 `preservesVisualRoleWhenDisabled` 语义位。
- 已完成：共享 `CanvasToolbarStateBuilder` 新增 `mainToolbarState(...)` 与 `importItemState(...)`。
- 已完成：`iOSCanvasToolbarHostView` 直接消费共享 `CanvasToolbarState`。
- 已完成：`macOSCanvasToolbarHostView` 直接消费共享 `CanvasToolbarState`。
- 已完成：`Import` 的外观语义并入共享主工具栏状态。
- 已完成：双端控制器中的主工具栏样式拼装逻辑显著收缩。
- 未完成：`undo/redo` history 组并入共享主工具栏状态。
- 未完成：统一 overlay/layout context 的 `D1` 设计与接线。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 C4 记录文件名，并对 C4 的 host 状态驱动改动执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_C4_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_C4_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_180149`
- `ReadLints` 对本次修改文件无报错。
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次构建过程中曾遇到 host 内 `compactMap` 的泛型推断编译错误，已通过显式标注 `[UIButton]` / `[NSButton]` 修复，并重新构建通过。

## 结论

- `C4` 的核心不是再补一个共享枚举，而是把主工具栏真正推进到 “共享状态驱动、host 负责渲染、控制器负责动作与副作用” 的边界上。
- 到这一阶段为止，`Crop / Save / Import` 已经从控制器内联样式逻辑中抽离出来，后续 `D1` 可以在不回退这些状态边界的前提下，继续推进统一的 chrome/layout 几何 contract。
