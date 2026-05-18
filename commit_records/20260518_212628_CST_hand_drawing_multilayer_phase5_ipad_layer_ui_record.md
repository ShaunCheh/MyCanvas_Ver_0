# 20260518_212628_CST_hand_drawing_multilayer_phase5_ipad_layer_ui_record

## 记录范围

- 记录内容：
  1. 实施 `手绘多图层` 计划的阶段 5：`为 iPad 编辑器补最小可行的 layer 管理入口与状态面板`。
  2. 在 iPad 手绘编辑器中增加 `顶栏 Layers 按钮 + 弹出 layer 管理面板` 的最小可行入口。
  3. 由 `HandDrawingEditorCoordinator` 统一产出 `LayerPanelState`，并承接 layer 相关 UI 命令。
  4. 补共享 layer panel 状态构建逻辑与回归测试，并完成本轮构建/诊断验证。
- 时间戳来源：
  - `date '+%Y%m%d_%H%M%S_CST'` -> `20260518_212628_CST`
- 说明：
  - 本记录只覆盖刚刚实施的阶段 5，不包含阶段 6 的宿主兼容与提交流水线对齐，也不包含阶段 7 的总回归收口。
  - 本记录基于当前 `git status`、当前 `git diff`、当前文件内容与本轮验证结果整理。
  - 不放原始 `git diff`，仅按“修改前 / 修改后”如实说明。
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - 当前文件内容：
    - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLayerPanelState.swift`
    - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift`
    - `MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
  - 计划文件：
    - `.cursor/plans/手绘多图层_1e238dea.plan.md`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLayerPanelState.swift`
  - `?? MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift`
  - `?? MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
  - `M MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
    - 这是 IDE 会话状态文件，不属于本次阶段 5 代码实现，本记录不展开。
- 验证结果：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322'`
    - 通过
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64,id=00006040-001C099034A0801C' -only-testing:MyCanvas_Ver_0Tests/HandDrawingLayerPanelStateTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests`
    - 通过
  - `ReadLints`
    - 本次改动文件未引入新的 linter 问题
- 本记录不包含：
  - 阶段 6 的 board / preview / thumbnail / minimap 宿主兼容
  - 阶段 7 的总回归收口
  - git commit / push

## 修改一：新增共享 `HandDrawingLayerPanelState` / `HandDrawingLayerPanelStateBuilder`

### 修改前

- 代码库中没有专门描述 iPad layer 面板的数据契约。
- 如果直接在 `UIViewController` 里拼 layer 列表，就需要临时计算：
  - 顶栏标题和副标题
  - 反向展示顺序（顶部 layer 在前）
  - `Current / Hidden / Locked` 文案
  - 上下移动和删除按钮的可用状态
- 这会把 layer 业务散到 `VC`，与阶段 5 的目标相反。

```swift
// 文件路径: 无（阶段 5 前不存在独立的 layer panel 状态文件）
// 函数名: 无
// 功能注释: 修改前没有共享的 layer panel 状态构建器，UI 若要展示图层列表只能自行读取 document 并拼装展示语义。
// 修改前不存在 HandDrawingLayerPanelState
// 修改前不存在 HandDrawingLayerPanelRowState
// 修改前不存在 HandDrawingLayerPanelStateBuilder.makeState(from:)
```

### 修改后

- 新增 `HandDrawingLayerPanelRowState` 和 `HandDrawingLayerPanelState`，把面板渲染所需数据收敛成单独契约。
- 新增 `HandDrawingLayerPanelStateBuilder.makeState(from:)`：
  - 统一产出 `Layers (N)` 标题
  - 用当前活动层名称填充按钮副标题
  - 按“顶层在前”的顺序输出 rows
  - 生成 `Current / Hidden / Locked` 状态副标题
  - 计算 `canMoveUp / canMoveDown / canDelete`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLayerPanelState.swift
