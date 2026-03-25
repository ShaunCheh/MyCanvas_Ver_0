# 20260325_125425_toolbar_measurement_feedback_loop_fix_record

## 记录范围

- 记录内容：
  1. 修复 `macOS` 侧 `toolbar` 在 `NSView` 路径上的尺寸反馈回路，避免 `fittingSize` 测量被宿主当前 `frame` 反向污染，并去掉会把尺寸向外放大的 `.integral` 回写方式。
  2. 将同一套“只测内容尺寸 + 保尺寸像素对齐”的处理同构收敛到 `iOS` 侧，避免 `UIView` 路径以后出现同类问题。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - 与本次 toolbar 尺寸反馈回路无关的功能变更

## 修改一：`macOS` 侧根因修复

### 问题归因

- `toolbarHostView` 在控制器里是手动写 `frame` 的视图，但宿主内部又是 Auto Layout 容器。
- 修改前，控制器用 `toolbarHostView.fittingSize` 作为测量值，同时把 solver 求出的结果做 `CGRect.integral` 后再回写给 `toolbarHostView.frame`。
- 这会把“旧 frame 的 autoresizing mask 约束”重新带回测量阶段，形成错误反馈回路；一旦 `integral` 因半像素把高度向外扩张，就可能制造 `1pt` 的不可满足约束。

### 修改前

- 宿主尺寸测量直接读 `toolbarHostView.fittingSize`。
- 布局结果直接对整个 `CGRect` 做 `.integral`，会在某些位置把高度从内容真实值向外放大。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyToolbarPlacement(using:) / measuredToolbarHostSize()
// 功能说明: 修改前控制器同时使用“宿主 view 自测量”和“整体 integral 回写”，这两者叠加构成了 macOS toolbar 的尺寸反馈回路。
private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func measuredToolbarHostSize() -> CGSize {
    let measuredSize = toolbarHostView.fittingSize
    let fallbackSize = toolbarHostView.bounds.size
    let candidateSize = measuredSize == .zero
        ? fallbackSize
        : measuredSize
    return CanvasChromeLayoutGeometry.sanitizedSize(candidateSize)
}
```

### 修改后

- 在 `macOSCanvasToolbarHostView` 新增 `measuredContentSize()`，只测 `buttonsStackView` 的内容尺寸，并把 `horizontalInset` / `verticalInset` 加回去。
- 在共享几何层新增 `pixelAlignedRectPreservingSize(...)`，只对原点做像素对齐，保留 solver 计算出的真实宽高。
- 在 `macOSViewController` 中改为调用宿主内容测量接口，并以“保尺寸像素对齐”替代 `.integral`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改后宿主只测量 stack 内容尺寸，不再让根视图当前 frame/bounds 反向参与 toolbar 尺寸计算。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名: pixelAlignedRectPreservingSize(_:scale:)
// 功能说明: 修改后共享几何层提供“保尺寸像素对齐”能力，只对原点取像素网格，不允许对宽高做额外外扩。
static func pixelAlignedRectPreservingSize(
    _ rect: CGRect,
    scale: CGFloat
) -> CGRect? {
    guard let sanitizedRect = sanitizedRect(rect) else {
        return nil
    }

    let sanitizedScale: CGFloat
    if scale.isFinite, scale > 0 {
        sanitizedScale = scale
    } else {
        sanitizedScale = 1
    }

    func alignToPixel(_ value: CGFloat) -> CGFloat {
        (value * sanitizedScale).rounded() / sanitizedScale
    }

    return CGRect(
        x: alignToPixel(sanitizedRect.minX),
        y: alignToPixel(sanitizedRect.minY),
        width: sanitizedRect.width,
        height: sanitizedRect.height
    ).standardized
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: applyToolbarPlacement(using:) / measuredToolbarHostSize() / toolbarPlacementBackingScale()
// 功能说明: 修改后控制器改为“内容测量 + 保尺寸像素对齐”，彻底切断 macOS toolbar 的尺寸反馈回路。
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

private func measuredToolbarHostSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(
        toolbarHostView.measuredContentSize()
    )
}

private func toolbarPlacementBackingScale() -> CGFloat {
    let scale = chromeOverlayView.window?.backingScaleFactor
        ?? view.window?.backingScaleFactor
        ?? NSScreen.main?.backingScaleFactor
        ?? 2
    return scale.isFinite && scale > 0 ? scale : 1
}
```

