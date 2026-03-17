---
name: crop边框拖动计划
overview: 在 crop 模式下新增“拖动橙黄色边框移动裁剪框”的交互，保持 8 个 handle 优先级不变，并复用现有 draft/commit/history 链路。实现优先采用 controller-only 最小改动方案，在 iOS/macOS 两端对称落地。
todos:
  - id: crop-border-ios-state
    content: 在 iOS controller 中新增 crop 边框 press target、drag state 与 translation state
    status: completed
  - id: crop-border-ios-hit-drag
    content: 在 iOS controller 中实现边框命中与 local-space 平移 draft 更新
    status: completed
  - id: crop-border-history-commit
    content: 把 crop 边框拖动接入现有 crop history transaction 与 commit 链路
    status: completed
  - id: crop-border-macos-mirror
    content: 将同样的边框拖动逻辑镜像同步到 macOS controller
    status: completed
  - id: crop-border-validate
    content: 完成 lints、双平台构建与关键手动回归检查
    status: completed
isProject: false
---

# Crop 边框拖动计划

## 目标

- 在 `crop` 模式下，当光标位于橙黄色裁剪边框上且不在 8 个 `handle` 内时，按下并拖动可以整体移动裁剪框。
- 保持现有优先级：`handle > crop 边框 > blank`。
- 保持现有提交链路：仍通过 `inlineEditState.draftCropRectNormalized` 预览，结束后复用 `commitCropDraftIfNeeded()` 提交。

## 实现边界

- 仅修改 controller 层：
  - [MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift](MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift)
  - [MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift](MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift)
- 先不改 shared model / renderer / viewport：
  - [MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift)
  - [MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift](MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift)
  - [MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift](MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift)
- 复用已有几何与数据：
  - `editOverlay.payload.crop.cropScreenQuad`
  - `CanvasImageItem.localPoint(fromWorld:)`
  - `CanvasImageItem.normalizedCropRect(fromLocalFrame:)`
  - `commitCropDraftIfNeeded()`

## 关键设计

- 在 `PointerPressTarget` 中新增 `cropOutline(itemID)`。
- 在 `PointerDragState` 中新增专门的 crop 框平移状态，例如 `movingCropFrame(PointerCropTranslationState)`。
- 平移求解全部放在 item local space：
  - 按下时记录 `initialLocalFrame`、`fullImageLocalFrame`、`initialPointerLocalPoint`。
  - 拖动时计算 `deltaLocal`，对 `initialLocalFrame` 做 `offsetBy(dx:dy:)`。
  - 先把结果 clamp 在 `fullImageLocalFrame` 内，再转回 `draftCropRectNormalized`。
- 历史事务沿用现有 `crop item` reason，不单独引入新类型。

## 关键代码落点

- 命中优先级当前集中在 `pointerPressTarget(at:)`，需要把 `crop border hit` 插到 `isInlineEditModeActive -> .blank` 之前。
- 现有 `crop` 只认 `handle`：

```swift
// MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
private func pointerPressTarget(at viewportLocation: CGPoint) -> PointerPressTarget {
    if let editHandleHit = hitTestEditHandle(at: viewportLocation) {
        return editHandleHit.pressTarget
    }

    if isInlineEditModeActive {
        return .blank
    }
    // ...
}
```

- 现有 crop quad 已足够做边框命中：

```swift
// MyCanvas_Ver_0/Canvas/Core/CanvasRenderSnapshot.swift
struct CanvasEditCropOverlayPayload {
    let fullImageWorldQuad: CanvasQuad
    let fullImageScreenQuad: CanvasQuad
    let cropRectNormalized: CanvasImageCropRect
    let cropWorldQuad: CanvasQuad
    let cropScreenQuad: CanvasQuad
}
```

## 分步实施

1. 在 iOS controller 中扩展输入状态。
  - 新增 `PointerPressTarget.cropOutline(itemID:)`。
  - 新增 `PointerCropTranslationState`，保存 `itemID`、`fullImageLocalFrame`、`initialLocalFrame`、`initialPointerLocalPoint`。
  - 新增 `PointerDragState.movingCropFrame(...)`。
2. 在 iOS controller 中新增边框命中测试。
  - 新增 `hitTestCropOutline(at:)`。
  - 基于 `lastRenderSnapshot.editOverlay` 的 `cropScreenQuad` 做边框命中。
  - 命中顺序固定为：`hitTestEditHandle(at:)` 优先，其次 `hitTestCropOutline(at:)`。
  - 为边框新增单独的 hit target 宽度常量，避免过窄或与 handle 抢夺过多区域。
3. 在 iOS controller 中接入拖拽状态机。
  - 在 `handlePrimaryPointerMove(to:from:)` 的 `.pressed` 分支里，为 `cropOutline` 建立 translation state。
  - 持续拖动时调用新的 `updateTranslatedCropDraft(...)`。
  - 在 `handlePrimaryPointerUp(at:)` / cancel 路径中，让 `movingCropFrame` 也复用 `commitCropDraftIfNeeded()`。
  - 在 `beginPointerHistoryTransactionIfNeeded(for:)` 中，把 `cropOutline` 也映射为 `"crop item"`。
4. 在 iOS controller 中实现 local-space 平移求解。
  - 新增 `makePointerCropTranslationState(...)`。
  - 新增 `translatedCropLocalFrame(...)` 或等价 helper，用 `deltaLocal` 平移 `initialLocalFrame`。
  - 先对平移后的 frame 做 clamp，再转成 `draftCropRectNormalized`。
  - 保证平移不改 `width/height`，只改 `origin`。
5. 镜像同步到 macOS controller。
  - 按 iOS 同样的新增类型、命中、状态迁移、draft update、history 映射逐项同步。
  - 确保双端命名和行为一致，避免后续分叉。
6. 验证。
  - 运行 `ReadLints` 检查两端 controller。
  - 构建 iOS Simulator Debug 与 macOS Debug。
  - 手动回归重点验证：
    - 8 个 handle 命中优先级仍高于边框拖动
    - 四角/边中点 resize 与边框平移互不干扰
    - rotated item 下边框拖动方向正确
    - undo/redo 与单次手势单条历史记录仍成立

## 风险与控制

- 风险：边框 hit 区过宽会抢走靠近 handle 的操作。
  - 控制：保持 `handle` 先判定，再判边框；边框命中宽度独立调参。
- 风险：若先做 normalized rect sanitize 再平移，可能导致尺寸被动缩小。
  - 控制：先在 local frame 内 clamp 平移量，再做 `normalizedCropRect(fromLocalFrame:)`。
- 风险：旋转状态下若用 screen/world delta，会出现拖动方向不对。
  - 控制：统一使用 `item.localPoint(fromWorld:)` 做 local-space 平移求解。

