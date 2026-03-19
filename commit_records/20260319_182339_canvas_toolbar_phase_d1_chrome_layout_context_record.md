# 20260319_182339_canvas_toolbar_phase_d1_chrome_layout_context_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段D-阶段1` 的实际代码变更。
- 本次实际产物：
- 新增共享 `CanvasChromeLayoutContext`、`CanvasChromeBlocker`、`CanvasChromeBlockerKind` 与 `CanvasChromeLayoutGeometry`，把 overlay/chrome 布局输入统一收口到共享层。
- 让 `iOS/macOS` 控制器不再分别维护 `chromeSafeBounds`、`chromeOccupiedRects`、`contextMenuSafeBounds`、`contextMenuOccupiedRects` 这一组局部几何输入函数，改为统一构建 `makeChromeLayoutContext()` / `makeContextMenuLayoutContext()`。
- 让 minimap solver 与 context menu host 都通过共享 layout context 的 `safeBounds` / `occupiedRects` 取数，保持 solver 独立但统一输入边界。
- 把 context menu 的调试日志也切换到共享 layout context，避免日志链路继续依赖旧的局部几何函数。
- 本次未执行：
- 未修改 `CanvasOverlayLayoutSolver` 的 minimap 放置算法。
- 未修改 `CanvasContextMenuLayoutSolver` 的菜单放置算法。
- 未进入 `阶段D-阶段2` 的 toolbar placement policy 重构。
- 未执行 git commit。

## 本次变更文件

- 新增：`MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前

- 到 `C4` 结束时，主工具栏已经实现了共享状态驱动，但 overlay/chrome 的布局输入仍散落在控制器里。
- `iOS/macOS` 控制器各自维护：
- `chromeSafeBounds()`
- `chromeOccupiedRects()`
- `contextMenuSafeBounds()`
- `contextMenuOccupiedRects()`
- minimap solver 和 context menu host 虽然都使用 `safeBounds / occupiedRects`，但这些输入没有统一 contract，也没有一个共享层的 blocker 语义模型。
- 项目里还没有独立的共享 `CanvasChromeLayoutContext` 文件；toolbar 的 preferred placement 与 measured size 也没有进入统一布局输入对象。

### Shared Layout Context 新增前状态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名/类型名: 文件级共享 chrome layout context
// 功能说明: 修改前该文件不存在；共享层还没有统一的 CanvasChromeLayoutContext 来承载 safeBounds、toolbarPlacement、measuredSize 与 chrome blockers。
// 该文件在阶段D-阶段1之前尚未创建。
```

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout()
// 功能说明: 修改前 iOS 的 context menu 直接从控制器局部函数读取 safeBounds 与 occupiedRects，没有统一共享 contract。
private func updateContextMenuPresentation() {
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: contextMenuSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}

private func updateContextMenuLayout() {
    contextMenuHostView.updateLayout(
        safeBounds: contextMenuSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / chromeSafeBounds() / chromeOccupiedRects() / contextMenuOccupiedRects() / contextMenuSafeBounds()
// 功能说明: 修改前 iOS 在控制器内部手工拼 minimap 与 context menu 的几何输入，toolbar placement 和 measured size 也没有进入统一对象。
private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func chromeSafeBounds() -> CGRect {
    let safeAreaInsets = view.safeAreaInsets
    return CGRect(
        x: view.bounds.minX + safeAreaInsets.left,
        y: view.bounds.minY + safeAreaInsets.top,
        width: max(view.bounds.width - safeAreaInsets.left - safeAreaInsets.right, 0),
        height: max(view.bounds.height - safeAreaInsets.top - safeAreaInsets.bottom, 0)
    ).standardized
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: historyButtonsStackView, to: &rects)
    appendChromeOccupiedRect(for: toolbarHostView, to: &rects)
    return rects
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }

    return rects.map { rect in
        convertToContextMenuHost(rect, from: chromeOverlayView)
    }
}

