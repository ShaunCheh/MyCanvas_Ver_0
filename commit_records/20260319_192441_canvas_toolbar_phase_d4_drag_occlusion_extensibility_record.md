# 20260319_192441_canvas_toolbar_phase_d4_drag_occlusion_extensibility_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段D-阶段4` 的实际代码变更。
- 本次实际产物：
- 扩展共享 `CanvasToolbarPlacement`，在现有 `offsetAlongEdge` 之外补入 `preferredEdge` 与 `isUserPinned`，为未来拖拽停靠输入预留稳定 contract。
- 保留 `dockEdge` 兼容入口，但让共享层和双端 host/solver 明确转向 `preferredEdge` 语义，避免后续再把“当前解析结果”和“用户偏好边”混成一个概念。
- 收口 `iOS/macOS` controller 的工具栏停靠瞬时状态，不再拆成 `toolbarDockEdge + toolbarOffsetAlongEdge` 两个散落标量，而是统一为 `transientToolbarPlacement`。
- 在双端 controller 中显式标注未来手势桥接点：
- `iOS` 未来由 `UIPanGestureRecognizer` 回写 placement。
- `macOS` 未来由 `NSPanGestureRecognizer` 回写 placement。
- 将 `context menu` 的共享默认遮挡策略从 `allowChromeOverlap` 切换为 `avoidOverlayChrome`，并同步移除 host 中对“允许覆盖 chrome”的显式覆盖，明确菜单默认避让 toolbar / minimap / back button 等 overlay chrome。
- 本次未执行：
- 未真正实现 `UIPanGestureRecognizer` / `NSPanGestureRecognizer` 的拖拽停靠交互。
- 未把工具栏停靠偏好持久化到 `board` 文档或其他长期存储。
- 未修改 `CanvasContextMenuLayoutSolver` 的候选位置算法本体，只调整默认 `occlusionPolicy`。
- 未执行 git commit。

## 本次变更文件

- 修改：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- 修改：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift`
- 修改：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
- 修改：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- 到 `D3` 结束时，工具栏位置已经进入统一 overlay 链，但 placement model 仍然更偏“当前布局结果”的表达，还没有明确承接未来拖拽输入的语义位。
- `CanvasToolbarPlacement` 只有：
- `dockEdge`
- `dockAlignment`
- `offsetAlongEdge`
- 没有独立的 `preferredEdge` 与 `isUserPinned`。
- 双端 controller 仍然分别维护：
- `toolbarDockEdge`
- `toolbarOffsetAlongEdge`
- 这意味着后续真接拖拽时，还要继续把手势结果拆回多个局部字段。
- `context menu` 的共享默认策略还是 `allowChromeOverlap`，host 还会再次显式设置为允许覆盖 chrome，因此虽然 `D3` 已经把 toolbar 纳入 blocker 链，但菜单在默认策略上依然允许压住工具栏。

### Shared Placement Contract 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarPlacement
// 功能说明: 修改前共享 placement 还没有 preferredEdge / isUserPinned，只有 dockEdge、dockAlignment 和 offsetAlongEdge。
import CoreGraphics
import Foundation

struct CanvasToolbarPlacement: Hashable, Sendable {
    var dockEdge: CanvasToolbarDockEdge
    var dockAlignment: CanvasToolbarDockAlignment
    var offsetAlongEdge: CGFloat

    init(
        dockEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered,
        offsetAlongEdge: CGFloat = 0
    ) {
        self.dockEdge = dockEdge
        self.dockAlignment = dockAlignment
        self.offsetAlongEdge = offsetAlongEdge
    }
}
```

### Shared Placement Solver 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift
// 函数名/类型名: clampedLeadingCoordinate(for:size:in:) / blockingInterval(for:placement:size:in:) / frame(for:size:leadingCoordinate:in:)
// 功能说明: 修改前 solver 全程都依赖 placement.dockEdge，尚未显式区分“首选停靠边”和“当前兼容别名”。
private func clampedLeadingCoordinate(
    for placement: CanvasToolbarPlacement,
    size: CGSize,
    in bounds: CGRect
) -> CGFloat {
    let range = leadingCoordinateRange(
        for: placement.dockEdge,
        size: size,
        in: bounds
    )
    let centeredLeadingCoordinate: CGFloat

    switch placement.dockEdge {
    case .top, .bottom:
        centeredLeadingCoordinate = bounds.midX - (size.width / 2)
    case .leading, .trailing:
        centeredLeadingCoordinate = bounds.midY - (size.height / 2)
    }

    return clamp(
        centeredLeadingCoordinate + placement.offsetAlongEdge,
        minValue: range.min,
        maxValue: range.max
    )
}
```

### ContextMenu 遮挡策略修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuLayoutConfiguration
// 功能说明: 修改前 context menu 的共享默认策略仍是 allowChromeOverlap，默认允许覆盖 overlay chrome。
struct CanvasContextMenuLayoutConfiguration {
    var minimumWidth: CGFloat = 180
    var maximumWidth: CGFloat = 280
    var edgeInset: CGFloat = 16
    var anchorSpacing: CGFloat = 10
    var chromeClearance: CGFloat = 12
    var occlusionPolicy: CanvasContextMenuOcclusionPolicy = .allowChromeOverlap
    var placementStyle: CanvasContextMenuPlacementStyle = .cursorPreferred
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: layoutConfiguration
// 功能说明: 修改前 iOS/macOS host 还会再次显式把 occlusionPolicy 设为 allowChromeOverlap，使默认菜单继续允许覆盖 toolbar/minimap。
private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
    var configuration = CanvasContextMenuLayoutConfiguration()
    configuration.occlusionPolicy = .allowChromeOverlap
    configuration.placementStyle = .cursorPreferred
    return configuration
}()
```

