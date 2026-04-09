# 20260409_190848_macos_toolbar_bootstrap_constraint_fix_record

## 记录说明

本记录基于当前工作区里“刚刚这次 macOS toolbar bootstrap 约束修复”的 `git diff` 与已落地代码整理，不包含原始 `git diff` 文本。

本次只记录 1 个文件的新增修改：

- `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`

当前统计：`1 file changed, 20 insertions(+), 1 deletion(-)`

## 问题背景

控制台报错位置出现在：

- `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSAppRootViewController.swift:147`

约束冲突信息说明：

- `macOSCanvasToolbarHostView` 在 opening 过程中一度出现 `width == 0`
- 但 `macOSCanvasToolbarHostView` 内部的 `buttonsStackView` 同时有左右各 `12` 的 inset 约束
- 因此在早期布局阶段会出现“父视图宽度为 0，但子视图左右都要保留边距”的瞬时冲突

这次没有修改 `macOSAppRootViewController.swift`，而是直接从根因修正 `macOSCanvasToolbarHostView` 的初始尺寸。

## 根因说明

当前实现里，toolbar host 是一个靠后续 frame 布局驱动的宿主视图；但在真正 toolbar frame 计算完成之前，AppRoot 会先触发一次布局。

修改前的 host 初始化逻辑是直接使用传入的 `frameRect`：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数: override init(frame:)
// 说明: 初始化时直接使用 frameRect，如果初始 frame 是零尺寸，就会把内部左右 inset 约束暴露到 width == 0 的瞬时布局里。
override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    wantsLayer = true
    addSubview(backgroundView)
    addSubview(contentClipView)
    contentClipView.addSubview(buttonsStackView)
    NSLayoutConstraint.activate([
        backgroundView.topAnchor.constraint(equalTo: topAnchor),
        backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
        backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
        backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
        contentClipView.topAnchor.constraint(equalTo: topAnchor),
        contentClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
        contentClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
        contentClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
        buttonsStackView.topAnchor.constraint(
            equalTo: contentClipView.topAnchor,
            constant: CanvasToolbarChromeMetrics.verticalInset
        ),
        buttonsStackView.leadingAnchor.constraint(
            equalTo: contentClipView.leadingAnchor,
            constant: CanvasToolbarChromeMetrics.horizontalInset
        ),
        buttonsStackView.trailingAnchor.constraint(
            equalTo: contentClipView.trailingAnchor,
            constant: -CanvasToolbarChromeMetrics.horizontalInset
        )
    ])
    updateDockEdgeLayout()
}
```

问题在于，这段代码要求内部 chrome 结构从一开始就是“可承载左右 inset 的合法宽度”，但初始化时并没有保证这一点。

## 详细修改

### `macOSCanvasToolbarHostView.swift`：为 host 增加合法的 bootstrap 初始尺寸

修改后，先根据 toolbar chrome 的最小可用内容尺寸，计算一个合法的非零 bootstrap size；然后在 `init(frame:)` 里用这个 size 包装初始 frame。

修改后代码如下：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数: Layout / override init(frame:) / bootstrapFrame(from:)
// 说明: 在真正 toolbar frame 出来前，先给 host 一个合法非零尺寸，避免 width == 0 与内部左右 inset 约束冲突。
final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
        // AppRoot can force an early layout pass before the controller computes
        // the real toolbar frame. Bootstrap with a legal non-zero size so the
        // internal chrome insets do not conflict against a transient width == 0.
        static let minimumBootstrapSize = CanvasToolbarMeasurement.measuredContentSize(
            forMeasuredStackSize: CGSize(
                width: CanvasToolbarChromeMetrics.buttonEdge,
                height: CanvasToolbarChromeMetrics.buttonEdge
            )
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: Self.bootstrapFrame(from: frameRect))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        addSubview(backgroundView)
        addSubview(contentClipView)
        contentClipView.addSubview(buttonsStackView)
        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentClipView.topAnchor.constraint(equalTo: topAnchor),
            contentClipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentClipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentClipView.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttonsStackView.topAnchor.constraint(
                equalTo: contentClipView.topAnchor,
                constant: CanvasToolbarChromeMetrics.verticalInset
            ),
            buttonsStackView.leadingAnchor.constraint(
                equalTo: contentClipView.leadingAnchor,
                constant: CanvasToolbarChromeMetrics.horizontalInset
            ),
            buttonsStackView.trailingAnchor.constraint(
                equalTo: contentClipView.trailingAnchor,
                constant: -CanvasToolbarChromeMetrics.horizontalInset
            )
        ])
        updateDockEdgeLayout()
    }

    private static func bootstrapFrame(from frameRect: CGRect) -> CGRect {
        CGRect(
            origin: frameRect.origin,
            size: CGSize(
                width: max(frameRect.width, Layout.minimumBootstrapSize.width),
                height: max(frameRect.height, Layout.minimumBootstrapSize.height)
            )
        )
    }
}
```

## 修改影响

这次修复的实际效果是：

- 在 AppRoot 提前触发布局时，toolbar host 不再以 `width == 0` 进入内部 Auto Layout
- 内部 `buttonsStackView` 的左右 inset 约束有了可容纳的最小宽度
- 真正的 toolbar frame 仍然会在后续 `applyToolbarFrame(...)` 阶段被覆盖，不改变正式布局逻辑

也就是说，这次修改修的是“初始瞬时非法尺寸”，不是改 toolbar 的最终布局策略。

## 验证

已完成：

- `git diff --stat` 已确认本次只涉及 `macOSCanvasToolbarHostView.swift`
- IDE lints：无新增错误
- 编译验证：
  - 命令：`xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -sdk iphonesimulator -configuration Debug build`
  - 结果：`BUILD SUCCEEDED`

尚未在本记录中完成：

- 运行时手动确认 opening 过程中那条 macOS toolbar host 约束冲突日志是否彻底消失

## 补充说明

本记录只覆盖这次 `macOSCanvasToolbarHostView.swift` 的 bootstrap constraint fix，不重复展开此前 `split_update_time`、`boardlist_closing_reveal_visibility_guard` 和 `macos_import_drag_return_compile_fix` 的记录内容。
