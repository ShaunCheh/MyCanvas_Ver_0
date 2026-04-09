# 20260409_192324_macos_toolbar_frame_sanitize_guard_fix_record

## 记录说明

本记录基于当前工作区里“刚刚这次 macOS toolbar frame sanitize guard 修复”的 `git diff` 与已落地代码整理，不包含原始 `git diff` 文本。

本次只记录 1 个文件的新增修改：

- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前统计：`1 file changed, 8 insertions(+), 2 deletions(-)`

## 问题背景

在上一轮给 `macOSCanvasToolbarHostView` 增加 bootstrap 非零初始尺寸之后，用户仍然观察到 opening 路径上的约束冲突日志。

继续沿链路排查后，发现问题不只出在 host 初始化阶段，还出在 toolbar frame 应用阶段：

- `CanvasToolbarPlacementPass.resolve(...)` 在某些早期布局时机如果暂时解不出合法 frame，会返回 `.zero`
- `macOSViewController.applyToolbarFrame(...)` 原先会无条件把这个 `zero rect` 直接写回 `toolbarHostView.frame`
- 一旦 host 后续再次被压到 `width == 0`，内部 chrome 结构里的左右 inset 约束就会再次和宿主宽度冲突

也就是说，bootstrap 修复只解决了“初始化时不要是 0”，但还缺少“后续也不要把非法 frame 写回去”的第二层防线。

## 详细修改

### `macOSViewController.swift`：应用 toolbar frame 前先做 sanitize 守卫

修改前：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: applyToolbarFrame(_:)
// 说明: 旧逻辑会把 placement pass 返回的 toolbarFrame 原样写给 host，即使它是 .zero 或非法矩形。
private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    if toolbarHostView.frame != toolbarFrame {
        toolbarHostView.frame = toolbarFrame
    }
}
```

修改后：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数: applyToolbarFrame(_:)
// 说明: 只有当 toolbarFrame 是合法且宽高都大于 0 的矩形时，才允许写回 toolbarHostView。
private func applyToolbarFrame(_ toolbarFrame: CGRect) {
    guard isToolbarTransitionActive == false else {
        markToolbarTransitionLayoutReconcilePending()
        return
    }

    guard let sanitizedToolbarFrame = CanvasChromeLayoutGeometry.sanitizedRect(
        toolbarFrame
    ) else {
        return
    }

    if toolbarHostView.frame != sanitizedToolbarFrame {
        toolbarHostView.frame = sanitizedToolbarFrame
    }
}
```

## 修改意图

这次修复的目标不是改变 toolbar 的正式摆放逻辑，而是补一层“非法结果不落盘”的守卫：

- 如果 placement solver 给出了合法 frame：照常应用
- 如果 solver 在早期布局时给出 `.zero` 或其他非法 rect：直接忽略，保持当前合法 frame

这样就不会再把 `toolbarHostView` 压回 `width == 0`，也就不会再次触发内部 chrome inset 与宿主宽度之间的冲突。

## 与上一轮修复的关系

上一份记录：

- `commit_records/20260409_190848_macos_toolbar_bootstrap_constraint_fix_record.md`

处理的是：

- 初始化时避免 host 以零尺寸进入约束系统

本次修复处理的是：

- 后续布局阶段避免把非法 `toolbarFrame` 再次写回 host

两次修复合在一起，分别覆盖：

- 初始 frame 建立阶段
- 运行中 frame 更新阶段

## 验证

已完成：

- IDE lints：无新增错误
- 编译验证：
  - 命令：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -sdk iphonesimulator -configuration Debug build`
  - 结果：`BUILD SUCCEEDED`

尚未在本记录中完成：

- 实际运行 macOS opening 路径，确认那条约束冲突日志是否完全消失

## 补充说明

本记录只覆盖这次 `macOSViewController.swift` 的 toolbar frame sanitize guard 修复，不重复展开此前的 bootstrap 修复、compile fix 或 boardlist reveal 修复。
