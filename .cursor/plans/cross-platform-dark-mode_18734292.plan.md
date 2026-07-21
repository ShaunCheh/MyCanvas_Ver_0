---
name: cross-platform-dark-mode
overview: 对 macOS 与 iOS 全 App 中“动态系统色转换为静态 CGColor 后不随外观刷新”的路径统一收口，预计涉及约 22–25 个文件、310–490 行。固定画布调色板、白纸、视频黑底、clear/black/shadow 等内容或效果色保持不变。
todos:
  - id: appearance-foundation
    content: 建立跨平台动态 layer 色解析、无动画刷新机制及基础测试
    status: completed
  - id: macos-appearance
    content: 收口 macOS 根界面、列表、转场、Canvas chrome 与外围编辑器外观刷新
    status: completed
  - id: ios-appearance
    content: 收口 iOS 窗口、列表、Canvas chrome、媒体与手绘界面外观刷新
    status: completed
  - id: shared-overlays
    content: 修复跨平台输入提示及 macOS 共享浮层的动态 layer 色
    status: completed
  - id: verify-themes
    content: 执行双平台构建、测试和完整浅色/深色切换回归验证
    status: completed
isProject: false
---

# 跨平台深色模式修复计划

## 处理边界
- 只处理动态语义色写入 `CALayer`、`CAShapeLayer`、`CATextLayer` 后失去动态性的路径；UIKit 原生 `backgroundColor`、文本色和按钮配置继续交给系统自动适配。
- 保持 [CanvasWorkspacePalette.swift](MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasWorkspacePalette.swift)、手绘白纸、视频黑底、固定阴影及 clear/black 色不变，避免改变画布内容语义。

## 统一外观刷新机制
- 新增平台条件编译的 layer 色解析辅助代码，macOS 使用当前 `effectiveAppearance`，iOS 使用当前 `traitCollection` 显式解析动态色，并在无隐式动画的事务内更新 layer。
- 各视图保留平台生命周期：macOS 在首次挂载及 `viewDidChangeEffectiveAppearance()` 调用 `updateAppearance()`；iOS 在首次挂载及 `traitCollectionDidChange(_:)` 中仅当颜色外观变化时刷新。
- 为颜色解析与明暗外观差异增加条件编译单元测试，避免后续重新引入“初始化时一次性 `.cgColor`”的问题。

## macOS 全面收口
- 修复根视图、Board List 与转场 shell：[macOSAppRootViewController.swift](MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift)、[macOSBoardListCanvasTransitionCarrier.swift](MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift)、[macOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift)、[macOSBoardCollectionItem.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift)。列表 Cell 外观变化时重放当前选中态；活动转场同步刷新 shell，避免切换主题时闪旧色。
- 修复 Canvas 根界面与浮层：[macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)、[macOSCanvasToolbarHostView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift)、[macOSCanvasTextEditorOverlayView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasTextEditorOverlayView.swift)。Toolbar 保存最近一次 item state，以便外观切换时重放背景、边框和按钮视觉角色。
- 扩展已有正确回调的 [macOSBoardPreviewView.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift) 与 [macOSCanvasMiniMapView.swift](MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasMiniMapView.swift)，让其余持久 layer 色也集中由 `updateAppearance()` 管理。
- 收口外围编辑界面：[macOSVideoTimelineView.swift](MyCanvas_Ver_0/Platform/macOS/macOSVideoTimelineView.swift)、[macOSGIFFrameImportViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift)、[macOSVideoDisplayFrameEditorViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift)、[macOSCanvasMarkdownEditorViewController.swift](MyCanvas_Ver_0/Platform/macOS/Markdown/macOSCanvasMarkdownEditorViewController.swift)。时间线在外观变化时无动画重绘 ruler；GIF Cell 重放当前选中态。

## iOS 全面收口
- 将 [iOSAppDelegate.swift](MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift) 的固定白色窗口背景改为动态 `systemBackground`，消除启动、转场和空白帧露白。
- 修复列表与预览：[iOSBoardCollectionViewCell.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift)、[iOSBoardPreviewView.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift)。Cell 重新应用当前选中态；Preview 把持久 layer 色统一纳入已有 `updateAppearance()`。
- 修复 Canvas chrome：[iOSCanvasToolbarHostView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift)、[iOSCanvasTextEditorOverlayView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasTextEditorOverlayView.swift)、[iOSCanvasMiniMapView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasMiniMapView.swift)，只刷新 border/fill/stroke 等 CGColor，不触发布局和内容重渲染。
- 修复媒体与手绘界面：[iOSVideoTimelineView.swift](MyCanvas_Ver_0/Platform/iOS/iOSVideoTimelineView.swift)、[iOSGIFFrameImportViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift)、[HandDrawingToolPaletteView.swift](MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingToolPaletteView.swift)、[HandDrawingLayerPanelView.swift](MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingLayerPanelView.swift)、[HandDrawingCanvasSurfaceView.swift](MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift)。保留白纸内容色，刷新动态边框并在需要时请求 interaction overlay 重绘。

## 共享浮层与验证
- 在 [CanvasInputIndicatorHostView.swift](MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift) 同时刷新 iOS/macOS item 背景与边框；macOS 的 [SelectionAccessoryHostView.swift](MyCanvas_Ver_0/Platform/Shared/SelectionAccessory/SelectionAccessoryHostView.swift) 和 [CanvasContextMenuHostView.swift](MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuHostView.swift) 重放当前 active 状态颜色。
- 分别构建 macOS 与 iOS Simulator 目标并运行相关测试；检查 lint 与 `git diff --check`。
- 手工验证浅色启动、深色启动、运行时切换，以及 Board List 选中/重命名、列表与 Canvas 转场、Toolbar、文本浮层、MiniMap、GIF、视频时间线、Markdown、手绘与共享浮层；重点确认无白闪、旧色残留和隐式 CALayer 动画。