# 20260522_110248_CST_hand_drawing_brush_engine_phase4_ui_preset_record

## 记录范围

- 记录内容：
  - 实施手绘笔刷引擎方案一的 `phase 4`，把编辑器里的“颜色 + 粗细”入口升级为“颜色 + 完整 `BrushPreset` / `BrushStyle` 模板”构造链路。
  - 让 `HandDrawingEditorCoordinator` 不再只维护 `selectedLineWidth`，而是维护 `availableBrushPresets + selectedBrushPresetID`，并在 reopen 现有文档时根据已有 `stroke.brush` 反推选中的 preset。
  - 保持现有 UI 结构不变，仍沿用原本那组宽度按钮作为第一版 preset 入口，但按钮背后承载完整 dynamics 参数，而不是只传一个线宽。
  - 补齐 preset catalog 与 coordinator reopen 语义的回归测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_110248_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次 `phase 4` 相关文件执行 `git diff --stat -- ...`，结果为：`6 files changed, 540 insertions(+), 40 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示 6 个已跟踪修改文件，均属于本次 `phase 4` 变更。
  - 当前工作区还存在 `/.cursor/plans/手绘笔刷引擎_b7888ee9.plan.md` 的现有修改，但该 `.md` 文件不属于本次 phase 4 代码产物，因此不纳入本记录正文。
- 本记录不包含：
  - `phase 3` 的 tilt-aware stamp / rasterizer / geometry 收口。
  - `phase 5` 的 codec、migration、旧稿兼容收口。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统 date 命令生成本次 phase 4 markdown 记录文件的时间戳前缀。
20260522_110248_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
# 功能说明: 汇总本次 phase 4 相关已跟踪文件的 diff 统计。
.../HandDrawing/Core/HandDrawingDocument.swift     | 219 +++++++++++++++++++++
.../HandDrawingEditorCoordinator.swift             |  63 ++++--
.../UI/HandDrawingToolPaletteView.swift            |  38 ++--
.../iOSHandDrawingEditorViewController.swift       |   4 +-
.../HandDrawingBrushDynamicsTests.swift            |  99 ++++++++++
.../HandDrawingEditorCoordinatorTests.swift        | 157 +++++++++++++++
6 files changed, 540 insertions(+), 40 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
# 功能说明: 记录本次 phase 4 相关文件的当前 changes 状态。
M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
M MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
M MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
```

## 当前 changes 摘要

- `HandDrawingDocument.swift` 里新增了 `HandDrawingBrushPreset`、`HandDrawingBrushPresetCatalog` 和 `HandDrawingBrushStyle` 的 preset 辅助能力，把“完整笔刷模板”正式建模出来。
- `HandDrawingEditorCoordinator.swift` 由 “`selectedColor + selectedLineWidth`” 升级为 “`selectedColor + selectedBrushPresetID + availableBrushPresets`”，并在初始化时根据最后一笔 `stroke.brush` 恢复 preset 语义。
- `HandDrawingToolPaletteView.swift` 保留原本按钮布局，但把“线宽按钮”改为“preset 按钮”；按钮标题仍然显示宽度值，因此 UI 视觉不需要在 phase 4 重做。
- `iOSHandDrawingEditorViewController.swift` 的 palette 回调改为转发 `presetID`。
- `HandDrawingBrushDynamicsTests.swift` 新增 preset catalog 行为测试。
- `HandDrawingEditorCoordinatorTests.swift` 新增 coordinator 的提交与 reopen 回归测试，锁定完整 brush style 不会在 reopen 后退化成默认模板。

## 修改一：在手绘核心类型里引入 `BrushPreset`

### 修改前

- `HandDrawingBrushStyle` 已经能保存 pressure / tilt 参数，但编辑器层没有“preset”抽象。
- 结果是 UI 和 coordinator 只能围绕 `baseSize` 这种单值状态工作，无法把“完整模板”作为一等对象传递。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift（修改前）
// 函数名: HandDrawingBrushStyle.defaultPen / HandDrawingBrushStyle.init(...)
// 功能说明: 修改前只有 BrushStyle 自身，没有 BrushPreset / Catalog 这类供编辑器与 reopen 复用的模板抽象。
static let defaultPen = HandDrawingBrushStyle(
    kind: .pen,
    color: .black,
    baseSize: 6,
    opacity: 1
)

