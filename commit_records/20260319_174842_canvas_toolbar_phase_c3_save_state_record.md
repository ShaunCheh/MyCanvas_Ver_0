# 20260319_174842_canvas_toolbar_phase_c3_save_state_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段C-阶段3` 的实际代码变更。
- 本次实际产物：
- 新增共享 `CanvasSaveState`，用平台无关的状态语义表达 `Save` 按钮的 `idle / saving / success / missingFolder / failure`。
- 扩展共享 `CanvasToolbarStateBuilder`，把 `CanvasSaveState` 统一映射成 `CanvasToolbarItemState`。
- 让 `iOS/macOS` 控制器不再直接用 `title / systemImageName / color` 参数链拼接 `Save` 按钮外观，改为先维护共享 `saveButtonState`，再消费共享 `itemState` 渲染。
- `macOS` 的通用工具栏图标按钮渲染入口补齐 `accessibilityLabel + accessibilityValue`，让 icon-only 的 `Save` 反馈仍然能表达辅助文本。
- 本次未执行：
- 未修改 `BoardSaveCoordinator` 的保存队列、错误传播或 autosave 机制。
- 未修改 `FolderBookmarkStore` 的书签解析逻辑。
- 未把 `Import` / 完整 `CanvasToolbarState.items` 驱动接入 host。
- 未执行 git commit。

## 本次变更文件

- 新增：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasSaveState.swift`
- 修改：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- `C2` 结束时，共享层已经能表达 `Crop` 的共享状态，但 `Save` 仍没有独立的共享状态类型。
- `iOS/macOS` 的保存反馈还停留在控制器私有实现里：点击保存后，控制器直接根据结果拼接 `title`、`systemImageName`、背景色和 `isEnabled`。
- `CanvasToolbarStateBuilder` 只支持 `Crop`，还不能把保存反馈收口为共享 `ToolbarItemState`。
- `macOS` 的通用工具栏图标按钮入口只接收单个 `accessibilityDescription` 字符串，无法像 `iOS` 一样分离 `accessibilityLabel` 与 `accessibilityValue`。

### SaveState 新增前状态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasSaveState.swift
// 函数名/类型名: 文件级共享 Save 状态类型
// 功能说明: 修改前该文件不存在；共享层还没有独立的 CanvasSaveState 来承载 Save 的反馈语义。
// 该文件在阶段C-阶段3之前尚未创建。
```

