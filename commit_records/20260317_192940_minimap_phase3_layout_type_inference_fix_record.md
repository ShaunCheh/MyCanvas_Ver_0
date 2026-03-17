# 20260317_192940_minimap_phase3_layout_type_inference_fix_record

## 记录范围

- 记录内容：
  1. 修复 `CanvasMiniMapLayout.swift` 中 `occupiedRects.compactMap` 的 Swift 泛型类型推断失败。
  2. 将 `blockerRects` 的类型改为显式 `[CGRect]`，并为闭包返回值显式声明 `CGRect?`。
  3. 将局部变量名从 `sanitizedRect` 调整为 `sanitizedOccupiedRect`，避免与同名辅助函数混淆。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift`
- 本记录不包含：
  - 原始 gif diff
  - git commit / push
  - minimap 其它阶段的功能实现

## 问题现象

- `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift` 报错：
  - `Generic parameter 'ElementOfResult' could not be inferred`
- 报错位置在 `resolveMiniMapFrame(safeBounds:occupiedRects:configuration:)` 内部的 `occupiedRects.compactMap`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift
// 函数名: resolveMiniMapFrame(safeBounds:occupiedRects:configuration:)
// 功能说明: 这里负责把已有 chrome 占位区域转换成 minimap 需要避让的 blocker rect；修改前编译器无法正确推断 compactMap 的返回类型。
let blockerRects = occupiedRects.compactMap { rect in
    guard let sanitizedRect = sanitizedRect(rect) else {
        return nil
    }

    return sanitizedRect.insetBy(
        dx: -configuration.chromeClearance,
        dy: -configuration.chromeClearance
    )
}
```

## 修改前

- `blockerRects` 没有显式类型。
- `compactMap` 闭包也没有标明返回值类型。
- 闭包内部局部变量名 `sanitizedRect` 与同名辅助函数 `sanitizedRect(_:)` 重名，进一步增加了可读性与推断上的歧义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift
// 函数名: resolveMiniMapFrame(safeBounds:occupiedRects:configuration:)
// 功能说明: 修改前 compactMap 依赖编译器自行推断 ElementOfResult，局部变量名也和辅助函数重名。
let blockerRects = occupiedRects.compactMap { rect in
    guard let sanitizedRect = sanitizedRect(rect) else {
        return nil
    }

    return sanitizedRect.insetBy(
        dx: -configuration.chromeClearance,
        dy: -configuration.chromeClearance
    )
}
```

## 修改后

- 给 `blockerRects` 增加显式类型：`[CGRect]`
- 给 `compactMap` 闭包增加显式返回类型：`CGRect?`
- 将局部变量名改为 `sanitizedOccupiedRect`
- 这样编译器不再需要从上下文猜测 `ElementOfResult`，单文件和 Core 全量 typecheck 都能通过。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift
// 函数名: resolveMiniMapFrame(safeBounds:occupiedRects:configuration:)
// 功能说明: 修改后显式声明 compactMap 的结果类型和闭包返回值类型，并避免局部变量名与辅助函数重名。
let blockerRects: [CGRect] = occupiedRects.compactMap { rect -> CGRect? in
    guard let sanitizedOccupiedRect = sanitizedRect(rect) else {
        return nil
    }

    return sanitizedOccupiedRect.insetBy(
        dx: -configuration.chromeClearance,
        dy: -configuration.chromeClearance
    )
}
```

## 修改影响

- 这是一次纯编译修复，不改变 minimap 布局算法的业务语义。
- 影响范围仅限 `resolveMiniMapFrame(...)` 内部 blocker rect 的生成实现。
- 修复后：
  - minimap 布局求解器仍按原计划工作
  - `Phase 3` 的布局层结构不需要回退
  - 后续 `Phase 4` 可以继续基于当前 layout solver 开发

## 校验情况

- 已执行：
  - `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift`
  - `swiftc -typecheck MyCanvas_Ver_0/Canvas/Core/*.swift`
- 两项均通过。
- `ReadLints` 未发现新增问题。
