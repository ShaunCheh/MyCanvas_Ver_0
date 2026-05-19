# 20260519_095156_CST_hand_drawing_layer_panel_list_visibility_fix_record

## 记录范围

- 记录内容：
  1. 修复 iPad 手绘编辑器里 `Layers` 面板只显示标题和 `Add Layer`，不显示实际 layer 列表的问题。
  2. 改动集中在 `HandDrawingLayerPanelView` 的布局约束与列表高度计算，不涉及 document / engine / coordinator 的 layer 数据生成逻辑。
- 时间戳来源：
  - `date '+%Y%m%d_%H%M%S_CST'` -> `20260519_095156_CST`
- 参考依据：
  - `git status --short`
  - `git diff -- MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift`
  - 当前文件内容：`MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift`
  - 状态生成参考：`MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLayerPanelState.swift`
- 当前 changes 摘要：
  - `M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift`
  - `M MyCanvas_Ver_0.xcodeproj/project.xcworkspace/xcuserdata/shaun.xcuserdatad/UserInterfaceState.xcuserstate`
    - 这是 IDE 会话状态文件，不属于本次修复的业务代码改动，本记录不展开。
- 验证结果：
  - `ReadLints`
    - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift` 未引入新的 linter 问题。
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=iOS Simulator,id=D71F3801-D496-43A0-BE46-CACF8B2D0322'`
    - 通过

## 问题现象

- 右上角 `Layers` 按钮能显示 `Layers (2)` 与当前激活层名，说明 layer 状态已经到达 UI。
- 但展开后的浮层面板里只显示标题 `Layers` 和 `Add Layer` 按钮，没有实际的 layer row。
- 因此问题不是“layer 数据没有加载”，而是“layer row 没有被布局显示出来”。

## 定位结论

- `HandDrawingLayerPanelStateBuilder` 本来就会把 `document.layers` 映射成面板 rows。
- 这部分代码未修改，本次只作为定位依据：状态层已经准备好了列表数据。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingLayerPanelState.swift
// 函数名: HandDrawingLayerPanelStateBuilder.makeState(from:)
// 功能注释: 这段代码没有在本次修复中改动；它说明 layer 面板的数据源本来就会生成 layers 数组，问题不在状态层。
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

## 根因

- `HandDrawingLayerPanelView` 内部用 `UIScrollView` 承载 layer rows。
- 修改前，这个 `scrollView` 只有一个 `height <= 320` 的上限约束，没有任何由内容驱动的显式高度。
- `UIScrollView` 本身没有 intrinsic height，因此在当前布局关系下，Auto Layout 可以合法地把它压成 `0` 高。
- 结果就是：
  - header 区域可见；
  - `rowsStackView` 虽然已经被 `rebuildRows(with:)` 填充，但所属 `scrollView` 高度为 `0`，导致 layer 列表不可见。

## 修改一：把列表区从“最大高度约束”改成“内容驱动的显式高度”

### 修改前

