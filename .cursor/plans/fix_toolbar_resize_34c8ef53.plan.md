---
name: fix toolbar resize
overview: 修复选中文本后 toolbar item 数量变化但 host 尺寸未重算的问题，避免 `+` 按钮被拉长；同时清理本次排查用的临时日志，并对 iOS 做同类路径对齐。
todos:
  - id: wire-toolbar-relayout
    content: 在 iOS/macOS view controller 中把 toolbar 内容变化路径接到完整的 placement 更新，而不只是 renderToolbar()
    status: pending
  - id: remove-toolbar-debug-logs
    content: 移除共享 builder 与 iOS/macOS toolbar host 中的临时调试日志
    status: pending
  - id: verify-toolbar-fix
    content: 做 lints + macOS typecheck，并复核文本/图片选择时 toolbar 尺寸变化
    status: pending
isProject: false
---

# 修复 Toolbar 尺寸重算

## 根因

- 选中文本后，共享 toolbar state 会正确隐藏 `crop`，item 数从 4 个变成 3 个，但当前仅调用 `renderToolbar()`，没有同步走完整的尺寸测量与 placement 更新。
- 在 [macOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 中，只有 `updatePreparedToolbarPlacement()` 会串起 `renderToolbar()`、`layoutSubtreeIfNeeded()` 和 `updateChromeOverlayLayout()`；而 `updateInlineEditButtonsAppearance()` 现在只调用了 `renderToolbar()`。
- [CanvasToolbarStateBuilder.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift) 的 `shouldShowCropItem(session:)` 逻辑本身是正确的，不需要改回去。

## 修改范围

- 在 [macOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift) 把会改变 toolbar 内容尺寸的刷新路径，从单纯 `renderToolbar()` 提升为完整的 `updatePreparedToolbarPlacement()` 或等价私有 helper。
- 在 [iOSViewController.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift) 做同样的结构对齐，避免 iOS 留下相同的“内容变了但 host 尺寸未重算”的隐患。
- 保持 [macOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift) 和 [iOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift) 的按钮尺寸约束不变；`NSStackView` / `UIStackView` 的 distribution 暂不作为根因修复项，只在必要时作为防御性加固再考虑。

## 调试清理

- 删除 [CanvasToolbarStateBuilder.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/Shared/Toolbar/CanvasToolbarStateBuilder.swift) 中新增的 `[Canvas Toolbar Debug][Shared]` 日志。
- 删除 [iOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift) 和 [macOSCanvasToolbarHostView.swift](/Users/shaun/Library/Mobile Documents/com~~apple~~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift) 中本次排查加入的 render/layout 调试日志。

## 验证

- 静态验证：对修改文件跑 `ReadLints`，再用 `xcrun --sdk macosx swiftc -typecheck -parse-as-library` 做一次全树 typecheck。
- 行为验证：在 macOS 复现“选中文字 -> crop 消失”场景，确认 toolbar host 高度会从 4 按钮尺寸缩回 3 按钮尺寸，`+` 按钮不再被拉长。
- 回归点：检查普通 image selection、进入/退出 text inline edit、save 状态切换时 toolbar 仍能正常刷新与重排。