// 函数名: HandDrawingLayerPanelStateBuilder.makeState(from:) / layerRowSubtitle(for:isActive:)
// 功能注释: 修改后共享层统一负责把 document 转成 layer panel 展示状态，避免 VC 自己拼业务语义。
struct HandDrawingLayerPanelState: Equatable {
    var buttonTitle: String
    var buttonSubtitle: String
    var canAddLayer: Bool
    var layers: [HandDrawingLayerPanelRowState]
}

enum HandDrawingLayerPanelStateBuilder {
    static func makeState(
        from document: HandDrawingDocument
    ) -> HandDrawingLayerPanelState {
        let layers = document.layers
        return HandDrawingLayerPanelState(
            buttonTitle: "Layers (\(layers.count))",
            buttonSubtitle: document.activeLayer?.name ?? "Layer",
            canAddLayer: true,
            layers: layers.enumerated().reversed().map { index, layer in
                let isActive = layer.id == document.activeLayerID
                return HandDrawingLayerPanelRowState(
                    id: layer.id,
                    name: layer.name,
                    subtitle: layerRowSubtitle(for: layer, isActive: isActive),
                    isActive: isActive,
                    isVisible: layer.isVisible,
                    isLocked: layer.isLocked,
                    canMoveUp: index < layers.count - 1,
                    canMoveDown: index > 0,
                    canDelete: layers.count > 1
                )
            }
        )
    }
}
```

## 修改二：`HandDrawingEditorCoordinator` 统一产出 layer panel 状态并封装 layer 命令入口

### 修改前

- `Coordinator` 只有 `surface` 和 `palette` 两类状态回调。
- 阶段 3 已经有 `applyLayerCommand(_:)`，但没有面向 UI 的更细粒度入口，也没有 `LayerPanelState` 输出。
- `activate()` 和画布重绘流程不会主动发布 layer panel 状态。
- `selectedStrokeBounds` 即使当前层被隐藏，也仍会尝试按选区计算 bounds。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.activate / applyLayerCommand(_:) / selectedStrokeBounds
// 功能注释: 修改前 coordinator 只负责 surface 和 palette，同步 layer UI 需要 VC 额外理解 document 结构。
var onSurfaceStateChange: ((HandDrawingCanvasSurfaceState) -> Void)?
var onPaletteStateChange: ((HandDrawingToolPaletteState) -> Void)?
var onErrorMessage: ((String) -> Void)?

func activate() {
    publishSurfaceState()
    publishPaletteState()
}

func applyLayerCommand(_ command: HandDrawingLayerCommand) {
    endTransientInteractionState()
    guard engine.apply(layerCommand: command) else {
        publishSurfaceState()
        publishPaletteState()
        return
    }
    refreshCommittedImageAndPublishState(forceFullRender: true)
}
```

### 修改后

- 新增 `onLayerPanelStateChange`。
- `activate()`、`applyLayerCommand(_:)` 失败分支、`refreshCommittedImageAndPublishState(...)` 都会同步发布 layer panel 状态。
- 对 UI 暴露显式命令入口：
  - `addLayer()`
  - `deleteLayer(withID:)`
  - `renameLayer(withID:to:)`
  - `selectLayer(withID:)`
  - `toggleLayerVisibility(withID:)`
  - `toggleLayerLock(withID:)`
  - `moveLayerUp(withID:)`
  - `moveLayerDown(withID:)`
- `makeLayerPanelState()` 改为直接调用共享的 `HandDrawingLayerPanelStateBuilder`。
- `selectedStrokeBounds` 增加隐藏层保护，避免当前层不可见时仍显示选区框。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.activate / addLayer() / deleteLayer(withID:) / renameLayer(withID:to:) / selectLayer(withID:) / toggleLayerVisibility(withID:) / toggleLayerLock(withID:) / moveLayerUp(withID:) / moveLayerDown(withID:) / makeLayerPanelState()
// 功能注释: 修改后 coordinator 统一承接 layer panel 的状态产出和交互命令，VC 不再直接理解 layer 业务。
var onSurfaceStateChange: ((HandDrawingCanvasSurfaceState) -> Void)?
var onPaletteStateChange: ((HandDrawingToolPaletteState) -> Void)?
var onLayerPanelStateChange: ((HandDrawingLayerPanelState) -> Void)?
var onErrorMessage: ((String) -> Void)?