### 结果

- `macOS` 侧 `toolbarMeasuredSize` 现在只由按钮、spacing、inset 决定。
- `toolbarHostView.frame` 回写时不再因为 `.integral` 把真实尺寸向外扩大。
- `NSView` 路径上的“宿主 frame 反向污染测量”问题被从根上切断。

## 修改二：`iOS` 侧同构收敛

### 收敛目的

- `iOS` 原先虽然没有暴露出与 `macOS` 完全相同的报错，但布局链路结构是同类问题的温床：同样存在“宿主自测量 + 整体 integral 回写”。
- 为了避免 `UIView` 路径未来出现同样的尺寸反馈回路，本次同步把 `iOS` 对齐到与 `macOS` 一致的模型。

### 修改前

- `iOSViewController` 直接使用 `toolbarHostView.systemLayoutSizeFitting(...)` 作为宿主尺寸。
- `applyToolbarPlacement(using:)` 同样直接对 solver 结果做 `.integral`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyToolbarPlacement(using:) / measuredToolbarHostSize()
// 功能说明: 修改前 iOS 侧仍然沿用“宿主 view 自测量 + 整体 integral 回写”的旧链路，结构上与 macOS 的问题源一致。
private func applyToolbarPlacement(
    using layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    let resolvedFrame = toolbarPlacementSolver.resolveFrame(
        in: layoutContext
    )?.integral ?? .zero

    if toolbarHostView.frame != resolvedFrame {
        toolbarHostView.frame = resolvedFrame
    }

    return resolvedFrame
}

private func measuredToolbarHostSize() -> CGSize {
    let measuredSize = toolbarHostView.systemLayoutSizeFitting(
        UIView.layoutFittingCompressedSize
    )
    let fallbackSize = toolbarHostView.bounds.size
    let candidateSize = measuredSize == .zero
        ? fallbackSize
        : measuredSize
    return CanvasChromeLayoutGeometry.sanitizedSize(candidateSize)
}
```

### 修改后

- 在 `iOSCanvasToolbarHostView` 新增 `measuredContentSize()`，只测 `buttonsStackView` 的内容。
- 在 `iOSViewController` 中改为复用共享的 `pixelAlignedRectPreservingSize(...)`，并通过 `toolbarPlacementScale()` 获取屏幕 scale。
- `iOS` 侧的 toolbar 尺寸模型与 `macOS` 侧完全对齐。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改后 iOS 宿主也只测量 stack 内容尺寸，避免 UIView 根节点当前 frame/bounds 参与下一轮 toolbar 尺寸计算。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: applyToolbarPlacement(using:) / measuredToolbarHostSize() / toolbarPlacementScale()
// 功能说明: 修改后 iOS 控制器复用共享“保尺寸像素对齐”能力，并通过内容测量接口获取 toolbar 真实尺寸，实现与 macOS 对称的布局链。
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

private func measuredToolbarHostSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(
        toolbarHostView.measuredContentSize()
    )
}

private func toolbarPlacementScale() -> CGFloat {
    let scale = chromeOverlayView.window?.screen.scale
        ?? view.window?.screen.scale
        ?? UIScreen.main.scale
    return scale.isFinite && scale > 0 ? scale : 1
}
```

### 结果

- `iOS` 侧与 `macOS` 侧统一为同一套 toolbar 尺寸职责边界。
- 未来如果按钮数量、排列方向或 inset 变化，测量来源仍然只会是内容本身，而不是宿主旧 frame。
- `UIView` 路径不再保留与本次 `macOS` 问题同构的尺寸反馈回路。

## 验证记录

- `ReadLints`：
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
  - 结果：无 linter 错误。
- `swiftc -frontend -parse`：
  - `macOS` 侧修改文件解析通过。
  - `iOS` 侧未完成同等级解析，原因是当前机器上的 `xcrun` 无法定位 `iphonesimulator` SDK。
- `xcodebuild`：
  - 当前机器的 `xcode-select` 指向 `CommandLineTools`，未能执行工程级 `xcodebuild` 校验。