### ToolbarStateBuilder 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/类型名: CanvasToolbarStateBuilder / cropItemState(session:) / cropItemState(from:)
// 功能说明: 修改前 Builder 只覆盖 Crop，还没有 Save 的共享状态映射入口。
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
}
```

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: saveButtonResetWorkItem / handleSaveButtonTap()
// 功能说明: 修改前 iOS 在控制器里直接把保存结果转成 title、icon 和颜色参数，再立刻下发给按钮渲染层。
private var saveButtonResetWorkItem: DispatchWorkItem?

@objc
private func handleSaveButtonTap() {
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(
                title: "Saved",
                systemImageName: "checkmark",
                backgroundColor: .systemGreen
            )
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(
                    title: "No Folder",
                    systemImageName: "exclamationmark.triangle",
                    backgroundColor: .systemOrange
                )
                self.presentSaveError(
                    message: "Select a folder from the board list before saving."
                )
            } else {
                self.showSaveButtonFeedback(
                    title: "Failed",
                    systemImageName: "xmark",
                    backgroundColor: .systemRed
                )
                self.presentSaveError(message: error.localizedDescription)
            }
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: beginSaveButtonSaveState() / showSaveButtonFeedback(...) / applyDefaultSaveButtonAppearance() / applySaveButtonAppearance(...)
// 功能说明: 修改前 iOS 的 Save 按钮完全由平台私有参数链驱动，保存中/成功/失败/缺少文件夹的视觉语义都散在控制器里。
private func beginSaveButtonSaveState() {
    saveButtonResetWorkItem?.cancel()
    saveButton.isEnabled = false
    applySaveButtonAppearance(
        title: "Saving",
        systemImageName: "square.and.arrow.down",
        backgroundColor: .systemBlue
    )
}

private func showSaveButtonFeedback(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor
) {
    saveButton.isEnabled = true
    applySaveButtonAppearance(
        title: title,
        systemImageName: systemImageName,
        backgroundColor: backgroundColor
    )

    saveButtonResetWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.applyDefaultSaveButtonAppearance()
    }
    saveButtonResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
}

private func applyDefaultSaveButtonAppearance() {
    saveButton.isEnabled = true
    applySaveButtonAppearance(
        title: "Save",
        systemImageName: "square.and.arrow.down",
        backgroundColor: .systemGreen
    )
}

private func applySaveButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor
) {
    applyToolbarIconButtonAppearance(
        to: saveButton,
        systemImageName: systemImageName,
        backgroundColor: backgroundColor,
        accessibilityLabel: "Save board",
        accessibilityValue: title == "Save" ? nil : title,
        isEnabled: saveButton.isEnabled
    )
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: saveButtonResetWorkItem / handleSaveButtonClick()
// 功能说明: 修改前 macOS 也在控制器里直接下发保存结果对应的文案、图标和 tintColor。
private var saveButtonResetWorkItem: DispatchWorkItem?

@objc
private func handleSaveButtonClick() {
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(
                title: "Saved",
                systemImageName: "checkmark",
                tintColor: .systemGreen
            )
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(
                    title: "No Folder",
                    systemImageName: "exclamationmark.triangle",
                    tintColor: .systemOrange
                )
                self.presentSaveError(
                    message: "Select a folder from the board list before saving."
                )
            } else {
                self.showSaveButtonFeedback(
                    title: "Failed",
                    systemImageName: "xmark",
                    tintColor: .systemRed
                )
                self.presentSaveError(message: error.localizedDescription)
            }
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: beginSaveButtonSaveState() / showSaveButtonFeedback(...) / applyDefaultSaveButtonAppearance() / applyToolbarIconButtonAppearance(...) / applySaveButtonAppearance(...)
// 功能说明: 修改前 macOS 的 Save 状态同样是平台私有链路，而且通用图标按钮入口只有单一 accessibilityDescription，未拆分 label/value。
private func beginSaveButtonSaveState() {
    saveButtonResetWorkItem?.cancel()
    saveButton.isEnabled = false
    applySaveButtonAppearance(
        title: "Saving",
        systemImageName: "square.and.arrow.down",
        tintColor: .controlAccentColor
    )
}

private func showSaveButtonFeedback(
    title: String,
    systemImageName: String,
    tintColor: NSColor
) {
    saveButton.isEnabled = true
    applySaveButtonAppearance(
        title: title,
        systemImageName: systemImageName,
        tintColor: tintColor
    )

    saveButtonResetWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.applyDefaultSaveButtonAppearance()
    }
    saveButtonResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
}

private func applyDefaultSaveButtonAppearance() {
    saveButton.isEnabled = true
    applySaveButtonAppearance(
        title: "Save",
        systemImageName: "square.and.arrow.down",
        tintColor: .controlAccentColor
    )
}

private func applyToolbarIconButtonAppearance(
    to button: NSButton,
    systemImageName: String,
    backgroundColor: NSColor,
    foregroundColor: NSColor,
    accessibilityDescription: String,
    isEnabled: Bool
) {
    button.toolTip = accessibilityDescription
    button.image = NSImage(
        systemSymbolName: systemImageName,
        accessibilityDescription: accessibilityDescription
    )
    button.isEnabled = isEnabled
}

private func applySaveButtonAppearance(
    title: String,
    systemImageName: String,
    tintColor: NSColor
) {
    let accessibilityDescription = title == "Save"
        ? "Save board"
        : "Save board (\(title))"
    applyToolbarIconButtonAppearance(
        to: saveButton,
        systemImageName: systemImageName,
        backgroundColor: tintColor,
        foregroundColor: .white,
        accessibilityDescription: accessibilityDescription,
        isEnabled: saveButton.isEnabled
    )
}
```

## 修改后