func activate() {
    publishSurfaceState()
    publishPaletteState()
    publishLayerPanelState()
}

func addLayer() {
    applyLayerCommand(.addLayer(name: nil))
}

func renameLayer(withID layerID: UUID, to proposedName: String) {
    applyLayerCommand(.renameLayer(id: layerID, name: proposedName))
}

private func makeLayerPanelState() -> HandDrawingLayerPanelState {
    HandDrawingLayerPanelStateBuilder.makeState(from: engine.state.document)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingEditorCoordinator.publishPaletteState() / selectedStrokeBounds
// 功能注释: 修改后 coordinator 会把 active layer 的可交互状态传给 palette，并在隐藏层时去掉选区显示。
private func publishPaletteState() {
    onPaletteStateChange?(
        HandDrawingToolPaletteState(
            selectedTool: selectedTool,
            selectedColor: selectedColor,
            selectedLineWidth: selectedLineWidth,
            availableColors: Self.defaultColors,
            availableLineWidths: Self.defaultLineWidths,
            canUndo: engine.canUndo,
            canRedo: engine.canRedo,
            isBrushEnabled: engine.canInteractWithActiveLayer,
            isPixelEraserEnabled: engine.canInteractWithActiveLayer,
            isLassoEnabled: engine.canInteractWithActiveLayer,
            canDeselectSelection: engine.state.selectedStrokeIDs.isEmpty == false
        )
    )
}

private var selectedStrokeBounds: CGRect? {
    guard engine.state.document.activeLayer?.isVisible != false else {
        return nil
    }
    return HandDrawingStrokeGeometry.unionBounds(
        forStrokeIDs: engine.state.selectedStrokeIDs,
        in: engine.state.document.activeLayerStrokes
    )
}
```

## 修改三：iPad 编辑器壳新增 `Layers` 顶栏按钮、弹出面板和重命名弹窗

### 修改前

- `iOSHandDrawingEditorViewController` 顶栏只有 `Close` 和 `Done`。
- 视图层级只有标题、提示、palette 和画布，没有 layer panel 容器。
- `Coordinator` 的 layer 语义没有绑定到任何 iPad UI 入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: iOSHandDrawingEditorViewController.setupViewHierarchy() / configureCoordinator()
// 功能注释: 修改前编辑器壳没有 layer 按钮和 layer 面板，也没有接收 layer panel 状态回调。
private let closeButton: UIButton = { /* ... */ }()
private let doneButton: UIButton = { /* ... */ }()
private let paletteView = HandDrawingToolPaletteView()
private let surfaceView = HandDrawingCanvasSurfaceView()

private func configureCoordinator() {
    coordinator.onSurfaceStateChange = { [weak self] state in
        self?.surfaceView.apply(state: state)
    }
    coordinator.onPaletteStateChange = { [weak self] state in
        self?.paletteView.apply(state: state)
    }
}

private func setupViewHierarchy() {
    view.addSubview(titleLabel)
    view.addSubview(hintLabel)
    view.addSubview(closeButton)
    view.addSubview(doneButton)
    view.addSubview(paletteView)
    view.addSubview(surfaceView)
}
```

### 修改后

- 顶栏新增 `layersButton`。
- 新增 `layerPanelBackdropView` 和 `layerPanelView`，使用浮层方式展示而不是把 palette 挤满。
- `configureCoordinator()` 开始接收 `onLayerPanelStateChange`。
- `configureLayerPanelView()` 把面板所有事件都回传给 `Coordinator`。
- 新增：
  - `handleLayersButtonTap()`
  - `handleLayerPanelBackdropTap()`
  - `applyLayerPanelState(_:)`
  - `updateLayerButtonConfiguration()`
  - `updateLayerPanelVisibility()`
  - `presentRenameLayerPrompt(for:)`
- `updateChromeConfiguration()` 会在结束保存态时关闭 layer panel，避免悬浮 UI 留在屏幕上。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: iOSHandDrawingEditorViewController.configureCoordinator() / configureLayerPanelView() / setupViewHierarchy()
// 功能注释: 修改后 iPad 编辑器壳接入 layer 顶栏按钮与弹出面板，并把全部 layer 操作回传给 coordinator。
private let layersButton: UIButton = {
    let button = UIButton(type: .system)
    var configuration = UIButton.Configuration.tinted()
    configuration.title = "Layers"
    configuration.image = UIImage(systemName: "square.3.layers.3d")
    button.configuration = configuration
    return button
}()
private let layerPanelBackdropView: UIControl = { /* ... */ }()
private let layerPanelView = HandDrawingLayerPanelView()
private var latestLayerPanelState: HandDrawingLayerPanelState?

private func configureCoordinator() {
    coordinator.onSurfaceStateChange = { [weak self] state in
        self?.surfaceView.apply(state: state)
    }
    coordinator.onPaletteStateChange = { [weak self] state in
        self?.paletteView.apply(state: state)
    }
    coordinator.onLayerPanelStateChange = { [weak self] state in
        self?.applyLayerPanelState(state)
    }
}

private func configureLayerPanelView() {
    layerPanelView.onAddLayer = { [weak self] in
        self?.coordinator.addLayer()
    }
    layerPanelView.onSelectLayer = { [weak self] layerID in
        self?.coordinator.selectLayer(withID: layerID)
    }
    layerPanelView.onRequestRenameLayer = { [weak self] rowState in
        self?.presentRenameLayerPrompt(for: rowState)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: iOSHandDrawingEditorViewController.handleLayersButtonTap() / updateLayerPanelVisibility() / presentRenameLayerPrompt(for:)
// 功能注释: 修改后 VC 负责 layer panel 的显隐切换和重命名弹窗展示，但不直接修改 document。
@objc
private func handleLayersButtonTap() {
    guard latestLayerPanelState != nil else {
        return
    }
    isLayerPanelVisible.toggle()
}

private func updateLayerPanelVisibility() {
    let shouldShowPanel = isLayerPanelVisible && latestLayerPanelState != nil
    layerPanelBackdropView.isHidden = shouldShowPanel == false
    layerPanelView.isHidden = shouldShowPanel == false
    layerPanelBackdropView.alpha = shouldShowPanel ? 1 : 0
    layerPanelView.alpha = shouldShowPanel ? 1 : 0
    updateLayerButtonConfiguration()
}

private func presentRenameLayerPrompt(
    for rowState: HandDrawingLayerPanelRowState
) {
    let alertController = UIAlertController(
        title: "Rename Layer",
        message: nil,
        preferredStyle: .alert
    )
    alertController.addTextField { textField in
        textField.placeholder = "Layer name"
        textField.text = rowState.name
    }
    alertController.addAction(
        UIAlertAction(title: "Save", style: .default) { [weak self, weak alertController] _ in
            guard let proposedName = alertController?.textFields?.first?.text else {
                return
            }
            self?.coordinator.renameLayer(withID: rowState.id, to: proposedName)
        }
    )
    present(alertController, animated: true)
}
```

## 修改四：新增独立的 `HandDrawingLayerPanelView`，承接最小可行图层面板展示

### 修改前

- 项目中没有专用的手绘 layer panel 视图。
- 如果把 layer 列表强塞进 `HandDrawingToolPaletteView`，会违反阶段 5 “palette 继续聚焦画笔 / 橡皮 / 套索 / 颜色 / 粗细 / undo redo”的边界。

```swift
// 文件路径: 无（阶段 5 前不存在 MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift）
// 函数名: 无
// 功能注释: 修改前不存在专门承接 layer 面板 UI 的视图，图层列表/操作按钮也没有独立渲染承载体。
// 修改前没有 HandDrawingLayerPanelView
// 修改前没有 LayerRowView
```

### 修改后

- 新增 `HandDrawingLayerPanelView.swift`。
- 面板职责：
  - 顶部标题和 `Add Layer` 按钮
  - 滚动 layer 列表
  - 每行展示当前层状态和操作按钮
- 每行支持：
  - 选中当前层
  - 切换显隐
  - 切换锁定
  - 重命名
  - 上下移动
  - 删除
- 视图只负责 `apply(state:)` 和事件回调，不直接接触 `document`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
// 函数名: HandDrawingLayerPanelView.apply(state:) / rebuildRows(with:) / handleAddButtonTap()
// 功能注释: 修改后独立 layer panel view 负责根据 LayerPanelState 渲染列表，并把用户操作回传给上层。
final class HandDrawingLayerPanelView: UIView {
    var onAddLayer: (() -> Void)?
    var onSelectLayer: ((UUID) -> Void)?
    var onRequestRenameLayer: ((HandDrawingLayerPanelRowState) -> Void)?
    var onMoveLayerUp: ((UUID) -> Void)?
    var onMoveLayerDown: ((UUID) -> Void)?
    var onToggleVisibility: ((UUID) -> Void)?
    var onToggleLock: ((UUID) -> Void)?
    var onDeleteLayer: ((UUID) -> Void)?

    func apply(state: HandDrawingLayerPanelState) {
        addButton.isEnabled = state.canAddLayer
        addButton.alpha = state.canAddLayer ? 1 : 0.5
        rebuildRows(with: state.layers)
    }

    private func rebuildRows(with rows: [HandDrawingLayerPanelRowState]) {
        rowsStackView.arrangedSubviews.forEach { arrangedSubview in
            rowsStackView.removeArrangedSubview(arrangedSubview)
            arrangedSubview.removeFromSuperview()
        }

        for rowState in rows {
            let rowView = LayerRowView()
            rowView.apply(state: rowState)
            rowView.onSelectLayer = { [weak self] layerID in
                self?.onSelectLayer?(layerID)
            }
            rowsStackView.addArrangedSubview(rowView)
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
// 函数名: LayerRowView.apply(state:)
// 功能注释: 修改后每个 layer row 会根据 active/visible/locked 状态更新按钮样式和可用性。
func apply(state: HandDrawingLayerPanelRowState) {
    self.state = state

    var selectionConfiguration = UIButton.Configuration.tinted()
    selectionConfiguration.title = state.name
    selectionConfiguration.subtitle = state.subtitle
    selectionConfiguration.image = UIImage(
        systemName: state.isActive ? "checkmark.circle.fill" : "circle"
    )
    selectionConfiguration.baseBackgroundColor = state.isActive
        ? .systemBlue
        : .tertiarySystemBackground
    selectionConfiguration.baseForegroundColor = state.isActive
        ? .white
        : .label
    selectButton.configuration = selectionConfiguration

    updateIconButton(
        visibilityButton,
        systemImageName: state.isVisible ? "eye" : "eye.slash",
        tintColor: state.isVisible ? .secondaryLabel : .systemOrange,
        isEnabled: true
    )
    updateIconButton(
        deleteButton,
        systemImageName: "trash",
        tintColor: .systemRed,
        isEnabled: state.canDelete
    )
}
```

## 修改五：`HandDrawingToolPaletteView` 不再默认放开 brush，而是显式跟随当前层可交互状态

### 修改前

- `brushButton` 永远 `isEnabled: true`。
- 即使当前活动层已被隐藏或锁定，palette 侧的 brush 视觉状态也不会体现这一点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: HandDrawingToolPaletteView.apply(state:)
// 功能注释: 修改前 brush 按钮始终可点，palette 没有显式接入 active layer 的可交互状态。
updateToolButtonSelection(
    brushButton,
    isSelected: state.selectedTool == .brush,
    isEnabled: true
)
```

### 修改后

- `HandDrawingToolPaletteState` 新增 `isBrushEnabled`。
- `Coordinator.publishPaletteState()` 使用 `engine.canInteractWithActiveLayer` 同步驱动 `brush / eraser / lasso` 的可用状态。
- `ToolPaletteView.apply(state:)` 改为按 `state.isBrushEnabled` 刷新 brush 按钮。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingToolPaletteState / HandDrawingEditorCoordinator.publishPaletteState()
// 功能注释: 修改后 palette state 显式带上 brush 的 enable 状态，并和 active layer 交互资格保持一致。
struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedLineWidth: CGFloat
    var availableColors: [HandDrawingColor]
    var availableLineWidths: [CGFloat]
    var canUndo: Bool
    var canRedo: Bool
    var isBrushEnabled: Bool
    var isPixelEraserEnabled: Bool
    var isLassoEnabled: Bool
    var canDeselectSelection: Bool
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: HandDrawingToolPaletteView.apply(state:)
// 功能注释: 修改后 brush 按钮是否可用由 coordinator 传入的 state 控制。
updateToolButtonSelection(
    brushButton,
    isSelected: state.selectedTool == .brush,
    isEnabled: state.isBrushEnabled
)
```

## 修改六：补 `HandDrawingLayerPanelStateTests`，覆盖阶段 5 的核心状态语义

### 修改前

- 阶段 5 开始前没有针对 layer panel 状态构建逻辑的测试。
- 尤其缺少以下场景的断言：
  - 顶层优先的展示顺序
  - 上下移动按钮能力
  - `Hidden / Locked / Current` 文案
  - 新增 layer 后按钮标题、副标题和删除能力

```swift
// 文件路径: 无（阶段 5 前不存在 MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift 中的 HandDrawingLayerPanelStateTests）
// 函数名: 无
// 功能注释: 修改前没有专门验证 layer panel 状态构建器的测试用例。
// 修改前不存在 HandDrawingLayerPanelStateTests
```

### 修改后

- 新增 `HandDrawingLayerPanelStateTests`。
- 重点覆盖：
  - 顶层优先排序
  - `canMoveUp / canMoveDown`
  - `Hidden / Locked / Current` 副标题
  - 插入新 layer 后的 `buttonTitle / buttonSubtitle / canDelete`
- 测试文件名仍为 `HandDrawingEditorCoordinatorTests.swift`，但测试类名已经改成 `HandDrawingLayerPanelStateTests`，实际关注点是共享状态构建器，而不是 iOS `UIViewController` 层级。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
// 函数名: HandDrawingLayerPanelStateTests.testLayerPanelStateBuilderUsesTopFirstOrderingAndMoveCapabilities() / testLayerPanelStateBuilderReflectsHiddenLockedAndInsertedLayerState()
// 功能注释: 修改后测试覆盖 layer panel 的顺序、按钮可用态、状态文案和新增 layer 场景。
final class HandDrawingLayerPanelStateTests: XCTestCase {
    func testLayerPanelStateBuilderUsesTopFirstOrderingAndMoveCapabilities() {
        let initialPanelState = HandDrawingLayerPanelStateBuilder.makeState(
            from: document
        )
        XCTAssertEqual(initialPanelState.layers.map(\.name), ["Detail", "Base"])
        XCTAssertFalse(initialPanelState.layers[0].canMoveUp)
        XCTAssertTrue(initialPanelState.layers[0].canMoveDown)
    }

    func testLayerPanelStateBuilderReflectsHiddenLockedAndInsertedLayerState() {
        let hiddenLayerState = HandDrawingLayerPanelStateBuilder
            .makeState(from: document)
            .layers[0]
        XCTAssertEqual(hiddenLayerState.subtitle, "Current · Hidden")

        let insertedLayerState = HandDrawingLayerPanelStateBuilder.makeState(
            from: document
        )
        XCTAssertEqual(insertedLayerState.buttonTitle, "Layers (2)")
    }
}
```

## 结果小结

- 阶段 5 已把 iPad 手绘编辑器的最小可行 layer UI 串起来：
  - 顶栏 `Layers` 按钮
  - 弹出 layer 管理面板
  - 新建 / 删除 / 重命名 / 上下移动 / 显隐 / 锁定 / 切换当前层
- layer 业务没有散落到 `VC`：
  - 状态由 `HandDrawingLayerPanelStateBuilder` 和 `HandDrawingEditorCoordinator` 统一产出
  - `VC` 只负责展示与弹窗承接
- palette 和选区显示也同步接入了 active layer 的可交互 / 可见状态，避免 UI 表达与文档状态脱节。
