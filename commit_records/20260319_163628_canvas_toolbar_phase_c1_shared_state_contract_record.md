# 20260319_163628_canvas_toolbar_phase_c1_shared_state_contract_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段C-阶段1` 的实际代码变更。
- 本次实际产物：
- 扩展共享 `CanvasToolbarDockEdge`，补齐平台无关的 `CanvasToolbarAxis` 与 `preferredAxis` 语义。
- 新增共享状态契约文件 `CanvasToolbarState.swift`。
- 在共享层定义：
- `CanvasToolbarDockAlignment`
- `CanvasToolbarItemID`
- `CanvasToolbarItemVisualRole`
- `CanvasToolbarPlacement`
- `CanvasToolbarItemState`
- `CanvasToolbarState`
- 本次未执行：
- 未接入 `Crop` 的共享命令映射。
- 未接入 `Save` 的共享状态。
- 未修改 `iOS/macOS` 控制器渲染逻辑。
- 未执行 git commit。

## 本次变更文件

- 修改：`MyCanvas_Ver_0/Platform/Shared/CanvasToolbarDockEdge.swift`
- 新增：`MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift`

## 修改前

- 共享层只有 `CanvasToolbarDockEdge`，且它只提供了一个 `prefersHorizontalButtonLayout` 布尔值。
- 项目里还没有独立的 `CanvasToolbarState` 共享契约，也没有统一的 `Toolbar Item` / `Placement` / `Visual Role` 类型。
- 因此在 `C1` 之前，工具栏虽然已经有布局和 UI 外壳，但还没有一组真正可供 `C2/C3/C4` 继续挂接的跨平台状态模型。

### DockEdge 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasToolbarDockEdge.swift
// 函数名/类型名: CanvasToolbarDockEdge / prefersHorizontalButtonLayout
// 功能说明: 修改前共享层只知道“当前 edge 是否偏好横向按钮排布”，还没有抽出平台无关的 ToolbarAxis 语义。
import Foundation

enum CanvasToolbarDockEdge: CaseIterable {
    case top
    case bottom
    case leading
    case trailing

    var prefersHorizontalButtonLayout: Bool {
        switch self {
        case .top, .bottom:
            return true
        case .leading, .trailing:
            return false
        }
    }
}
```

### ToolbarState 文件修改前状态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: 文件级共享状态契约
// 功能说明: 修改前该文件不存在；项目里还没有统一的 Canvas 工具栏共享状态模型。
// 该文件在阶段C-阶段1之前尚未创建。
```

## 修改后

- `CanvasToolbarDockEdge` 现在除了保留现有 `prefersHorizontalButtonLayout`，还显式暴露了 `preferredAxis`，并让 `DockEdge` 与 `ToolbarAxis` 都具备共享层可复用的 `Sendable` / `RawRepresentable` 语义。
- 新增 `CanvasToolbarState.swift` 后，工具栏的共享状态契约已经具备了这几层语义：
- 停靠位置：`CanvasToolbarPlacement`
- 停靠对齐：`CanvasToolbarDockAlignment`
- 单个工具项身份：`CanvasToolbarItemID`
- 单个工具项状态：`CanvasToolbarItemState`
- 单个工具项视觉角色：`CanvasToolbarItemVisualRole`
- 整体工具栏状态：`CanvasToolbarState`
- 这些类型都只依赖 `Foundation`，没有把 `UIKit/AppKit`、平台颜色对象或平台控件实例带进共享层。

### DockEdge 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasToolbarDockEdge.swift
// 函数名/类型名: CanvasToolbarAxis / CanvasToolbarDockEdge / preferredAxis / prefersHorizontalButtonLayout
// 功能说明: C1 之后，共享层不仅能表达工具栏停靠边，还能显式表达“主工具栏偏好的轴向语义”，为后续 ToolbarState 提供平台无关输入。
import Foundation

enum CanvasToolbarAxis: String, Sendable {
    case horizontal
    case vertical
}

enum CanvasToolbarDockEdge: String, CaseIterable, Sendable {
    case top
    case bottom
    case leading
    case trailing

    var preferredAxis: CanvasToolbarAxis {
        switch self {
        case .top, .bottom:
            return .horizontal
        case .leading, .trailing:
            return .vertical
        }
    }

    var prefersHorizontalButtonLayout: Bool {
        preferredAxis == .horizontal
    }
}
```

### ToolbarState 新增代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarState.swift
// 函数名/类型名: CanvasToolbarDockAlignment / CanvasToolbarItemID / CanvasToolbarItemVisualRole / CanvasToolbarPlacement / CanvasToolbarItemState / CanvasToolbarState
// 功能说明: C1 新增共享工具栏状态契约，把 placement、item state、visual role 与整体 toolbar state 收敛到平台无关的共享层。
import Foundation

enum CanvasToolbarDockAlignment: String, Sendable {
    case centered
}

enum CanvasToolbarItemID: String, CaseIterable, Sendable {
    case crop
    case save
    case importImage
    case undo
    case redo
}

enum CanvasToolbarItemVisualRole: String, Sendable {
    case neutral
    case accent
    case success
    case warning
    case danger
}

struct CanvasToolbarPlacement: Hashable, Sendable {
    var dockEdge: CanvasToolbarDockEdge
    var dockAlignment: CanvasToolbarDockAlignment

    init(
        dockEdge: CanvasToolbarDockEdge,
        dockAlignment: CanvasToolbarDockAlignment = .centered
    ) {
        self.dockEdge = dockEdge
        self.dockAlignment = dockAlignment
    }
}

struct CanvasToolbarItemState: Hashable, Sendable {
    var id: CanvasToolbarItemID
    var systemImageName: String
    var isEnabled: Bool
    var isActive: Bool
    var accessibilityLabel: String
    var accessibilityValue: String?
    var visualRole: CanvasToolbarItemVisualRole
}

struct CanvasToolbarState: Hashable, Sendable {
    var placement: CanvasToolbarPlacement
    var items: [CanvasToolbarItemState]
    var showsBackground: Bool
    var preferredAxis: CanvasToolbarAxis
}
```

## 阶段C1完成情况

- 已完成：共享 `CanvasToolbarAxis` 语义定义。
- 已完成：共享 `CanvasToolbarPlacement` / `CanvasToolbarItemState` / `CanvasToolbarState` 契约定义。
- 已完成：工具栏共享状态类型与平台层解耦，不依赖 `UIKit/AppKit`。
- 已完成：为 `C2/C3` 预留 `visualRole`、`accessibilityValue`、`preferredAxis` 这些扩展位。
- 未完成：`Crop` 状态接入共享 builder。
- 未完成：`Save` 状态接入共享 state。
- 未完成：host/render 层消费这份状态契约。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 C1 记录文件名，并对 C1 的共享类型契约改动执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_C1_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_C1_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_163628`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- `C1` 的目标不是把工具栏状态真正接进控制器，而是先把“共享状态契约”这层地基搭好。
- 到这一阶段为止，工具栏已经从“只有 UI 结构和停靠行为”推进到了“拥有独立共享状态模型”的状态，下一步 `C2` 可以直接把 `Crop` 的共享命令描述映射进这套契约，而不需要再回头重设计类型边界。