var kind: Kind
var color: HandDrawingColor
var baseSize: Double
var opacity: Double
var pressureCurveExponent: Double?
var minSizeRatio: Double?
var maxSizeRatio: Double?
var tiltSizeInfluence: Double?
var tiltOpacityInfluence: Double?
```

### 修改后

- 新增 `HandDrawingBrushPreset`，把 `id`、`title`、`brushTemplate` 聚合到一起。
- 新增 `HandDrawingBrushPresetCatalog.defaultPenPresets(...)`，把现有默认线宽数组升级为 preset 列表。
- 新增 `resolveSelection(for:presets:)`，在 reopen 时把已有 `stroke.brush` 解析成：
  - 命中默认 preset
  - 同宽 custom dynamics 覆盖默认 preset
  - 非预设宽度插入 custom preset
- `HandDrawingBrushStyle` 新增 `withColor(_:)` 和 `hasEquivalentPresetSemantics(as:)`，用于“模板保持不变，只覆盖颜色”和“忽略颜色比对刷语义”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingBrushPreset / HandDrawingBrushPresetCatalog.resolveSelection(for:presets:) / HandDrawingBrushStyle.withColor(_:)
// 功能说明: 修改后 hand drawing 核心层正式提供可恢复、可匹配、可生成完整 BrushStyle 的 preset 抽象，供 UI 与 reopen 复用。
struct HandDrawingBrushPreset: Equatable {
    let id: String
    let title: String
    let brushTemplate: HandDrawingBrushStyle

    init(
        id: String,
        title: String,
        brushTemplate: HandDrawingBrushStyle
    ) {
        self.id = id
        self.title = title
        self.brushTemplate = brushTemplate.withColor(.black)
    }

    var displayLineWidth: CGFloat {
        CGFloat(brushTemplate.baseSize)
    }

    func makeBrushStyle(color: HandDrawingColor) -> HandDrawingBrushStyle {
        brushTemplate.withColor(color)
    }
}

enum HandDrawingBrushPresetCatalog {
    static func defaultPenPresets(
        lineWidths: [CGFloat],
        tiltSizeInfluence: Double?,
        tiltOpacityInfluence: Double?
    ) -> [HandDrawingBrushPreset] {
        lineWidths.map { lineWidth in
            let title = self.title(for: lineWidth)
            return .pen(
                id: "pen-\(title)",
                title: title,
                baseSize: Double(lineWidth),
                tiltSizeInfluence: tiltSizeInfluence,
                tiltOpacityInfluence: tiltOpacityInfluence
            )
        }
    }

    static func resolveSelection(
        for brush: HandDrawingBrushStyle,
        presets: [HandDrawingBrushPreset]
    ) -> HandDrawingBrushPresetSelection {
        // ... 命中默认 preset / 同宽 custom preset / 非预设宽度插入 custom preset ...
    }
}

extension HandDrawingBrushStyle {
    func withColor(_ color: HandDrawingColor) -> HandDrawingBrushStyle {
        HandDrawingBrushStyle(
            kind: kind,
            color: color,
            baseSize: baseSize,
            opacity: opacity,
            pressureCurveExponent: pressureCurveExponent,
            minSizeRatio: minSizeRatio,
            maxSizeRatio: maxSizeRatio,
            tiltSizeInfluence: tiltSizeInfluence,
            tiltOpacityInfluence: tiltOpacityInfluence
        )
    }
}
```

## 修改二：`HandDrawingEditorCoordinator` 从线宽会话态升级为 preset 会话态

### 修改前

- `HandDrawingToolPaletteState` 暴露的是 `selectedLineWidth + availableLineWidths`。
- `HandDrawingEditorCoordinator` 内部也只存 `selectedLineWidth`。
- `currentBrushStyle` 每次都用 `selectedLineWidth` 临时构造一个 `HandDrawingBrushStyle`，这让 reopen 旧文档时无法完整恢复自定义 dynamics。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: HandDrawingToolPaletteState / selectLineWidth(_:) / currentBrushStyle / publishPaletteState()
// 功能说明: 修改前 coordinator 只维护 lineWidth，会话态里没有 preset 概念，提交时只能按当前线宽临时拼 BrushStyle。
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

func selectLineWidth(_ lineWidth: CGFloat) {
    selectedLineWidth = lineWidth
    publishPaletteState()
}

