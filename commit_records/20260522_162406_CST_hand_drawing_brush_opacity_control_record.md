# 20260522_162406_CST_hand_drawing_brush_opacity_control_record

## 记录范围

- 记录内容：
  - 为手绘编辑器新增一个真正可用的笔刷透明度控制入口，而不是只在底层模型里保留 `opacity` 字段。
  - 把透明度接入 `palette state -> coordinator -> currentBrushStyle -> committed stroke` 这条完整链路。
  - 顺手修正一个根因问题：brush preset 的“选中语义”之前把 `opacity` 也算进去，导致仅透明度变化时，同宽度 preset 会被替换成携带新透明度的自定义模板，污染 preset 语义。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift`
- 如实说明：
  - 当前工作区还有其他与本轮任务无关的修改，本记录只按路径过滤聚焦这 6 个文件。
  - 这次不是新增一套 brush 类型，而是在现有 `HandDrawingBrushStyle.opacity` 基础上补齐 UI 与状态入口。
  - 验证时，直接在 iOS Simulator 上运行 `MyCanvas_Ver_0Tests` 的指定 case 遇到了 test target 平台不支持问题，因此本轮采用 `macOS HandDrawingBrushDynamicsTests + iOS Simulator build` 组合验证。
- 本记录不包含：
  - 任何提交操作。
  - macOS 手绘编辑器的透明度 UI 入口。
  - 笔刷透明度的独立 preset 存档模型。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST_hand_drawing_brush_opacity_control_record"
# 功能说明: 使用系统自带 date 命令生成本次“笔刷透明度入口”记录文件的时间戳前缀。
20260522_162406_CST_hand_drawing_brush_opacity_control_record
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
# 功能说明: 按路径过滤 current changes，确认本轮“笔刷透明度入口”只落在这 6 个文件上。
 M MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
 M MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
 M MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
# 功能说明: 汇总本轮透明度入口变更规模，不贴原始 diff。
.../HandDrawing/Core/HandDrawingDocument.swift     | 40 +++++++++++--
.../HandDrawingEditorCoordinator.swift             | 14 ++++-
.../UI/HandDrawingToolPaletteView.swift            | 65 +++++++++++++++++++++-
.../iOSHandDrawingEditorViewController.swift       |  3 +
.../HandDrawingBrushDynamicsTests.swift            | 33 +++++++++++
.../HandDrawingEditorCoordinatorTests.swift        | 16 +++++-
6 files changed, 163 insertions(+), 8 deletions(-)
```

## 当前 changes 摘要

- `HandDrawingToolPaletteState` 新增 `selectedBrushOpacity`，不再只管理颜色和宽度 preset。
- `HandDrawingEditorCoordinator` 新增 `selectBrushOpacity(_:)`，并让 `currentBrushStyle` 在组装 brush 时真正吃到透明度。
- `HandDrawingToolPaletteView` 新增 `Opacity` 滑条和百分比标签，`iOSHandDrawingEditorViewController` 把滑条事件接到了 coordinator。
- `HandDrawingBrushPreset.makeBrushStyle(...)` 新增透明度覆盖能力，不再只能套颜色。
- `HandDrawingBrushPreset.matches(_:)` 改为基于 `hasEquivalentPresetSelectionSemantics(as:)`，把透明度从“preset 选择语义”里剥离，避免同宽度 preset 被透明度污染。
- 新增并更新测试，覆盖：
  - 仅透明度变化时仍保持同宽 preset 选中
  - coordinator 选中透明度后提交的 stroke 真正带上新透明度

## 修改一：从根因上拆开“preset 选择语义”和“opacity 覆盖语义”

### 修改前

- `HandDrawingBrushPreset.makeBrushStyle(...)` 只能覆盖颜色，不能覆盖透明度。
- `matches(_:)` 直接使用 `hasEquivalentPresetSemantics(as:)`。
- `hasEquivalentPresetSemantics(as:)` 把 `opacity` 也算进去。
- 结果是：当 reopen 一个**线宽相同但透明度不同**的 brush 时，preset 匹配会失败，然后同宽 preset 会被替换成带新透明度的 `brushTemplate`，把透明度变化混进 preset 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift（修改前）
// 函数名: HandDrawingBrushPreset.makeBrushStyle(color:) / HandDrawingBrushPreset.matches(_:) / HandDrawingBrushStyle.hasEquivalentPresetSemantics(as:)
// 功能说明: 修改前 preset 只能覆盖颜色，且 preset 选择语义把 opacity 也算进去，导致透明度变化会污染 preset 匹配结果。
struct HandDrawingBrushPreset: Equatable {
    func makeBrushStyle(color: HandDrawingColor) -> HandDrawingBrushStyle {
        brushTemplate.withColor(color)
    }