private func contextMenuSafeBounds() -> CGRect {
    convertToContextMenuHost(
        chromeSafeBounds(),
        from: chromeOverlayView
    )
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout()
// 功能说明: 修改前 macOS 的 context menu 同样直接消费控制器局部几何函数，而不是共享 layout context。
private func updateContextMenuPresentation() {
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: contextMenuSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}

private func updateContextMenuLayout() {
    contextMenuHostView.updateLayout(
        safeBounds: contextMenuSafeBounds(),
        occupiedRects: contextMenuOccupiedRects()
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / chromeSafeBounds() / chromeOccupiedRects() / contextMenuOccupiedRects() / contextMenuSafeBounds()
// 功能说明: 修改前 macOS 也把 safeBounds 和 blockers 的收集散落在控制器里，没有统一的 chrome 输入 contract。
private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func chromeSafeBounds() -> CGRect {
    let safeAreaInsets = view.safeAreaInsets
    return CGRect(
        x: view.bounds.minX + safeAreaInsets.left,
        y: view.bounds.minY + safeAreaInsets.top,
        width: max(view.bounds.width - safeAreaInsets.left - safeAreaInsets.right, 0),
        height: max(view.bounds.height - safeAreaInsets.top - safeAreaInsets.bottom, 0)
    ).standardized
}

private func chromeOccupiedRects() -> [CGRect] {
    var rects: [CGRect] = []
    appendChromeOccupiedRect(for: backButton, to: &rects)
    appendChromeOccupiedRect(for: toolbarHostView, to: &rects)
    return rects
}

private func contextMenuOccupiedRects() -> [CGRect] {
    var rects = chromeOccupiedRects()
    let miniMapFrame = miniMapMountView.frame.standardized
    if miniMapMountView.isHidden == false, miniMapFrame.isEmpty == false {
        rects.append(miniMapFrame)
    }

    return rects.map { rect in
        convertToContextMenuHost(rect, from: chromeOverlayView)
    }
}

private func contextMenuSafeBounds() -> CGRect {
    convertToContextMenuHost(
        chromeSafeBounds(),
        from: chromeOverlayView
    )
}
```

## 修改后

- 新增共享 `CanvasChromeLayoutContext`，统一表达：
- `safeBounds`
- `toolbarPreferredPlacement`
- `toolbarMeasuredSize`
- `chromeBlockers`
- 新增 `CanvasChromeBlockerKind`，让 blocker rect 不再只是“没有身份的 CGRect 数组”，而是具备 `backButton / historyButtons / toolbar / miniMap / contextMenu` 语义。
- 新增 `CanvasChromeLayoutGeometry`，集中放置首版几何清洗工具，避免 controller 再各自手写 rect/size sanitize。
- `iOS/macOS` 控制器现在都先构建：
- `makeChromeLayoutContext()`
- `makeContextMenuLayoutContext()`
- minimap solver 与 context menu host 继续各自保持原有算法，但输入都从共享 context 读取。
- context menu 的诊断日志也改为基于共享 context 输出 `safeBounds` 与 `occupiedRects`，避免调试链路与真实布局输入脱节。

### Shared Layout Context 新增后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasChromeLayoutContext.swift
// 函数名/类型名: CanvasChromeBlockerKind / CanvasChromeBlocker / CanvasChromeLayoutGeometry / CanvasChromeLayoutContext
// 功能说明: D1 新增共享 chrome layout context，把 safeBounds、toolbar placement、measured size 与 chrome blockers 收口到统一输入 contract。
import CoreGraphics
import Foundation

enum CanvasChromeBlockerKind: String, Sendable {
    case backButton
    case historyButtons
    case toolbar
    case miniMap
    case contextMenu
}

struct CanvasChromeBlocker: Hashable, Sendable {
    var kind: CanvasChromeBlockerKind
    var rect: CGRect
}

enum CanvasChromeLayoutGeometry {
    static func sanitizedRect(_ rect: CGRect) -> CGRect? {
        guard rect.isNull == false, rect.isInfinite == false else {
            return nil
        }

        let standardizedRect = rect.standardized
        guard
            standardizedRect.width > 0,
            standardizedRect.height > 0
        else {
            return nil
        }

        return standardizedRect
    }

    static func sanitizedSize(_ size: CGSize) -> CGSize {
        guard
            size.width.isFinite,
            size.height.isFinite
        else {
            return .zero
        }

        return CGSize(
            width: max(size.width, 0),
            height: max(size.height, 0)
        )
    }
}

struct CanvasChromeLayoutContext: Hashable, Sendable {
    var safeBounds: CGRect
    var toolbarPreferredPlacement: CanvasToolbarPlacement
    var toolbarMeasuredSize: CGSize
    var chromeBlockers: [CanvasChromeBlocker]

    var occupiedRects: [CGRect] {
        chromeBlockers.map(\.rect)
    }
}
```

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout()
// 功能说明: D1 之后，iOS 的 context menu 展示与重排都先读取共享 layout context，再传给 host。
private func updateContextMenuPresentation() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}

private func updateContextMenuLayout() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.updateLayout(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / toolbarPreferredPlacement() / makeChromeLayoutContext() / makeContextMenuLayoutContext() / appendChromeBlocker(...) / measuredToolbarHostSize()
// 功能说明: D1 之后，iOS 通过共享 CanvasChromeLayoutContext 统一准备 minimap 与 context menu 的几何输入，同时把 toolbar placement 与 measured size 也纳入 contract。
private func updateChromeOverlayLayout() {
    let layoutContext = makeChromeLayoutContext()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    CanvasToolbarPlacement(dockEdge: toolbarDockEdge)
}

private func makeChromeLayoutContext() -> CanvasChromeLayoutContext {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(kind: .backButton, for: backButton, to: &chromeBlockers)
    appendChromeBlocker(kind: .historyButtons, for: historyButtonsStackView, to: &chromeBlockers)
    appendChromeBlocker(kind: .toolbar, for: toolbarHostView, to: &chromeBlockers)

    return CanvasChromeLayoutContext(
        safeBounds: chromeOverlayView.safeAreaLayoutGuide.layoutFrame,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        chromeBlockers: chromeBlockers
    )
}

private func makeContextMenuLayoutContext() -> CanvasChromeLayoutContext {
    let chromeLayoutContext = makeChromeLayoutContext()
    var chromeBlockers = chromeLayoutContext.chromeBlockers.map { blocker in
        CanvasChromeBlocker(
            kind: blocker.kind,
            rect: convertToContextMenuHost(
                blocker.rect,
                from: chromeOverlayView
            )
        )
    }

    if
        miniMapMountView.isHidden == false,
        let miniMapRect = CanvasChromeLayoutGeometry.sanitizedRect(miniMapMountView.frame)
    {
        chromeBlockers.append(
            CanvasChromeBlocker(
                kind: .miniMap,
                rect: convertToContextMenuHost(miniMapRect, from: chromeOverlayView)
            )
        )
    }

    return CanvasChromeLayoutContext(
        safeBounds: convertToContextMenuHost(
            chromeLayoutContext.safeBounds,
            from: chromeOverlayView
        ),
        toolbarPreferredPlacement: chromeLayoutContext.toolbarPreferredPlacement,
        toolbarMeasuredSize: chromeLayoutContext.toolbarMeasuredSize,
        chromeBlockers: chromeBlockers
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: logContextMenuPresentation(...)
// 功能说明: D1 之后，iOS 的 context menu 诊断日志也基于共享 layout context 输出 safeBounds 与 occupiedRects。
private func logContextMenuPresentation(
    resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let layoutContext = makeContextMenuLayoutContext()
    let occupiedRectsDescription = layoutContext.occupiedRects
        .map(describe(rect:))
        .joined(separator: ", ")
    // ... 省略其余日志字段
}
```

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateContextMenuPresentation() / updateContextMenuLayout()
// 功能说明: D1 之后，macOS 的 context menu 输入也统一改由共享 layout context 提供。
private func updateContextMenuPresentation() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.apply(
        state: contextMenuState,
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}

private func updateContextMenuLayout() {
    let layoutContext = makeContextMenuLayoutContext()
    contextMenuHostView.updateLayout(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: updateChromeOverlayLayout() / toolbarPreferredPlacement() / makeChromeLayoutContext() / makeContextMenuLayoutContext() / appendChromeBlocker(...) / measuredToolbarHostSize()
// 功能说明: D1 之后，macOS 同样通过共享 layout context 统一准备 overlay 布局输入，并保留 minimap/menu 各自 solver。
private func updateChromeOverlayLayout() {
    let layoutContext = makeChromeLayoutContext()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
    miniMapMountView.isHidden = miniMapFrame.isEmpty
    if miniMapView.frame != miniMapMountView.bounds {
        miniMapView.frame = miniMapMountView.bounds
    }
    updateContextMenuLayout()
}

private func toolbarPreferredPlacement() -> CanvasToolbarPlacement {
    CanvasToolbarPlacement(dockEdge: toolbarDockEdge)
}

private func makeChromeLayoutContext() -> CanvasChromeLayoutContext {
    var chromeBlockers: [CanvasChromeBlocker] = []
    appendChromeBlocker(kind: .backButton, for: backButton, to: &chromeBlockers)
    appendChromeBlocker(kind: .toolbar, for: toolbarHostView, to: &chromeBlockers)

    return CanvasChromeLayoutContext(
        safeBounds: CGRect(
            x: view.bounds.minX + view.safeAreaInsets.left,
            y: view.bounds.minY + view.safeAreaInsets.top,
            width: max(view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right, 0),
            height: max(view.bounds.height - view.safeAreaInsets.top - view.safeAreaInsets.bottom, 0)
        ).standardized,
        toolbarPreferredPlacement: toolbarPreferredPlacement(),
        toolbarMeasuredSize: measuredToolbarHostSize(),
        chromeBlockers: chromeBlockers
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: logContextMenuPresentation(...)
// 功能说明: D1 之后，macOS 的 context menu 日志同样切到共享 layout context，避免日志链路继续依赖旧局部函数。
private func logContextMenuPresentation(
    resolvedContext: CanvasContextMenuContext,
    commandIDs: [CanvasCommandID]
) {
    let layoutContext = makeContextMenuLayoutContext()
    let occupiedRectsDescription = layoutContext.occupiedRects
        .map(describe(rect:))
        .joined(separator: ", ")
    // ... 省略其余日志字段
}
```

## 阶段D1完成情况

- 已完成：新增共享 `CanvasChromeLayoutContext`。
- 已完成：新增共享 `CanvasChromeBlockerKind` / `CanvasChromeBlocker`。
- 已完成：新增共享 `CanvasChromeLayoutGeometry` 首版几何清洗工具。
- 已完成：`iOS` 控制器通过共享 layout context 提供 minimap 与 context menu 输入。
- 已完成：`macOS` 控制器通过共享 layout context 提供 minimap 与 context menu 输入。
- 已完成：context menu 调试日志切到共享 layout context。
- 未完成：toolbar 独立 placement policy。
- 未完成：minimap / context menu / toolbar 的统一布局链整合。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 D1 记录文件名，并对 D1 的共享 chrome layout context 改动执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_D1_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_D1_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_182339`
- `ReadLints` 对本次修改文件无报错。
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次过程中曾出现 `NSLayoutGuide` 无 `layoutFrame` 的 macOS 编译错误，已改回基于 `safeAreaInsets` 的 `safeBounds` 采集后重新构建通过。

## 结论

- `D1` 的核心不是重写 minimap 或 context menu solver，而是先把它们依赖的几何输入 contract 真正统一起来。
- 到这一阶段为止，toolbar/minimap/context menu 已经开始共享同一份 chrome 布局输入边界，后续 `D2` 可以在这份 contract 之上继续抽离 toolbar 的独立 placement policy，而不需要再回头整理 controller 里的几何来源。
