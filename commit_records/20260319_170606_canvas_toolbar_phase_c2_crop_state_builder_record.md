# 20260319_170606_canvas_toolbar_phase_c2_crop_state_builder_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段C-阶段2` 的实际代码变更。
- 本次实际产物：
- 新增共享 `CanvasToolbarStateBuilder`，把 `Crop` 的共享命令描述映射成 `CanvasToolbarItemState`。
- 让 `iOS/macOS` 控制器不再直接用 `CanvasCommandDescriptor` 拼接 `Crop` 按钮外观，改为消费共享 `itemState`。
- 在双端控制器补充 `visualRole -> 平台颜色` 的映射入口，使共享层只表达视觉语义，平台层负责最终颜色落地。
- 本次未执行：
- 未把 `Save` / `Import` / `Undo` / `Redo` 接入共享 `ToolbarStateBuilder`。
- 未把整个主工具栏改造成由完整 `CanvasToolbarState` 数组驱动。
- 未执行 git commit。

## 本次变更文件

- 新增：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- `C1` 虽然已经提供了 `CanvasToolbarItemState`、`CanvasToolbarItemVisualRole` 等共享契约，但还没有 builder 负责把共享命令层正式映射到这些状态对象。
- `iOS/macOS` 的 `Crop` 按钮仍直接读取 `commandDescriptor(for: .crop)`，平台控制器自己决定图标、启用态、激活态颜色和无障碍文案。
- 这意味着 `Crop` 的业务状态来源仍然停留在平台层，尚未真正进入共享 `Toolbar State` 链路。

### 共享 Builder 新增前状态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/类型名: 文件级共享 Builder
// 功能说明: 修改前该文件不存在；共享层只有 ToolbarState 类型契约，还没有把 Crop command descriptor 转成 ToolbarItemState 的构建器。
// 该文件在阶段C-阶段2之前尚未创建。
```

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateCropButtonAppearance() / applyCropButtonAppearance(...)
// 功能说明: 修改前 iOS 直接读取 CanvasCommandDescriptor，并在控制器里自行决定背景色和无障碍文案。
private let commandCatalog = CanvasCommandCatalog()

private func updateCropButtonAppearance() {
    let descriptor = commandDescriptor(for: .crop)
    applyCropButtonAppearance(
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        backgroundColor: descriptor.isActive ? .systemOrange : .systemIndigo,
        isEnabled: descriptor.isEnabled
    )
}

private func applyCropButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor,
    isEnabled: Bool
) {
    applyToolbarIconButtonAppearance(
        to: cropButton,
        systemImageName: systemImageName,
        backgroundColor: isEnabled ? backgroundColor : .systemGray3,
        accessibilityLabel: title == "Done" ? "Done cropping" : "Crop",
        isEnabled: isEnabled
    )
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateCropButtonAppearance() / applyCropButtonAppearance(...)
// 功能说明: 修改前 macOS 同样直接消费 CanvasCommandDescriptor，并在控制器里自行拼接视觉和可访问性语义。
private let commandCatalog = CanvasCommandCatalog()

private func updateCropButtonAppearance() {
    let descriptor = commandDescriptor(for: .crop)
    applyCropButtonAppearance(
        title: descriptor.title,
        systemImageName: descriptor.systemImageName,
        tintColor: descriptor.isActive ? .systemOrange : .controlAccentColor,
        isEnabled: descriptor.isEnabled
    )
}

private func applyCropButtonAppearance(
    title: String,
    systemImageName: String,
    tintColor: NSColor,
    isEnabled: Bool
) {
    applyToolbarIconButtonAppearance(
        to: cropButton,
        systemImageName: systemImageName,
        backgroundColor: isEnabled ? tintColor : .quaternaryLabelColor.withAlphaComponent(0.35),
        foregroundColor: isEnabled ? .white : .secondaryLabelColor,
        accessibilityDescription: title == "Done" ? "Done cropping" : "Crop",
        isEnabled: isEnabled
    )
}
```

## 修改后