private var currentBrushStyle: HandDrawingBrushStyle {
    HandDrawingBrushStyle(
        kind: .pen,
        color: selectedColor,
        baseSize: Double(selectedLineWidth),
        opacity: 1,
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )
}

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
```

### 修改后

- `HandDrawingToolPaletteState` 改为 `selectedBrushPresetID + availableBrushPresets`。
- coordinator 初始化时会：
  - 读取最后一笔 `stroke.brush`
  - 调用 `HandDrawingBrushPresetCatalog.resolveSelection(...)`
  - 恢复 `selectedColor`、`availableBrushPresets`、`selectedBrushPresetID`
- `selectBrushPreset(_:)` 替代 `selectLineWidth(_:)`。
- `currentBrushStyle` 改为从 `selectedBrushPreset.makeBrushStyle(color:)` 直接生成完整 brush。
- pixel eraser 仍只需要 `baseSize`，因此单独通过 `selectedBrushBaseSize` 读取 preset 展示宽度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingToolPaletteState / init(editorContext:) / selectBrushPreset(_:) / currentBrushStyle / publishPaletteState() / selectedBrushPreset
// 功能说明: 修改后 coordinator 的会话态不再是裸线宽，而是完整 preset 选择；reopen 时也会按已有 brush 恢复 preset 语义。
struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedBrushPresetID: String
    var availableColors: [HandDrawingColor]
    var availableBrushPresets: [HandDrawingBrushPreset]
    var canUndo: Bool
    var canRedo: Bool
    var isBrushEnabled: Bool
    var isPixelEraserEnabled: Bool
    var isLassoEnabled: Bool
    var canDeselectSelection: Bool
}

static let defaultBrushPresets: [HandDrawingBrushPreset] =
    HandDrawingBrushPresetCatalog.defaultPenPresets(
        lineWidths: defaultLineWidths,
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )

let initialBrush = document.strokes.last?.brush
    ?? Self.defaultBrushPresets.first?.makeBrushStyle(color: .black)
    ?? .defaultPen
let initialPresetSelection = HandDrawingBrushPresetCatalog.resolveSelection(
    for: initialBrush,
    presets: Self.defaultBrushPresets
)
selectedColor = initialBrush.color
availableBrushPresets = initialPresetSelection.availablePresets
selectedBrushPresetID = initialPresetSelection.selectedPresetID

func selectBrushPreset(_ presetID: String) {
    guard availableBrushPresets.contains(where: { $0.id == presetID }) else {
        return
    }
    selectedBrushPresetID = presetID
    publishPaletteState()
}

private var currentBrushStyle: HandDrawingBrushStyle {
    selectedBrushPreset.makeBrushStyle(color: selectedColor)
}

private func publishPaletteState() {
    onPaletteStateChange?(
        HandDrawingToolPaletteState(
            selectedTool: selectedTool,
            selectedColor: selectedColor,
            selectedBrushPresetID: selectedBrushPresetID,
            availableColors: Self.defaultColors,
            availableBrushPresets: availableBrushPresets,
            canUndo: engine.canUndo,
            canRedo: engine.canRedo,
            isBrushEnabled: engine.canInteractWithActiveLayer,
            isPixelEraserEnabled: engine.canInteractWithActiveLayer,
            isLassoEnabled: engine.canInteractWithActiveLayer,
            canDeselectSelection: engine.state.selectedStrokeIDs.isEmpty == false
        )
    )
}

private var selectedBrushPreset: HandDrawingBrushPreset {
    if let matchedPreset = availableBrushPresets.first(where: {
        $0.id == selectedBrushPresetID
    }) {
        return matchedPreset
    }
    return availableBrushPresets[0]
}
```

## 修改三：`HandDrawingToolPaletteView` 保持原有 UI 结构，但按钮语义切到 preset

### 修改前

