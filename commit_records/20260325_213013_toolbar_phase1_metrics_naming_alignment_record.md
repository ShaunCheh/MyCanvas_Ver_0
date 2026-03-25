# 20260325_213013_toolbar_phase1_metrics_naming_alignment_record

## 记录范围

- 记录内容：
  1. 实施 `toolbar` 平台对称收敛计划的 `Phase 1`，把影响测量结果的布局常量从 `iOS/macOS` 两端 host 中收敛到共享 `Toolbar` 层。
  2. 将 `macOS` 侧 placement scale 的命名与 `iOS` 侧对齐，减少同职责方法的命名漂移。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - `Phase 2` 及后续阶段的结构收敛

## 修改一：抽取共享 `Toolbar` 测量常量

### 修改前

- `macOSCanvasToolbarHostView` 和 `iOSCanvasToolbarHostView` 都各自维护一份 `Layout.spacing`、`Layout.horizontalInset`、`Layout.verticalInset`、`Layout.buttonEdge`。
- 两端数值虽然完全相同，但来源分散，后续如果只改一侧，`toolbar` 测量结果就会发生平台漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize() / ensureSquareSize(for:)
// 功能说明: 修改前 macOS host 在本地 Layout 中维护 spacing、inset 和 buttonEdge，并直接参与 stack 布局与内容尺寸计算。
private enum Layout {
    static let spacing: CGFloat = 12
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 12
    static let buttonEdge: CGFloat = 44
    static let cornerRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.12
    static let shadowRadius: CGFloat = 10
    static let shadowOffset = CGSize(width: 0, height: 4)
}

private let buttonsStackView: macOSCanvasChromeStackView = {
    let stackView = macOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = Layout.spacing
    return stackView
}()

func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.fittingSize
    return CanvasChromeLayoutGeometry.sanitizedSize(
        CGSize(
            width: stackSize.width + (Layout.horizontalInset * 2),
            height: stackSize.height + (Layout.verticalInset * 2)
        )
    )
}

private func ensureSquareSize(for button: NSButton) {
    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: Layout.buttonEdge)
        widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
        widthConstraint.isActive = true
    }

    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: Layout.buttonEdge)
        heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
        heightConstraint.isActive = true
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize() / ensureSquareSize(for:)
// 功能说明: 修改前 iOS host 也在本地 Layout 中重复维护同一组测量常量，和 macOS 一样存在常量来源分散的问题。
private enum Layout {
    static let spacing: CGFloat = 12
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 12
    static let buttonEdge: CGFloat = 44
    static let cornerRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.12
    static let shadowRadius: CGFloat = 10
    static let shadowOffset = CGSize(width: 0, height: 4)
}

private let buttonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = Layout.spacing
    return stackView
}()

func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.systemLayoutSizeFitting(
        UIView.layoutFittingCompressedSize
    )
    return CanvasChromeLayoutGeometry.sanitizedSize(
        CGSize(
            width: stackSize.width + (Layout.horizontalInset * 2),
            height: stackSize.height + (Layout.verticalInset * 2)
        )
    )
}