    func matches(_ brush: HandDrawingBrushStyle) -> Bool {
        brushTemplate.hasEquivalentPresetSemantics(as: brush)
    }
}

extension HandDrawingBrushStyle {
    func hasEquivalentPresetSemantics(as other: HandDrawingBrushStyle) -> Bool {
        kind == other.kind
            && approximatelyEqual(baseSize, other.baseSize)
            && approximatelyEqual(opacity, other.opacity)
            && approximatelyEqual(
                pressureCurveExponent,
                other.pressureCurveExponent
            )
            && approximatelyEqual(minSizeRatio, other.minSizeRatio)
            && approximatelyEqual(maxSizeRatio, other.maxSizeRatio)
            && approximatelyEqual(tiltSizeInfluence, other.tiltSizeInfluence)
            && approximatelyEqual(
                tiltOpacityInfluence,
                other.tiltOpacityInfluence
            )
    }
}
```

### 修改后

- `makeBrushStyle(...)` 允许单独覆盖 `opacity`。
- 新增 `withOpacity(_:)`，把透明度覆盖收口成显式 helper。
- 新增 `hasEquivalentPresetSelectionSemantics(as:)`，只保留真正决定 preset 身份的语义。
- `hasEquivalentPresetSemantics(as:)` 继续保留“完整语义一致”判断，但现在只用于完整 brush 对比，不再用于 preset 选择。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Core/HandDrawingDocument.swift
// 函数名: HandDrawingBrushPreset.makeBrushStyle(color:opacity:) / HandDrawingBrushStyle.withOpacity(_:) / HandDrawingBrushStyle.hasEquivalentPresetSelectionSemantics(as:)
// 功能说明: 修改后把“preset 身份识别”和“透明度覆盖”拆开，避免 opacity 变化污染线宽 preset 语义。
struct HandDrawingBrushPreset: Equatable {
    func makeBrushStyle(
        color: HandDrawingColor,
        opacity: Double? = nil
    ) -> HandDrawingBrushStyle {
        let coloredBrush = brushTemplate.withColor(color)
        guard let opacity else {
            return coloredBrush
        }
        return coloredBrush.withOpacity(opacity)
    }

    func matches(_ brush: HandDrawingBrushStyle) -> Bool {
        brushTemplate.hasEquivalentPresetSelectionSemantics(as: brush)
    }
}

extension HandDrawingBrushStyle {
    func withOpacity(_ opacity: Double) -> HandDrawingBrushStyle {
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

    func hasEquivalentPresetSelectionSemantics(
        as other: HandDrawingBrushStyle
    ) -> Bool {
        kind == other.kind
            && approximatelyEqual(baseSize, other.baseSize)
            && approximatelyEqual(
                pressureCurveExponent,
                other.pressureCurveExponent
            )
            && approximatelyEqual(minSizeRatio, other.minSizeRatio)
            && approximatelyEqual(maxSizeRatio, other.maxSizeRatio)
            && approximatelyEqual(tiltSizeInfluence, other.tiltSizeInfluence)
            && approximatelyEqual(
                tiltOpacityInfluence,
                other.tiltOpacityInfluence
            )
    }
}
```

## 修改二：把透明度接进 palette state 与 coordinator 的真实 brush 组装链路

### 修改前

- `HandDrawingToolPaletteState` 没有 `selectedBrushOpacity`。
- coordinator 没有 `selectBrushOpacity(_:)`。
- `currentBrushStyle` 仅由 `selectedBrushPreset + selectedColor` 生成。
- 结果是：即使底层 `HandDrawingBrushStyle` 自带 `opacity` 字段，编辑器运行时也没有一条状态链路能让用户修改这个值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: HandDrawingToolPaletteState / selectColor(_:) / currentBrushStyle / publishPaletteState()
// 功能说明: 修改前 palette state 与 coordinator 都没有透明度状态，currentBrushStyle 只吃颜色和 preset。
struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedBrushPresetID: String
    var availableColors: [HandDrawingColor]
    var availableBrushPresets: [HandDrawingBrushPreset]
}