- palette view 内部维护的是 `lineWidthStackView`、`lineWidthButtons`、`currentLineWidths`。
- `apply(state:)` 用 `state.selectedLineWidth` 决定哪个按钮高亮。
- `rebuildLineWidthButtonsIfNeeded(...)` 创建按钮时直接回调 `onSelectLineWidth?(lineWidth)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift（修改前）
// 函数名: onSelectLineWidth / apply(state:) / rebuildLineWidthButtonsIfNeeded(lineWidths:)
// 功能说明: 修改前 palette 里的第二行按钮只表达 lineWidth，没有 preset ID 和完整 brush template 语义。
var onSelectTool: ((HandDrawingEditorTool) -> Void)?
var onSelectColor: ((HandDrawingColor) -> Void)?
var onSelectLineWidth: ((CGFloat) -> Void)?
var onUndo: (() -> Void)?
var onRedo: (() -> Void)?
var onDeselectSelection: (() -> Void)?

private let lineWidthStackView = HandDrawingToolPaletteView.makeHorizontalStack()
private var lineWidthButtons: [UIButton] = []
private var currentLineWidths: [CGFloat] = []

func apply(state: HandDrawingToolPaletteState) {
    rebuildColorButtonsIfNeeded(colors: state.availableColors)
    rebuildLineWidthButtonsIfNeeded(lineWidths: state.availableLineWidths)
    // ...
    for (index, button) in lineWidthButtons.enumerated() {
        guard currentLineWidths.indices.contains(index) else {
            continue
        }
        button.isSelected = currentLineWidths[index] == state.selectedLineWidth
        button.configurationUpdateHandler?(button)
    }
}

private func rebuildLineWidthButtonsIfNeeded(lineWidths: [CGFloat]) {
    guard lineWidths != currentLineWidths else {
        return
    }
    currentLineWidths = lineWidths
    lineWidthButtons = lineWidths.map { lineWidth in
        let button = Self.makeActionButton(title: "\(Int(lineWidth.rounded()))")
        button.addAction(
            UIAction { [weak self] _ in
                self?.onSelectLineWidth?(lineWidth)
            },
            for: .touchUpInside
        )
        lineWidthStackView.addArrangedSubview(button)
        return button
    }
}
```

### 修改后

- 第二行按钮仍然存在，但对应的数据源切成 `brushPresetStackView`、`brushPresetButtons`、`currentBrushPresets`。
- `apply(state:)` 使用 `state.selectedBrushPresetID` 决定高亮状态。
- `rebuildBrushPresetButtonsIfNeeded(...)` 用 `preset.title` 做按钮标题，但真正传回的是 `preset.id`。
- 这保证 phase 4 不用重做 UI 布局，也能把底层语义升级到完整 preset。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: onSelectBrushPreset / apply(state:) / rebuildBrushPresetButtonsIfNeeded(presets:)
// 功能说明: 修改后 palette 保留同一套按钮布局，但按钮背后已经绑定到完整 preset，而不是仅仅绑定 lineWidth。
var onSelectTool: ((HandDrawingEditorTool) -> Void)?
var onSelectColor: ((HandDrawingColor) -> Void)?
var onSelectBrushPreset: ((String) -> Void)?
var onUndo: (() -> Void)?
var onRedo: (() -> Void)?
var onDeselectSelection: (() -> Void)?

private let brushPresetStackView = HandDrawingToolPaletteView.makeHorizontalStack()
private var brushPresetButtons: [UIButton] = []
private var currentBrushPresets: [HandDrawingBrushPreset] = []

func apply(state: HandDrawingToolPaletteState) {
    rebuildColorButtonsIfNeeded(colors: state.availableColors)
    rebuildBrushPresetButtonsIfNeeded(presets: state.availableBrushPresets)
    // ...
    for (index, button) in brushPresetButtons.enumerated() {
        guard currentBrushPresets.indices.contains(index) else {
            continue
        }
        button.isSelected = currentBrushPresets[index].id == state.selectedBrushPresetID
        button.configurationUpdateHandler?(button)
    }
}

private func rebuildBrushPresetButtonsIfNeeded(
    presets: [HandDrawingBrushPreset]
) {
    guard presets != currentBrushPresets else {
        return
    }
    currentBrushPresets = presets
    brushPresetButtons = presets.map { preset in
        let button = Self.makeActionButton(title: preset.title)
        button.addAction(
            UIAction { [weak self] _ in
                self?.onSelectBrushPreset?(preset.id)
            },
            for: .touchUpInside
        )
        brushPresetStackView.addArrangedSubview(button)
        return button
    }
}
```

## 修改四：`iOSHandDrawingEditorViewController` 把 palette 回调接到 preset 选择

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift（修改前）
// 函数名: configurePaletteView()
// 功能说明: 修改前 view controller 只把 palette 的线宽点击事件转发给 coordinator.selectLineWidth(_:)。
private func configurePaletteView() {
    paletteView.onSelectTool = { [weak self] tool in
        self?.coordinator.selectTool(tool)
    }
    paletteView.onSelectColor = { [weak self] color in
        self?.coordinator.selectColor(color)
    }
    paletteView.onSelectLineWidth = { [weak self] lineWidth in
        self?.coordinator.selectLineWidth(lineWidth)
    }
    // ...
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: configurePaletteView()
// 功能说明: 修改后 view controller 将 palette 的 preset 选择事件转发给 coordinator.selectBrushPreset(_:)。
private func configurePaletteView() {
    paletteView.onSelectTool = { [weak self] tool in
        self?.coordinator.selectTool(tool)
    }
    paletteView.onSelectColor = { [weak self] color in
        self?.coordinator.selectColor(color)
    }
    paletteView.onSelectBrushPreset = { [weak self] presetID in
        self?.coordinator.selectBrushPreset(presetID)
    }
    // ...
}
```

