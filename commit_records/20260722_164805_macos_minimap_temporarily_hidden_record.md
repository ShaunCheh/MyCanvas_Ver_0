# 20260722_164805_macos_minimap_temporarily_hidden_record

## 背景

本次修改是在 macOS 上暂时不显示左下角 minimap，但不删除 minimap 的实现。

实现方式是新增一个 macOS controller 内部开关 `showsMiniMap = false`，让 minimap 不再解析可见 frame，也不再刷新真实 snapshot。相关 view、layout solver、navigation handler 和 minimap 类型都保留，后续只需要打开开关即可恢复。

## 修改 1：新增 macOS minimap 显示开关

修改前，macOS controller 没有类似 iOS 的 minimap 显示开关。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型：macOSViewController；修改前，没有 showsMiniMap 开关
private static let isPointerHitTraceLoggingEnabled = true
private static let observedKeyboardShortcutReuseWindow: TimeInterval = 0.45
private static let continuousRawInputObservationInterval: TimeInterval = 0.32

private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
private let alignmentGuideSolver = CanvasAlignmentGuideSolver()
```

修改后，新增 `showsMiniMap = false`。这是临时隐藏开关，不删除 minimap 相关对象。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型：macOSViewController；修改后，新增 minimap 临时隐藏开关
private static let isPointerHitTraceLoggingEnabled = true
private static let observedKeyboardShortcutReuseWindow: TimeInterval = 0.45
private static let continuousRawInputObservationInterval: TimeInterval = 0.32
private static let showsMiniMap = false

private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
private let alignmentGuideSolver = CanvasAlignmentGuideSolver()
```

## 修改 2：关闭时不解析 minimap frame

修改前，`resolveMiniMapFrame(in:)` 总是调用 `miniMapLayoutSolver.resolveMiniMapFrame(...)`，因此 macOS 左下角会继续显示 minimap。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：resolveMiniMapFrame(in:)；修改前，总是解析 minimap frame
private func resolveMiniMapFrame(
    in layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
}
```

修改后，如果 `showsMiniMap == false`，直接返回 `.zero`。后续 `applyMiniMapFrame(_:)` 会根据 empty frame 隐藏 `miniMapMountView`，并且 context menu layout 不会把 minimap 加入 blocker。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：resolveMiniMapFrame(in:)；修改后，关闭开关时返回 zero frame
private func resolveMiniMapFrame(
    in layoutContext: CanvasChromeLayoutContext
) -> CGRect {
    guard Self.showsMiniMap else {
        return .zero
    }

    return miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: layoutContext.safeBounds,
        occupiedRects: layoutContext.occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
}
```

## 修改 3：关闭时不刷新真实 minimap snapshot

修改前，`refreshMiniMap()` 每次 canvas refresh 都构建 miniMap snapshot 并应用到 `miniMapView`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：refreshMiniMap()；修改前，总是生成并应用 minimap snapshot
private func refreshMiniMap() {
    let snapshot = editorSession.makeMiniMapSnapshot()
    miniMapView.apply(snapshot)
}
```

修改后，关闭开关时应用 `.empty` 后返回，不再生成真实 snapshot。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数：refreshMiniMap()；修改后，关闭开关时清空并跳过真实 snapshot 刷新
private func refreshMiniMap() {
    guard Self.showsMiniMap else {
        miniMapView.apply(.empty)
        return
    }

    let snapshot = editorSession.makeMiniMapSnapshot()
    miniMapView.apply(snapshot)
}
```

## 保留内容

本次没有删除以下 minimap 实现：

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 保留：minimap view、layout solver、setup 和 navigation handler 仍存在
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
private let miniMapMountView: macOSCanvasChromeOverlayView = { /* ... */ }()
private let miniMapView = macOSCanvasMiniMapView()

private func setupMiniMapView() { /* ... */ }
private func handleMiniMapNavigate(to miniMapPoint: CGPoint) { /* ... */ }
```

## 验证

已执行 lints 检查：

```shell
# terminal
# 验证命令：检查本次修改的 macOSViewController.swift
ReadLints(paths: [
    "/Users/shaun/cloudDev/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift"
])
```

结果：无 linter 错误。

已执行 macOS build。第一次 build 发现 `resolveMiniMapFrame(in:)` 从单表达式函数变为多语句函数后缺少显式 `return`；已补充 `return` 后重新验证。

```shell
# terminal
# 验证命令：macOS arm64 build
xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination 'platform=macOS,arch=arm64'
```

结果：build 通过。

## 当前状态

当前 changes：

```shell
# terminal
# 命令：git status --short，显示 macOS minimap 临时隐藏代码改动和本记录文件
M MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
?? commit_records/20260722_164805_macos_minimap_temporarily_hidden_record.md
```

本次没有提交代码。