- 共享层新增 `CanvasSaveState`，把保存反馈收口为统一状态语义，而不是继续在平台控制器里手写文案和颜色参数。
- `CanvasToolbarStateBuilder` 现在同时支持 `Crop` 和 `Save`，其中 `Save` 通过 `saveItemState(saveState:)` 输出标准 `CanvasToolbarItemState`。
- `iOS/macOS` 两端现在都维护一个共享语义的 `saveButtonState`；保存按钮 UI 更新由 `didSet -> updateSaveButtonAppearance() -> saveItemState -> applySaveButtonAppearance(itemState:)` 这条链路统一驱动。
- 保存成功、缺少文件夹、保存失败等分支还在控制器里处理，但只负责切换共享状态和弹错误提示，不再直接拼按钮的外观参数。
- `macOS` 通用图标按钮渲染入口现在支持 `accessibilityLabel + accessibilityValue`，从而让 icon-only 的保存按钮也能把 `Saving / Saved / No folder selected / Save failed` 通过辅助文本表达出来。
- 当前共享层把 `idle` / `saving` 都统一映射为 `visualRole = .accent`；也就是说 `Save` 的可见外观不再依赖控制器里单独传入的绿色/蓝色参数，而是走共享视觉语义到平台颜色的映射链。

### SaveState 新增后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasSaveState.swift
// 函数名/类型名: CanvasSaveState / systemImageName / isEnabled / accessibilityValue / visualRole
// 功能说明: C3 新增共享 Save 状态，把按钮图标、可用态、辅助文本和视觉角色都收口到平台无关的共享层。
import Foundation

enum CanvasSaveState: String, Sendable {
    case idle
    case saving
    case success
    case missingFolder
    case failure

    var systemImageName: String {
        switch self {
        case .idle, .saving:
            return "square.and.arrow.down"
        case .success:
            return "checkmark"
        case .missingFolder:
            return "exclamationmark.triangle"
        case .failure:
            return "xmark"
        }
    }

    var isEnabled: Bool {
        self != .saving
    }

    var accessibilityValue: String? {
        switch self {
        case .idle:
            return nil
        case .saving:
            return "Saving"
        case .success:
            return "Saved"
        case .missingFolder:
            return "No folder selected"
        case .failure:
            return "Save failed"
        }
    }

    var visualRole: CanvasToolbarItemVisualRole {
        switch self {
        case .idle, .saving:
            return .accent
        case .success:
            return .success
        case .missingFolder:
            return .warning
        case .failure:
            return .danger
        }
    }
}
```

### ToolbarStateBuilder 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/类型名: CanvasToolbarStateBuilder / saveItemState(saveState:)
// 功能说明: C3 之后，Builder 不仅能构建 Crop item state，也能把共享 Save 状态映射为统一的 ToolbarItemState。
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

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: saveButtonState / handleSaveButtonTap()
// 功能说明: C3 之后，iOS 把保存结果先归一到 CanvasSaveState，再由共享 Builder 驱动按钮渲染，而不是直接传 title/icon/color。
private var saveButtonResetWorkItem: DispatchWorkItem?
private var saveButtonState: CanvasSaveState = .idle {
    didSet {
        updateSaveButtonAppearance()
    }
}

@objc
private func handleSaveButtonTap() {
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(.success)
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(.missingFolder)
                self.presentSaveError(
                    message: "Select a folder from the board list before saving."
                )
            } else {
                self.showSaveButtonFeedback(.failure)
                self.presentSaveError(message: error.localizedDescription)
            }
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: beginSaveButtonSaveState() / showSaveButtonFeedback(_:) / applyDefaultSaveButtonAppearance() / updateSaveButtonAppearance() / applySaveButtonAppearance(itemState:)
// 功能说明: C3 之后，iOS 保留原有 1.2s 自动回落时序，但真正渲染 Save 按钮时只消费共享 item state。
private func beginSaveButtonSaveState() {
    saveButtonResetWorkItem?.cancel()
    saveButtonState = .saving
}

private func showSaveButtonFeedback(_ state: CanvasSaveState) {
    saveButtonState = state
    saveButtonResetWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.applyDefaultSaveButtonAppearance()
    }
    saveButtonResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
}

private func applyDefaultSaveButtonAppearance() {
    saveButtonState = .idle
}

private func updateSaveButtonAppearance() {
    let itemState = toolbarStateBuilder.saveItemState(
        saveState: saveButtonState
    )
    applySaveButtonAppearance(
        itemState: itemState
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
```

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: saveButtonState / handleSaveButtonClick()
// 功能说明: C3 之后，macOS 的保存结果也先收口到 CanvasSaveState，再通过共享 item state 驱动 Save 按钮。
private var saveButtonResetWorkItem: DispatchWorkItem?
private var saveButtonState: CanvasSaveState = .idle {
    didSet {
        updateSaveButtonAppearance()
    }
}