func selectColor(_ color: HandDrawingColor) {
    selectedColor = color
    publishPaletteState()
}

private var currentBrushStyle: HandDrawingBrushStyle {
    selectedBrushPreset.makeBrushStyle(color: selectedColor)
}
```

### 修改后

- `HandDrawingToolPaletteState` 新增 `selectedBrushOpacity`。
- coordinator 初始化时会从 `initialBrush.opacity` 恢复当前透明度。
- 新增 `selectBrushOpacity(_:)`，并在 `publishPaletteState()` 中持续发布。
- `currentBrushStyle` 组装 brush 时显式传入 `selectedBrushOpacity`，因此 realtime draft 和最终 committed stroke 都会继承这个值。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: HandDrawingToolPaletteState / selectBrushOpacity(_:) / currentBrushStyle / publishPaletteState()
// 功能说明: 修改后 palette state 与 coordinator 正式管理 selectedBrushOpacity，并把它接到当前实际使用的 brush style 上。
struct HandDrawingToolPaletteState {
    var selectedTool: HandDrawingEditorTool
    var selectedColor: HandDrawingColor
    var selectedBrushOpacity: Double
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

func selectBrushOpacity(_ opacity: Double) {
    selectedBrushOpacity = min(max(opacity, 0), 1)
    publishPaletteState()
}

private var currentBrushStyle: HandDrawingBrushStyle {
    selectedBrushPreset.makeBrushStyle(
        color: selectedColor,
        opacity: selectedBrushOpacity
    )
}

private func publishPaletteState() {
    onPaletteStateChange?(
        HandDrawingToolPaletteState(
            selectedTool: selectedTool,
            selectedColor: selectedColor,
            selectedBrushOpacity: selectedBrushOpacity,
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
```

## 修改三：新增工具栏 Opacity UI，并把事件接到 coordinator

### 修改前

- `HandDrawingToolPaletteView` 只有工具、颜色、笔刷 preset、撤销重做按钮。
- 没有 `onSelectBrushOpacity`。
- `iOSHandDrawingEditorViewController.configurePaletteView()` 也没有任何透明度回调绑定。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift（修改前）
// 函数名: setupViewHierarchy() / bindActions()
// 功能说明: 修改前工具栏没有透明度控件，也没有事件回调入口。
var onSelectTool: ((HandDrawingEditorTool) -> Void)?
var onSelectColor: ((HandDrawingColor) -> Void)?
var onSelectBrushPreset: ((String) -> Void)?

private func setupViewHierarchy() {
    addSubview(rootStackView)
    [brushButton, eraserButton, lassoButton].forEach(toolStackView.addArrangedSubview)
    [deselectButton, undoButton, redoButton].forEach(historyStackView.addArrangedSubview)
    [toolStackView, colorStackView, brushPresetStackView, historyStackView]
        .forEach(rootStackView.addArrangedSubview)
}
```

### 修改后

- `HandDrawingToolPaletteView` 新增：
  - `onSelectBrushOpacity`
  - `opacityStackView`
  - `opacityTitleLabel`
  - `opacityValueLabel`
  - `opacitySlider`
- `apply(state:)` 会同步滑条位置和百分比文本。
- `handleOpacitySliderValueChanged(_:)` 会把范围限制到 `[0, 1]` 再回传给 coordinator。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift
// 函数名: apply(state:) / setupViewHierarchy() / bindActions() / handleOpacitySliderValueChanged(_:)
// 功能说明: 修改后工具栏新增一个真正可交互的 Opacity 行，UI 状态会和 palette state 保持同步。
var onSelectBrushOpacity: ((Double) -> Void)?

private let opacityStackView = HandDrawingToolPaletteView.makeHorizontalStack()
private let opacityTitleLabel = HandDrawingToolPaletteView.makeOpacityLabel(
    text: "Opacity"
)
private let opacityValueLabel = HandDrawingToolPaletteView.makeOpacityValueLabel()
private let opacitySlider: UISlider = {
    let slider = UISlider()
    slider.minimumValue = 0
    slider.maximumValue = 1
    slider.minimumTrackTintColor = .systemBlue
    return slider
}()

func apply(state: HandDrawingToolPaletteState) {
    let resolvedOpacity = Float(min(max(state.selectedBrushOpacity, 0), 1))
    if opacitySlider.value != resolvedOpacity {
        opacitySlider.value = resolvedOpacity
    }
    opacityValueLabel.text = Self.opacityText(for: state.selectedBrushOpacity)
}

private func setupViewHierarchy() {
    addSubview(rootStackView)
    [brushButton, eraserButton, lassoButton].forEach(toolStackView.addArrangedSubview)
    [opacityTitleLabel, opacitySlider, opacityValueLabel]
        .forEach(opacityStackView.addArrangedSubview)
    [deselectButton, undoButton, redoButton].forEach(historyStackView.addArrangedSubview)
    [toolStackView, colorStackView, opacityStackView, brushPresetStackView, historyStackView]
        .forEach(rootStackView.addArrangedSubview)
}

private func bindActions() {
    opacitySlider.addTarget(
        self,
        action: #selector(handleOpacitySliderValueChanged(_:)),
        for: .valueChanged
    )
}

@objc
private func handleOpacitySliderValueChanged(_ sender: UISlider) {
    let resolvedOpacity = Double(min(max(sender.value, 0), 1))
    opacityValueLabel.text = Self.opacityText(for: resolvedOpacity)
    onSelectBrushOpacity?(resolvedOpacity)
}
```