private func ensureSquareSize(for button: UIButton) {
    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: Layout.buttonEdge)
        widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
        widthConstraint.isActive = true
    }

    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: Layout.buttonEdge)
        heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
        heightConstraint.isActive = true
    }
}
```

### 修改后

- 新增共享 `CanvasToolbarChromeMetrics`，把真正影响 `toolbar` 宽高测量的常量集中到 `Platform/Shared/Toolbar`。
- `iOS/macOS` 两端 host 继续保留各自的 UI 实现，但 `spacing`、`inset`、`buttonEdge` 不再分散定义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift
// 函数名: CanvasToolbarChromeMetrics
// 功能说明: 新增共享 metrics，统一承载 toolbar host 的 spacing、inset 与 buttonEdge，作为两端测量结果的单一来源。
enum CanvasToolbarChromeMetrics {
    static let spacing: CGFloat = 12
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 12
    static let buttonEdge: CGFloat = 44
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize() / ensureSquareSize(for:)
// 功能说明: 修改后 macOS host 从共享 metrics 读取 spacing、inset 与 buttonEdge，本地 Layout 仅保留视觉层常量。
private enum Layout {
    static let cornerRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.12
    static let shadowRadius: CGFloat = 10
    static let shadowOffset = CGSize(width: 0, height: 4)
}

private let buttonsStackView: macOSCanvasChromeStackView = {
    let stackView = macOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = CanvasToolbarChromeMetrics.spacing
    return stackView
}()

func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.fittingSize
    return CanvasChromeLayoutGeometry.sanitizedSize(
        CGSize(
            width: stackSize.width + (CanvasToolbarChromeMetrics.horizontalInset * 2),
            height: stackSize.height + (CanvasToolbarChromeMetrics.verticalInset * 2)
        )
    )
}

private func ensureSquareSize(for button: NSButton) {
    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: CanvasToolbarChromeMetrics.buttonEdge)
        widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
        widthConstraint.isActive = true
    }

    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: CanvasToolbarChromeMetrics.buttonEdge)
        heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
        heightConstraint.isActive = true
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize() / ensureSquareSize(for:)
// 功能说明: 修改后 iOS host 与 macOS 对称地读取共享 metrics，避免两端在测量常量上继续重复维护。
private enum Layout {
    static let cornerRadius: CGFloat = 18
    static let shadowOpacity: Float = 0.12
    static let shadowRadius: CGFloat = 10
    static let shadowOffset = CGSize(width: 0, height: 4)
}

private let buttonsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = CanvasToolbarChromeMetrics.spacing
    return stackView
}()

func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.systemLayoutSizeFitting(
        UIView.layoutFittingCompressedSize
    )
    return CanvasChromeLayoutGeometry.sanitizedSize(
        CGSize(
            width: stackSize.width + (CanvasToolbarChromeMetrics.horizontalInset * 2),
            height: stackSize.height + (CanvasToolbarChromeMetrics.verticalInset * 2)
        )
    )
}

private func ensureSquareSize(for button: UIButton) {
    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: CanvasToolbarChromeMetrics.buttonEdge)
        widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
        widthConstraint.isActive = true
    }

    if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: CanvasToolbarChromeMetrics.buttonEdge)
        heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
        heightConstraint.isActive = true
    }
}
```

### 结果

- `toolbar` 测量结果相关常量现在只有一处来源。
- `iOS/macOS` 两端 host 的职责边界更清晰：平台本地只保留视觉层常量与各自 UI API，测量常量收回共享层。
- 本次没有改动 `measuredContentSize()` 的计算公式，也没有改变 `toolbar` 的实际布局行为。

## 修改二：统一 `macOS` placement scale 命名

### 修改前

- `iOSViewController` 已经使用 `toolbarPlacementScale()`。
- `macOSViewController` 仍然使用同职责但不同名的 `toolbarPlacementBackingScale()`。
- 两端语义一致但命名不一致，后续继续抽公共布局链时容易形成噪音。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyToolbarPlacement(using:) / toolbarPlacementBackingScale()
// 功能说明: 修改前 macOS 侧使用带有平台特征前缀的命名，和 iOS 的同职责方法未对齐。
private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    ).flatMap { frame in
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            frame,
            scale: toolbarPlacementBackingScale()
        )
    } ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func toolbarPlacementBackingScale() -> CGFloat {
    let scale = chromeOverlayView.window?.backingScaleFactor
        ?? view.window?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor
        ?? 2
    return scale.isFinite && scale > 0 ? scale : 1
}
```

### 修改后

- `macOSViewController` 收口为和 `iOS` 一致的 `toolbarPlacementScale()`。
- 方法内部实现没有变化，仍然返回 `backingScaleFactor` 链路上的有效 scale，只是职责命名被统一。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyToolbarPlacement(using:) / toolbarPlacementScale()
// 功能说明: 修改后 macOS 侧与 iOS 使用相同的方法名，便于后续把 placement 数据流继续向共享层收敛。
private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    ).flatMap { frame in
        CanvasChromeLayoutGeometry.pixelAlignedRectPreservingSize(
            frame,
            scale: toolbarPlacementScale()
        )
    } ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func toolbarPlacementScale() -> CGFloat {
    let scale = chromeOverlayView.window?.backingScaleFactor
        ?? view.window?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor
        ?? 2
    return scale.isFinite && scale > 0 ? scale : 1
}
```

### 结果

- `iOS/macOS` 两端 placement scale 的命名已经对齐。
- 这次只做命名统一，没有改变任何 scale 选择逻辑或像素对齐行为。

## 验证记录

- `ReadLints` 检查以下文件，结果为无错误：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- `swiftc -frontend -parse` 解析以下文件通过：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