@objc
private func handleSaveButtonClick() {
    beginSaveButtonSaveState()
    saveBoardNow(
        reason: "manual save",
        createBoardIfNeeded: true
    ) { [weak self] result in
        guard let self else {
            return
        }

        switch result {
        case .success:
            self.showSaveButtonFeedback(.success)
        case let .failure(error):
            if case FolderBookmarkStoreError.missingBookmarkData = error {
                self.showSaveButtonFeedback(.missingFolder)
                self.presentSaveError(
                    message: "Select a folder from the board list before saving."
                )
            } else {
                self.showSaveButtonFeedback(.failure)
                self.presentSaveError(message: error.localizedDescription)
            }
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: beginSaveButtonSaveState() / showSaveButtonFeedback(_:) / applyDefaultSaveButtonAppearance() / updateSaveButtonAppearance()
// 功能说明: C3 之后，macOS 保留原有延时回落，但状态切换只更新共享 saveButtonState，不再直接写按钮标题和颜色。
private func beginSaveButtonSaveState() {
    saveButtonResetWorkItem?.cancel()
    saveButtonState = .saving
}

private func showSaveButtonFeedback(_ state: CanvasSaveState) {
    saveButtonState = state
    saveButtonResetWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
        self?.applyDefaultSaveButtonAppearance()
    }
    saveButtonResetWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: workItem)
}

private func applyDefaultSaveButtonAppearance() {
    saveButtonState = .idle
}

private func updateSaveButtonAppearance() {
    let itemState = toolbarStateBuilder.saveItemState(
        saveState: saveButtonState
    )
    applySaveButtonAppearance(
        itemState: itemState
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: applyToolbarIconButtonAppearance(...) / applySaveButtonAppearance(itemState:)
// 功能说明: C3 之后，macOS 的通用 icon-only 按钮入口支持 label/value 组合，从而让 Save 的辅助文本跟随共享状态一起更新。
private func applyToolbarIconButtonAppearance(
    to button: NSButton,
    systemImageName: String,
    backgroundColor: NSColor,
    foregroundColor: NSColor,
    accessibilityLabel: String,
    accessibilityValue: String? = nil,
    isEnabled: Bool
) {
    let accessibilityDescription: String
    if let accessibilityValue {
        accessibilityDescription = "\(accessibilityLabel) (\(accessibilityValue))"
    } else {
        accessibilityDescription = accessibilityLabel
    }
    button.toolTip = accessibilityDescription
    button.image = NSImage(
        systemSymbolName: systemImageName,
        accessibilityDescription: accessibilityDescription
    )
    button.isEnabled = isEnabled
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
```

## 阶段C3完成情况

- 已完成：新增共享 `CanvasSaveState`。
- 已完成：`CanvasToolbarStateBuilder` 新增 `saveItemState(saveState:)`。
- 已完成：`iOS/macOS` 的 `Save` 按钮改为通过共享 `saveButtonState` 和共享 `itemState` 渲染。
- 已完成：`macOS` 通用 icon-only 按钮渲染支持 `accessibilityLabel + accessibilityValue`。
- 已完成：保留现有 `1.2s` 自动回落时序，不改手动保存触发链路。
- 未完成：`Import` 并入共享 toolbar state。
- 未完成：完整主工具栏由 `CanvasToolbarState.items` 统一驱动。
- 未完成：保存系统底层 dirty/persisted 真状态治理。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 C3 记录文件名，并对 C3 的 Save 共享状态收口改动执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_C3_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_C3_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_174842`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- `C3` 的核心不是重写保存系统，而是把 `Save` 的视觉反馈从“平台控制器私有参数链”推进到“共享保存状态 -> 共享工具栏 item state -> 平台渲染”的链路。
- 到这一阶段为止，`Crop` 和 `Save` 都已经具备共享状态输入，后续 `C4` 可以继续把 `Import` 和 host 渲染入口接到同一份 `CanvasToolbarState` 上，而不需要再回头重设计状态边界。