## 修改五：补齐 preset catalog 与 coordinator reopen 语义回归测试

### 修改前

- `HandDrawingBrushDynamicsTests.swift` 只覆盖到 tilt-aware dynamics，没有 preset catalog 测试。
- `HandDrawingEditorCoordinatorTests.swift` 只包含 layer panel 状态测试，没有 coordinator 的 preset 提交 / reopen 回归。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift（修改前）
// 函数名: testHandDrawingBrushDynamicsRotatedTiltedStampBoundsCoverAxisAlignedExtent()
// 功能说明: 修改前测试文件停留在 brush dynamics / tilt stamp 范围，还没有 preset catalog 的行为回归。
func testHandDrawingBrushDynamicsRotatedTiltedStampBoundsCoverAxisAlignedExtent() throws {
    let stroke = makeHandDrawingTestStroke(
        baseSize: 20,
        samplePoints: [CGPoint(x: 60, y: 60)],
        sampleForces: [0.5],
        sampleAzimuths: [.pi / 4],
        sampleAltitudes: [0],
        tiltSizeInfluence: 1
    )
    // ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift（修改前）
// 函数名: HandDrawingLayerPanelStateTests
// 功能说明: 修改前 coordinator 测试文件里只有 layer panel 相关测试，没有 iOS preset 提交与 reopen 语义校验。
final class HandDrawingLayerPanelStateTests: XCTestCase {
    func testLayerPanelStateBuilderUsesTopFirstOrderingAndMoveCapabilities() {
        // ...
    }

    func testLayerPanelStateBuilderReflectsHiddenLockedAndInsertedLayerState() {
        // ...
    }
}
```

### 修改后

- `HandDrawingBrushDynamicsTests.swift` 新增 3 个 preset catalog 回归：
  - 默认 preset 命中与完整 `BrushStyle` 生成
  - 同宽 custom dynamics 恢复
  - 非预设宽度插入排序
- `HandDrawingEditorCoordinatorTests.swift` 新增 `HandDrawingEditorCoordinatorBrushPresetTests`：
  - 锁定“选中 preset 后提交到文档”的刷子参数正确性
  - 锁定“reopen 旧 brush 后继续画”的刷子模板不会被默认 preset 覆盖

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
// 函数名: testHandDrawingBrushPresetCatalogResolvesDefaultPresetAndBuildsFullBrushStyle() / testHandDrawingBrushPresetCatalogPreservesDocumentBrushDynamicsAtMatchingWidth() / testHandDrawingBrushPresetCatalogInsertsNonPresetWidthInSortedOrder()
// 功能说明: 修改后测试锁定 preset catalog 的三条核心语义：默认命中、同宽 custom dynamics 保留、非预设宽度插入。
func testHandDrawingBrushPresetCatalogResolvesDefaultPresetAndBuildsFullBrushStyle() throws {
    let presets = HandDrawingBrushPresetCatalog.defaultPenPresets(
        lineWidths: [4, 8, 12, 18],
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )
    let selectedColor = HandDrawingColor(
        red: 0.18,
        green: 0.46,
        blue: 0.81,
        alpha: 1
    )
    let selectedBrush = presets[2].makeBrushStyle(color: selectedColor)
    let selection = HandDrawingBrushPresetCatalog.resolveSelection(
        for: selectedBrush,
        presets: presets
    )
    // ...
}

func testHandDrawingBrushPresetCatalogPreservesDocumentBrushDynamicsAtMatchingWidth() throws {
    let reopenedBrush = HandDrawingBrushStyle(
        kind: .pen,
        color: HandDrawingColor(red: 0.73, green: 0.22, blue: 0.4, alpha: 1),
        baseSize: 8,
        opacity: 0.76,
        pressureCurveExponent: 1.7,
        minSizeRatio: 0.18,
        maxSizeRatio: 0.94,
        tiltSizeInfluence: 0.42,
        tiltOpacityInfluence: 0.16
    )
    let selection = HandDrawingBrushPresetCatalog.resolveSelection(
        for: reopenedBrush,
        presets: presets
    )
    // ...
}

func testHandDrawingBrushPresetCatalogInsertsNonPresetWidthInSortedOrder() {
    XCTAssertEqual(
        selection.availablePresets.map(\.displayLineWidth),
        [4, 8, 10, 12, 18]
    )
    XCTAssertEqual(selection.selectedPresetID, "custom-10")
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
// 函数名: HandDrawingEditorCoordinatorBrushPresetTests / makeHandDrawingEditorCoordinatorTestContext(document:)
// 功能说明: 修改后测试直接覆盖 coordinator 的提交链路与 reopen 链路，确保 phase 4 的 preset 语义真正落入 documentData。
@MainActor
final class HandDrawingEditorCoordinatorBrushPresetTests: XCTestCase {
    func testHandDrawingEditorCoordinatorCommitsSelectedBrushPresetWithFullDynamics() throws {
        let coordinator = try HandDrawingEditorCoordinator(
            editorContext: makeHandDrawingEditorCoordinatorTestContext(
                document: HandDrawingDocument(
                    paper: HandDrawingPaper(
                        id: "coordinator-preset-paper",
                        size: CGSize(width: 120, height: 120)
                    )
                )
            )
        )
        // ... 选择颜色与 preset，画一笔后提交 ...
    }

    func testHandDrawingEditorCoordinatorRestoresCustomBrushPresetFromDocument() throws {
        let customBrush = HandDrawingBrushStyle(
            kind: .pen,
            color: HandDrawingColor(red: 0.21, green: 0.35, blue: 0.82, alpha: 1),
            baseSize: 8,
            opacity: 0.72,
            pressureCurveExponent: 1.65,
            minSizeRatio: 0.18,
            maxSizeRatio: 0.91,
            tiltSizeInfluence: 0.44,
            tiltOpacityInfluence: 0.12
        )
        // ... reopen 含 custom brush 的文档，继续绘制并验证提交后的 committedStroke.brush 仍等于 customBrush ...
    }
}
```

## 验证结果

- 目标 macOS 测试通过：`HandDrawingBrushDynamicsTests`、`HandDrawingDocumentCodecTests`
- iOS Simulator App 构建通过：`MyCanvas_Ver_0` scheme
- `MyCanvas_Ver_0Tests` target 当前不支持 `com.apple.platform.iphonesimulator`，因此新增的 UIKit-only coordinator 测试本次只能完成编译接入，不能直接在 iOS Simulator 上执行
- `ReadLints` 检查本次 6 个修改文件，结果为空

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS,arch=arm64" -derivedDataPath "/tmp/MyCanvasPhase4MacTests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests
# 功能说明: 运行本次 phase 4 依赖的共享 hand drawing 核心测试，确认 preset catalog 引入后未破坏已有 dynamics / codec 语义。
Test session results, code coverage, and logs:
	/tmp/MyCanvasPhase4MacTests/Logs/Test/Test-MyCanvas_Ver_0-2026.05.22_11-00-08-+0800.xcresult

** TEST SUCCEEDED **
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322" -derivedDataPath "/tmp/MyCanvasPhase4IOSTests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorBrushPresetTests
# 功能说明: 尝试执行 UIKit-only 的 coordinator preset 回归测试；结果显示当前测试 target 不支持 iOS Simulator 平台，这是工程配置现状，不是本次 phase 4 代码编译错误。
xcodebuild: error: Failed to build project MyCanvas_Ver_0 with scheme MyCanvas_Ver_0.: Cannot test target “MyCanvas_Ver_0Tests” on “iPad (A16)”: MyCanvas_Ver_0Tests does not support iPad (A16)’s platform: com.apple.platform.iphonesimulator
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322" -derivedDataPath "/tmp/MyCanvasPhase4IOSBuild"
# 功能说明: 在 iOS Simulator 目标上验证 phase 4 改动后的 app 编译链路，确保 UIKit 侧 preset 接线完整可编译。
note: Disabling hardened runtime with ad-hoc codesigning. (in target 'MyCanvas_Ver_0' from project 'MyCanvas_Ver_0')
** BUILD SUCCEEDED **
```

## 结论

- 这次 `phase 4` 的实际落点不是新增一套笔刷渲染算法，而是把编辑器入口的“线宽选择”正式提升为“preset 选择”。
- 新画出的 `stroke.brush` 现在由完整 preset 模板生成，reopen 旧文档时也会优先保持文档里已有的 dynamics 公式，不再因为 UI 只保存线宽而被动退化。
- 当前 phase 4 记录的 6 个代码文件都仍处于未提交修改状态；本记录仅如实归档实现与验证过程，不包含提交动作。