- 共享层新增 `CanvasToolbarStateBuilder`，由它负责调用 `CanvasCommandCatalog`，把 `Crop` 的 `CanvasCommandDescriptor` 收敛成统一的 `CanvasToolbarItemState`。
- `Crop` 的共享状态现在统一包含：
- `id`
- `systemImageName`
- `isEnabled`
- `isActive`
- `accessibilityLabel`
- `visualRole`
- `iOS/macOS` 控制器只保留“平台渲染职责”：读取共享 `itemState`，再把 `visualRole` 映射到各自颜色体系。
- 这样 `Crop` 的“状态来源”已经从平台层挪到共享层，为后续 `Save` / `Import` / 全量 `ToolbarState` 接线打下边界。

### 共享 Builder 新增后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift
// 函数名/类型名: CanvasToolbarStateBuilder / cropItemState(session:) / cropItemState(from:)
// 功能说明: C2 新增共享 Builder，把 Crop command descriptor 统一映射为平台无关的 CanvasToolbarItemState。
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

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: toolbarStateBuilder / updateCropButtonAppearance() / toolbarBackgroundColor(for:) / applyCropButtonAppearance(itemState:)
// 功能说明: C2 之后，iOS 改为先从共享 Builder 获取 Crop item state，再由平台层完成 visualRole 到 UIColor 的落地。
private let commandCatalog = CanvasCommandCatalog()
private let toolbarStateBuilder = CanvasToolbarStateBuilder()

private func updateCropButtonAppearance() {
    let itemState = toolbarStateBuilder.cropItemState(
        session: editorSession
    )
    applyCropButtonAppearance(
        itemState: itemState
    )
}

private func toolbarBackgroundColor(
    for visualRole: CanvasToolbarItemVisualRole
) -> UIColor {
    switch visualRole {
    case .neutral:
        return .secondarySystemBackground
    case .accent:
        return .systemIndigo
    case .success:
        return .systemGreen
    case .warning:
        return .systemOrange
    case .danger:
        return .systemRed
    }
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

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: toolbarStateBuilder / updateCropButtonAppearance() / toolbarBackgroundColor(for:) / applyCropButtonAppearance(itemState:)
// 功能说明: C2 之后，macOS 也改为消费共享 Crop item state，再由平台层把 visualRole 落到 NSColor 和无障碍描述。
private let commandCatalog = CanvasCommandCatalog()
private let toolbarStateBuilder = CanvasToolbarStateBuilder()

private func updateCropButtonAppearance() {
    let itemState = toolbarStateBuilder.cropItemState(
        session: editorSession
    )
    applyCropButtonAppearance(
        itemState: itemState
    )
}

private func toolbarBackgroundColor(
    for visualRole: CanvasToolbarItemVisualRole
) -> NSColor {
    switch visualRole {
    case .neutral:
        return .controlBackgroundColor
    case .accent:
        return .controlAccentColor
    case .success:
        return .systemGreen
    case .warning:
        return .systemOrange
    case .danger:
        return .systemRed
    }
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
        accessibilityDescription: itemState.accessibilityLabel,
        isEnabled: itemState.isEnabled
    )
}
```

## 阶段C2完成情况

- 已完成：新增共享 `CanvasToolbarStateBuilder`。
- 已完成：`Crop` 的共享命令描述映射为共享 `CanvasToolbarItemState`。
- 已完成：`iOS/macOS` 两端的 `Crop` 按钮改为由共享 `itemState` 驱动。
- 已完成：共享层只表达 `visualRole`，平台层负责颜色落地。
- 未完成：`Save` / `Import` / `Undo` / `Redo` 的共享状态 builder。
- 未完成：整条主工具栏由完整 `CanvasToolbarState.items` 统一驱动。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 C2 记录文件名，并对 C2 的 Crop 共享状态接线执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_C2_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_C2_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_170606`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- `C2` 的目标不是把整个工具栏一次性状态化，而是先把 `Crop` 这条链路从“平台直接取 descriptor”推进到“共享层先产出 item state，平台再负责渲染”。
- 到这一阶段为止，工具栏已经从“只有共享状态契约”推进到了“至少有一个真实按钮开始消费共享状态”的状态，后续 `C3` 可以沿同一边界继续把 `Save` / `Import` 等项逐步接入，而不用重写平台渲染层。