- `iOSHandDrawingEditorViewController` 新增 palette -> coordinator 的透明度事件转发。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/iOSHandDrawingEditorViewController.swift
// 函数名: configurePaletteView()
// 功能说明: 把 palette 新增的透明度滑条事件真正转发给 coordinator，避免 UI 只改显示不改 brush state。
private func configurePaletteView() {
    paletteView.onSelectTool = { [weak self] tool in
        self?.coordinator.selectTool(tool)
    }
    paletteView.onSelectColor = { [weak self] color in
        self?.coordinator.selectColor(color)
    }
    paletteView.onSelectBrushOpacity = { [weak self] opacity in
        self?.coordinator.selectBrushOpacity(opacity)
    }
    paletteView.onSelectBrushPreset = { [weak self] presetID in
        self?.coordinator.selectBrushPreset(presetID)
    }
}
```

## 修改四：补回归测试，锁住 preset 语义与提交链路

### 修改前

- 不存在“仅透明度变化时仍应保持同宽 preset”的测试。
- coordinator 的 preset 提交测试也没有断言 `selectedBrushOpacity` 是否真进了 committed stroke。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift（修改前）
// 函数名: testHandDrawingBrushPresetCatalogResolvesDefaultPresetAndBuildsFullBrushStyle() / testHandDrawingBrushPresetCatalogPreservesDocumentBrushDynamicsAtMatchingWidth()
// 功能说明: 修改前测试覆盖了默认 preset 和 reopen brush 动态恢复，但没有锁住“仅 opacity 变化不应污染 preset 选择语义”。
// 本轮新增测试前，不存在只针对 opacity 差异的 preset 选择回归。
```

### 修改后

