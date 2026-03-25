# 20260325_213632_toolbar_phase2_measurement_contract_record

## 记录范围

- 记录内容：
  1. 实施 `toolbar` 平台对称收敛计划的 `Phase 2`，把“内容尺寸 = stack 尺寸 + inset + sanitize”从 `iOS/macOS` 两端 host 中抽到共享 `Toolbar` 层。
  2. 保持平台差异仍在各自 host 内部：`iOS` 继续用 `systemLayoutSizeFitting(...)`，`macOS` 继续用 `fittingSize`。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarMeasurement.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - `Phase 3` 的 placement pass 收敛

## 修改一：把内容测量公式从平台 host 中抽到共享层

### 修改前

- `macOSCanvasToolbarHostView.measuredContentSize()` 和 `iOSCanvasToolbarHostView.measuredContentSize()` 都已经完成了 Phase 1 的常量收敛，但“`stackSize + inset + sanitize`”这个测量公式仍然各自内联在平台 host 中。
- 这意味着两端虽然表面一致，但公式本体仍旧是重复维护。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改前 macOS host 负责两件事：先用 AppKit 的 fittingSize 量 stack，再在本地把共享 inset 叠加成最终内容尺寸。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改前 iOS host 也承担同样的两层职责：先用 UIKit 的 systemLayoutSizeFitting 量 stack，再在本地拼装最终内容尺寸。
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
```

### 修改后

- 新增共享 `CanvasToolbarMeasurement`，专门承载“用共享 metrics 把 `stackSize` 转成 host 内容尺寸”的公式。
- 这样“平台测量 API”和“共享测量公式”被拆成两层职责：
  - 平台层：负责得到 `stackSize`
  - 共享层：负责把 `stackSize` 变成内容尺寸

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarMeasurement.swift
// 函数名: measuredContentSize(forMeasuredStackSize:)
// 功能说明: 新增共享测量 helper，统一承载 toolbar 内容尺寸公式，避免 iOS/macOS host 再各自重复维护 “stackSize + inset + sanitize” 逻辑。
enum CanvasToolbarMeasurement {
    static func measuredContentSize(
        forMeasuredStackSize stackSize: CGSize
    ) -> CGSize {
        CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: stackSize.width + (CanvasToolbarChromeMetrics.horizontalInset * 2),
                height: stackSize.height + (CanvasToolbarChromeMetrics.verticalInset * 2)
            )
        )
    }
}
```

### 结果

- 共享层现在同时拥有：
  - `CanvasToolbarChromeMetrics`
  - `CanvasToolbarMeasurement`
- `toolbar` 的内容尺寸公式不再分散在 `iOS/macOS` 两端 host 中。
- 本次没有改动公式本身，只是把公式搬到了共享层。

## 修改二：把两端 host 的 `measuredContentSize()` 收敛成同一职责结构

### 修改前

- 两端 host 对外都暴露 `measuredContentSize()`，但函数内部仍同时承担“平台测量 stack”和“本地拼装内容尺寸”两项职责。
- 这不利于后续继续做平台对称收敛，因为重复公式还留在平台实现里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改前 macOS host 内部直接把 fittingSize 和共享 metrics 公式拼在一起，职责尚未完全拆开。
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
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改前 iOS host 同样把 systemLayoutSizeFitting 和共享 metrics 公式直接耦合在同一个函数体内。
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
```

### 修改后

- `macOSCanvasToolbarHostView.measuredContentSize()` 现在只保留：
  1. 用 `fittingSize` 获取 `stackSize`
  2. 调用共享 `CanvasToolbarMeasurement`
- `iOSCanvasToolbarHostView.measuredContentSize()` 现在只保留：
  1. 用 `systemLayoutSizeFitting(...)` 获取 `stackSize`
  2. 调用同一个共享 `CanvasToolbarMeasurement`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改后 macOS host 只负责平台测量 stack，本地不再维护内容尺寸公式；公式统一由共享 ToolbarMeasurement 提供。
func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.fittingSize
    return CanvasToolbarMeasurement.measuredContentSize(
        forMeasuredStackSize: stackSize
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名: measuredContentSize()
// 功能说明: 修改后 iOS host 也只负责平台测量 stack，再把结果交给共享 ToolbarMeasurement 统一计算最终内容尺寸。
func measuredContentSize() -> CGSize {
    guard buttonsStackView.arrangedSubviews.isEmpty == false else {
        return .zero
    }

    let stackSize = buttonsStackView.systemLayoutSizeFitting(
        UIView.layoutFittingCompressedSize
    )
    return CanvasToolbarMeasurement.measuredContentSize(
        forMeasuredStackSize: stackSize
    )
}
```

### 结果

- 两端 `measuredContentSize()` 现在都只剩两步：
  1. 平台测量 `stackSize`
  2. 调共享 helper 计算最终内容尺寸
- 这正是 Phase 2 计划里定义的“共享内容测量契约”。
- `iOS/macOS` 对外仍然都暴露同名的 `measuredContentSize()`，接口语义保持一致。

## 结构变化总结

- Phase 1 收敛了共享测量常量：`CanvasToolbarChromeMetrics`
- Phase 2 继续收敛了共享测量公式：`CanvasToolbarMeasurement`
- 截至当前，两端 host 已经形成一致结构：
  - 平台侧负责拿到 `stackSize`
  - 共享层负责把 `stackSize` 转成 `toolbar` 内容尺寸

## 验证记录

- `ReadLints` 检查以下文件，结果为无错误：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarMeasurement.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- `swiftc -frontend -parse` 解析以下文件通过：
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarChromeMetrics.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarMeasurement.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