- `apply(state:)` 只重建 rows，不会更新列表高度。
- `setupConstraints()` 只给 `scrollView` 设了一个 `lessThanOrEqualToConstant` 上限。
- 一旦外层布局没有额外高度信息，`scrollView` 就可能塌成 `0`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
// 函数名: HandDrawingLayerPanelView.apply(state:) / setupConstraints()
// 功能注释: 修改前 layer panel 只负责把 rows 填进 scroll view，但没有显式把 rows 内容高度反馈给 scroll view 自身。
func apply(state: HandDrawingLayerPanelState) {
    addButton.isEnabled = state.canAddLayer
    addButton.alpha = state.canAddLayer ? 1 : 0.5
    rebuildRows(with: state.layers)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        rootStackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.panelInset),
        rootStackView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Layout.panelInset
        ),
        rootStackView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Layout.panelInset
        ),
        scrollView.topAnchor.constraint(
            equalTo: rootStackView.bottomAnchor,
            constant: Layout.sectionSpacing
        ),
        scrollView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Layout.panelInset
        ),
        scrollView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Layout.panelInset
        ),
        scrollView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Layout.panelInset
        ),
        scrollView.heightAnchor.constraint(
            lessThanOrEqualToConstant: Layout.maxListHeight
        )
    ])
}
```

### 修改后

- 新增 `scrollViewHeightConstraint`，显式持有列表区高度约束。
- `apply(state:)` 在重建 rows 后立即调用 `updateListHeight()`。
- 新增 `layoutSubviews()`，在 panel 宽度稳定后再次重算高度，避免首次布局时 `scrollView.bounds.width` 还没就绪。
- 新增 `updateListHeight()`：
  - 通过 `rowsStackView.systemLayoutSizeFitting(...)` 计算实际内容高度；
  - 把 `scrollView` 高度设置为 `min(measuredHeight, maxListHeight)`；
  - 列表少时按内容撑开，列表多时上限为 `320` 并交给 `scrollView` 滚动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
// 函数名: HandDrawingLayerPanelView.apply(state:) / layoutSubviews() / setupConstraints() / updateListHeight()
// 功能注释: 修改后 layer panel 用 rows 的实际布局高度驱动 scroll view，避免 layer 列表区域被压成 0 高。
private var scrollViewHeightConstraint: NSLayoutConstraint?

func apply(state: HandDrawingLayerPanelState) {
    addButton.isEnabled = state.canAddLayer
    addButton.alpha = state.canAddLayer ? 1 : 0.5
    rebuildRows(with: state.layers)
    updateListHeight()
}

override func layoutSubviews() {
    super.layoutSubviews()
    updateListHeight()
}

private func setupConstraints() {
    let scrollViewHeightConstraint = scrollView.heightAnchor.constraint(equalToConstant: 0)
    self.scrollViewHeightConstraint = scrollViewHeightConstraint
    NSLayoutConstraint.activate([
        rootStackView.topAnchor.constraint(equalTo: topAnchor, constant: Layout.panelInset),
        rootStackView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Layout.panelInset
        ),
        rootStackView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Layout.panelInset
        ),
        scrollView.topAnchor.constraint(
            equalTo: rootStackView.bottomAnchor,
            constant: Layout.sectionSpacing
        ),
        scrollView.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: Layout.panelInset
        ),
        scrollView.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -Layout.panelInset
        ),
        scrollView.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -Layout.panelInset
        ),
        scrollViewHeightConstraint
    ])
}

private func updateListHeight() {
    guard let scrollViewHeightConstraint else {
        return
    }

    let availableWidth = max(
        scrollView.bounds.width,
        bounds.width - Layout.panelInset * 2
    )
    guard availableWidth > 0 else {
        return
    }

    // UIScrollView 没有 intrinsic height；显式用 rows 内容高度驱动它，避免面板把列表压成 0 高。
    let measuredHeight = rowsStackView.systemLayoutSizeFitting(
        CGSize(
            width: availableWidth,
            height: UIView.layoutFittingCompressedSize.height
        ),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
    ).height
    scrollViewHeightConstraint.constant = min(
        Layout.maxListHeight,
        ceil(measuredHeight)
    )
}
```

## 修改二：提高面板自身的垂直抗压缩能力，防止外层继续把列表区挤扁

### 修改前

- `HandDrawingLayerPanelView` 本身没有显式声明垂直方向的 hugging / compression resistance 优先级。
- 外层浮层布局在收缩时，panel 更容易把列表区继续压缩。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
// 函数名: HandDrawingLayerPanelView.init(frame:)
// 功能注释: 修改前 panel 只配置背景、圆角和边框，没有声明垂直方向上更强的抗压缩行为。
override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .secondarySystemGroupedBackground
    layer.cornerRadius = Layout.cornerRadius
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
    setupViewHierarchy()
    setupConstraints()
    bindActions()
}
```

### 修改后

- 在初始化时显式设置：
  - `setContentHuggingPriority(.required, for: .vertical)`
  - `setContentCompressionResistancePriority(.required, for: .vertical)`
- 这样当内部列表已经有了明确高度时，外层布局不会轻易继续把 panel 压扁。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift
// 函数名: HandDrawingLayerPanelView.init(frame:)
// 功能注释: 修改后 panel 在垂直方向上提高 hugging / compression resistance，和内容驱动高度一起保证列表可见。
override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false
    backgroundColor = .secondarySystemGroupedBackground
    layer.cornerRadius = Layout.cornerRadius
    layer.cornerCurve = .continuous
    layer.borderWidth = 1
    layer.borderColor = UIColor.separator.withAlphaComponent(0.18).cgColor
    setContentHuggingPriority(.required, for: .vertical)
    setContentCompressionResistancePriority(.required, for: .vertical)
    setupViewHierarchy()
    setupConstraints()
    bindActions()
}
```

## 修改结果

- `Layers` 按钮保持原有摘要职责：显示 layer 数量和当前层名。
- 展开的 layer panel 现在会根据 `rowsStackView` 的实际内容高度显示 layer 列表。
- 当 layer 数量较少时，面板会按内容自然撑开；当 layer 数量过多时，列表区高度封顶在 `320`，并通过 `scrollView` 滚动查看其余层。