- 新增 `testHandDrawingBrushPresetCatalogKeepsWidthPresetSelectedWhenOnlyOpacityDiffers()`，锁住 root cause。
- 更新 coordinator 测试，让它真正调用 `selectBrushOpacity(0.37)`，并验证 palette state 与最终 committed stroke 都带着这个透明度。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests.swift
// 函数名: testHandDrawingBrushPresetCatalogKeepsWidthPresetSelectedWhenOnlyOpacityDiffers()
// 功能说明: 验证仅透明度变化时仍保持同宽 preset 选中，且不会把 availablePresets 改写成带新 opacity 的污染模板。
func testHandDrawingBrushPresetCatalogKeepsWidthPresetSelectedWhenOnlyOpacityDiffers() throws {
    let presets = HandDrawingBrushPresetCatalog.defaultPenPresets(
        lineWidths: [4, 8, 12, 18],
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )
    let reopenedBrush = HandDrawingBrushStyle(
        kind: .pen,
        color: HandDrawingColor(red: 0.73, green: 0.22, blue: 0.4, alpha: 1),
        baseSize: 8,
        opacity: 0.42,
        tiltSizeInfluence: 0.85,
        tiltOpacityInfluence: 0
    )
    let selection = HandDrawingBrushPresetCatalog.resolveSelection(
        for: reopenedBrush,
        presets: presets
    )
    let selectedPreset = try XCTUnwrap(
        selection.availablePresets.first { $0.id == selection.selectedPresetID }
    )

    XCTAssertEqual(selection.selectedPresetID, presets[1].id)
    XCTAssertEqual(selection.availablePresets, presets)
    XCTAssertEqual(
        selectedPreset.makeBrushStyle(
            color: reopenedBrush.color,
            opacity: reopenedBrush.opacity
        ),
        reopenedBrush
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorTests.swift
// 函数名: testHandDrawingEditorCoordinatorCommitsSelectedBrushPresetWithFullDynamics() / testHandDrawingEditorCoordinatorRestoresCustomBrushPresetFromDocument()
// 功能说明: 验证 coordinator 新增的透明度状态既会反映到 palette state，也会反映到最终提交的 stroke。
func testHandDrawingEditorCoordinatorCommitsSelectedBrushPresetWithFullDynamics() throws {
    var paletteState: HandDrawingToolPaletteState?
    coordinator.onPaletteStateChange = { paletteState = $0 }
    coordinator.activate()

    coordinator.selectColor(selectedColor)
    coordinator.selectBrushPreset(selectedPreset.id)
    coordinator.selectBrushOpacity(0.37)

    // ... 省略起笔、收笔样本 ...

    XCTAssertEqual(
        try XCTUnwrap(paletteState?.selectedBrushOpacity),
        0.37,
        accuracy: 0.001
    )
    XCTAssertEqual(
        committedStroke.brush,
        selectedPreset.makeBrushStyle(
            color: selectedColor,
            opacity: 0.37
        )
    )
}

func testHandDrawingEditorCoordinatorRestoresCustomBrushPresetFromDocument() throws {
    XCTAssertEqual(
        try XCTUnwrap(paletteState?.selectedBrushOpacity),
        customBrush.opacity,
        accuracy: 0.001
    )
}
```

## 验证记录

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS' -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests
# 功能说明: 运行与 brush 语义最直接相关的 macOS 单元测试，确认 opacity 入口与 preset 语义修正没有破坏现有 brush dynamics。
** TEST SUCCEEDED **

Test suite 'HandDrawingBrushDynamicsTests' started on 'My Mac - MyCanvas_Ver_0'
Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushPresetCatalogKeepsWidthPresetSelectedWhenOnlyOpacityDiffers()' passed
Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushPresetCatalogPreservesDocumentBrushDynamicsAtMatchingWidth()' passed
Test case 'HandDrawingBrushDynamicsTests.testHandDrawingBrushPresetCatalogResolvesDefaultPresetAndBuildsFullBrushStyle()' passed
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'generic/platform=iOS Simulator'
# 功能说明: 构建 iOS Simulator App，确认新增的 palette UI、view controller 绑定与 coordinator 透明度链路可以完整编译通过。
** BUILD SUCCEEDED **
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,id=AD083E5B-DDB7-4007-91EB-7160FC1E6F79' -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorCoordinatorBrushPresetTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests
# 功能说明: 如实记录本轮尝试直接跑 iOS Simulator 指定测试时遇到的平台限制，因此最终采用“macOS 单测 + iOS Simulator build”组合验证。
xcodebuild: error: Failed to build project MyCanvas_Ver_0 with scheme MyCanvas_Ver_0.: Cannot test target “MyCanvas_Ver_0Tests” on “iPad Pro 13-inch (M5)”: MyCanvas_Ver_0Tests does not support iPad Pro 13-inch (M5)’s platform: com.apple.platform.iphonesimulator
```

## 结果

- `phase 7` 之后补做的“笔刷透明度入口”已经如实记录到 `commit_records/20260522_162406_CST_hand_drawing_brush_opacity_control_record.md`。
- 本轮修改的实际结果是：
  - 手绘编辑器现在有了可见、可交互的透明度入口。
  - 透明度不再停留在底层字段，而是贯通到 palette state、coordinator 和最终提交 stroke。
  - 同宽度 preset 的选择语义不再被透明度变化污染。