### iOS Controller / Host 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: toolbarDockEdge / toolbarOffsetAlongEdge / toolbarPreferredPlacement()
// 功能说明: 修改前 iOS controller 仍把停靠偏好拆成两个局部标量，未来拖拽结果还没有统一写回入口。
private var toolbarDockEdge: CanvasToolbarDockEdge = .trailing {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}
private var toolbarOffsetAlongEdge: CGFloat = 0 {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    CanvasToolbarPlacement(
        dockEdge: toolbarDockEdge,
        offsetAlongEdge: toolbarOffsetAlongEdge
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: render(_:)
// 功能说明: 修改前 iOS toolbar host 仍直接消费 placement.dockEdge，尚未转向 preferredEdge 语义。
func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.dockEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}
```

### macOS Controller / Host 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: toolbarDockEdge / toolbarOffsetAlongEdge / toolbarPreferredPlacement()
// 功能说明: 修改前 macOS controller 也把停靠偏好拆成两个局部标量，未来 pointer drag 还没有稳定回写点。
private var toolbarDockEdge: CanvasToolbarDockEdge = .trailing {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}
private var toolbarOffsetAlongEdge: CGFloat = 0 {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    CanvasToolbarPlacement(
        dockEdge: toolbarDockEdge,
        offsetAlongEdge: toolbarOffsetAlongEdge
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: render(_:)
// 功能说明: 修改前 macOS toolbar host 同样直接读取 placement.dockEdge，语义上仍偏向旧的停靠字段。
func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.dockEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}
```

## 修改后

- 共享 placement contract 现在可以承接未来拖拽输入：
- `preferredEdge`
- `dockAlignment`
- `offsetAlongEdge`
- `isUserPinned`
- 同时保留 `dockEdge` 作为兼容别名，避免立刻打断现有调用面。
- `CanvasToolbarPlacementSolver` 与双端 toolbar host 都明确切换到 `preferredEdge`，把“用户停靠偏好边”作为一等语义。
- 双端 controller 都新增了一个统一的瞬时 placement 状态：
- `transientToolbarPlacement`
- 并在注释中明确未来手势桥接点：
- `iOS`: `UIPanGestureRecognizer`
- `macOS`: `NSPanGestureRecognizer`
- `context menu` 共享默认策略现在改为 `avoidOverlayChrome`，host 也不再覆盖回 `allowChromeOverlap`，菜单默认会参与避让 toolbar / minimap / back button。
- 是否持久化停靠偏好仍明确保持“暂不实现”，当前只在 controller 内存中维护瞬时状态。

### Shared Placement Contract 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarPlacement / dockEdge
// 功能说明: D4 之后，共享 placement 可以同时表达 preferredEdge、offsetAlongEdge 与 isUserPinned，并保留 dockEdge 兼容入口。
import CoreGraphics
import Foundation

struct CanvasToolbarPlacement: Hashable, Sendable {
    var preferredEdge: CanvasToolbarDockEdge
    var dockAlignment: CanvasToolbarDockAlignment
    var offsetAlongEdge: CGFloat
    var isUserPinned: Bool

    var dockEdge: CanvasToolbarDockEdge {
        get {
            preferredEdge
        }
        set {
            preferredEdge = newValue
        }
    }

    init(
        preferredEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered,
        offsetAlongEdge: CGFloat = 0,
        isUserPinned: Bool = false
    ) {
        self.preferredEdge = preferredEdge
        self.dockAlignment = dockAlignment
        self.offsetAlongEdge = offsetAlongEdge
        self.isUserPinned = isUserPinned
    }
}
```

### Shared Placement Solver 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift
// 函数名/类型名: clampedLeadingCoordinate(for:size:in:) / blockingInterval(for:placement:size:in:) / frame(for:size:leadingCoordinate:in:)
// 功能说明: D4 之后，solver 显式改为围绕 preferredEdge 求解，为未来“用户偏好边”和“解析结果”分层打基础。
private func clampedLeadingCoordinate(
    for placement: CanvasToolbarPlacement,
    size: CGSize,
    in bounds: CGRect
) -> CGFloat {
    let range = leadingCoordinateRange(
        for: placement.preferredEdge,
        size: size,
        in: bounds
    )
    let centeredLeadingCoordinate: CGFloat

    switch placement.preferredEdge {
    case .top, .bottom:
        centeredLeadingCoordinate = bounds.midX - (size.width / 2)
    case .leading, .trailing:
        centeredLeadingCoordinate = bounds.midY - (size.height / 2)
    }

    return clamp(
        centeredLeadingCoordinate + placement.offsetAlongEdge,
        minValue: range.min,
        maxValue: range.max
    )
}

private func frame(
    for placement: CanvasToolbarPlacement,
    size: CGSize,
    leadingCoordinate: CGFloat,
    in bounds: CGRect
) -> CGRect {
    switch placement.preferredEdge {
    case .top:
        return CGRect(x: leadingCoordinate, y: bounds.minY, width: size.width, height: size.height)
    case .bottom:
        return CGRect(x: leadingCoordinate, y: bounds.maxY - size.height, width: size.width, height: size.height)
    case .leading:
        return CGRect(x: bounds.minX, y: leadingCoordinate, width: size.width, height: size.height)
    case .trailing:
        return CGRect(x: bounds.maxX - size.width, y: leadingCoordinate, width: size.width, height: size.height)
    }
}
```

### ContextMenu 遮挡策略修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 函数名/类型名: CanvasContextMenuLayoutConfiguration
// 功能说明: D4 之后，context menu 的共享默认策略改为 avoidOverlayChrome，默认会避让 overlay chrome。
struct CanvasContextMenuLayoutConfiguration {
    var minimumWidth: CGFloat = 180
    var maximumWidth: CGFloat = 280
    var edgeInset: CGFloat = 16
    var anchorSpacing: CGFloat = 10
    var chromeClearance: CGFloat = 12
    var occlusionPolicy: CanvasContextMenuOcclusionPolicy = .avoidOverlayChrome
    var placementStyle: CanvasContextMenuPlacementStyle = .cursorPreferred
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift
// 函数名/类型名: layoutConfiguration
// 功能说明: D4 之后，iOS/macOS host 不再把 occlusionPolicy 强行改回 allowChromeOverlap，而是继承共享默认避让策略。
private let layoutConfiguration: CanvasContextMenuLayoutConfiguration = {
    var configuration = CanvasContextMenuLayoutConfiguration()
    configuration.placementStyle = .cursorPreferred
    return configuration
}()
```

### iOS Controller / Host 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: transientToolbarPlacement / toolbarPreferredPlacement()
// 功能说明: D4 之后，iOS controller 用一个统一的瞬时 placement 状态承接未来拖拽输入，并明确暂不持久化到 board。
// Keep placement transient until persistence is designed; future UIPanGestureRecognizer
// bridge code should write drag results back into this value.
private var transientToolbarPlacement = CanvasToolbarPlacement(
    preferredEdge: .trailing
) {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    transientToolbarPlacement
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: render(_:)
// 功能说明: D4 之后，iOS toolbar host 明确读取 placement.preferredEdge，而不是继续依赖旧的 dockEdge 主语义。
func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}
```

### macOS Controller / Host 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: transientToolbarPlacement / toolbarPreferredPlacement()
// 功能说明: D4 之后，macOS controller 同样把停靠偏好收口成统一 placement 瞬时态，并为 NSPanGestureRecognizer 桥接预留回写点。
// Keep placement transient until persistence is designed; future NSPanGestureRecognizer
// bridge code should write drag results back into this value.
private var transientToolbarPlacement = CanvasToolbarPlacement(
    preferredEdge: .trailing
) {
    didSet {
        guard isViewLoaded else {
            return
        }

        updatePreparedToolbarPlacement()
    }
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    transientToolbarPlacement
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: render(_:)
// 功能说明: D4 之后，macOS toolbar host 也统一读取 placement.preferredEdge，和共享 contract 语义保持一致。
func render(_ state: CanvasToolbarState) {
    preferredAxisOverride = state.preferredAxis
    dockEdge = state.placement.preferredEdge
    backgroundView.isHidden = state.showsBackground == false
    isHidden = state.items.isEmpty
    syncButtons(with: state.items)
}
```

## 验证结果

- 已执行 `ReadLints`，检查以下文件，结果无新增 lint 问题：
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`
- `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarPlacementSolver.swift`
- `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
- `MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 已执行 iOS Debug 构建并通过：
- `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=iOS Simulator" -derivedDataPath ".build/ios-sim" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" AD_HOC_CODE_SIGNING_ALLOWED=NO`
- 已执行 macOS Debug 构建并通过：
- `DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "generic/platform=macOS" -derivedDataPath ".build/macos" build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`

## 结果说明

- `D4` 的重点不是把拖拽停靠直接做完，而是把“未来拖拽输入写到哪里”“菜单默认是否避让 toolbar”“停靠偏好是否立刻持久化”这三个架构边界定稳。
- 当前结论已经落到代码里：
- placement 输入可扩展到拖拽桥接。
- context menu 默认避让 overlay chrome。
- toolbar placement 仍保持 controller 级瞬时状态，不与 board 持久化绑定。
