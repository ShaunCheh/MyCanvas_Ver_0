# 20260413_210650_macos_input_indicator_constraint_fix_record

## 记录说明

本记录基于本次 `macOS` 输入指示器约束冲突修复的实际 `git status`、`git diff --stat`、当前代码状态与构建结果整理，不包含原始 `git diff` 文本。

本次实际只涉及 `1` 个业务文件：

- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- 当前工作区只有 `CanvasInputIndicatorHostView.swift` 处于已修改状态
- `git diff --stat` 显示本次文件级改动规模为 `1 file changed, 81 insertions(+), 31 deletions(-)`
- `macOS` 与 `iOS Simulator` 的构建都已通过
- 运行态手工回归尚未执行，因此本记录不声称“实机输入时已完全看不到约束告警”

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对 `.cursor/plans/输入指示器修复_d8a2babb.plan.md` 的改写
- `macOS` 运行态手工输入回归结论

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
#
# 实际输出:
# 20260413_210650
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取本次输入指示器修复写记录前的真实工作区状态。
git status --short --branch -- \
  "MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift"
#
# 实际输出:
# ## feat/cross-platform-input-indicator
#  M MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计本次输入指示器宿主修复的真实改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift"
#
# 实际输出:
#  .../CanvasInputIndicatorHostView.swift             | 112 +++++++++++++++------
#  1 file changed, 81 insertions(+), 31 deletions(-)
```

## 本次修复的真实目标

这一步不是新增输入语义，而是修正 `macOS` 输入指示器宿主的布局根因：

1. 去掉 `containerView` 依赖 `leading/top/width/height` 常量约束驱动的 `0` 尺寸容器链路。
2. 把 `containerView` 改成和现有 floating chrome 一致的 frame-driven 浮层容器。
3. 让 `preferredContainerSize()` 不再从被 live 约束环境污染的 `stackView.fittingSize` 取值，而是改成从 item 自身测量结果聚合。
4. 对空快照、无 layout context、solver 返回 `nil` 的场景，统一用 `hidden + frame` 表达，而不是回写 `0` 尺寸约束。

## 修改一：宿主容器从 `0` 尺寸约束链改成 frame-driven 浮层

### 修改前

`CanvasInputIndicatorHostView` 的 macOS 分支自己维护一组常量约束来驱动 `containerView`，并把 `stackView` 四边钉死在这个 live 容器里。这样一来，只要外层把宽高写成 `0`，内部内容树就会一起进入受压测量环境。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: CanvasInputIndicatorHostView.init(frame:) / containerLeadingConstraint / containerWidthConstraint
// 功能说明: 修改前 macOS 宿主使用 leading/top/width/height 常量约束来驱动 containerView，stackView 依赖这个 live 容器的约束环境。
final class CanvasInputIndicatorHostView: NSView {
    private let containerView = NSView()
    private let stackView = NSStackView()
    private var containerLeadingConstraint: NSLayoutConstraint!
    private var containerTopConstraint: NSLayoutConstraint!
    private var containerWidthConstraint: NSLayoutConstraint!
    private var containerHeightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // ... 其余初始化代码保持不变 ...

        addSubview(containerView)
        containerView.addSubview(stackView)
        containerLeadingConstraint = containerView.leadingAnchor.constraint(equalTo: leadingAnchor)
        containerTopConstraint = containerView.topAnchor.constraint(equalTo: topAnchor)
        containerWidthConstraint = containerView.widthAnchor.constraint(equalToConstant: 0)
        containerHeightConstraint = containerView.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            containerLeadingConstraint,
            containerTopConstraint,
            containerWidthConstraint,
            containerHeightConstraint,
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }
}
```

### 修改后

现在 `containerView` 与 `stackView` 不再通过那组常量约束驱动，而是转成 frame-driven 浮层；宿主自身仍然铺在 overlay 上，但内部容器的位置和尺寸改由后续 layout solver 解出来的 frame 回写。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: CanvasInputIndicatorHostView.init(frame:)
// 功能说明: 修改后 macOS 宿主不再维护 0 尺寸常量约束链，containerView/stackView 改由 frame 驱动。
final class CanvasInputIndicatorHostView: NSView {
    private let containerView = NSView()
    private let stackView = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // ... 其余初始化代码保持不变 ...

        addSubview(containerView)
        containerView.addSubview(stackView)
        containerView.frame = .zero
        stackView.frame = .zero
    }
}
```

这一改动对应了本次根因修复的第一刀：不再让“显示位置求解”与“内容树尺寸压缩”混在同一组 Auto Layout 常量约束里。

## 修改二：layout 失败分支不再写回 `0` 尺寸约束，统一收口到 `hidden + frame`

### 修改前

`applyLayout()` 只有两种结果：

1. 有解，调用 `updateContainerConstraints(frame)`
2. 无解，调用 `updateContainerConstraints(.zero)`

也就是说，一旦当前快照为空、layout context 未就绪，或者 solver 返回 `nil`，代码就会把 live 容器重新压回 `0x0`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applyLayout() / updateContainerConstraints(_:)
// 功能说明: 修改前所有失败分支都会回写 0 尺寸约束，把 live 内容树再次压回 0x0 容器。
private func applyLayout() {
    guard
        currentSnapshot.isEmpty == false,
        let currentLayoutContext
    else {
        updateContainerConstraints(.zero)
        return
    }

    let preferredSize = preferredContainerSize()
    guard let frame = layoutSolver.resolveHostFrame(
        preferredSize: preferredSize,
        layoutContext: currentLayoutContext
    ) else {
        updateContainerConstraints(.zero)
        return
    }

    updateContainerConstraints(frame)
}

private func updateContainerConstraints(_ frame: CGRect) {
    let standardizedFrame = frame.standardized
    containerLeadingConstraint.constant = standardizedFrame.minX
    containerTopConstraint.constant = standardizedFrame.minY
    containerWidthConstraint.constant = max(0, standardizedFrame.width)
    containerHeightConstraint.constant = max(0, standardizedFrame.height)
}
```

### 修改后

现在 `applyLayout()` 先判断快照、再判断测量结果、再判断 layout context、最后才交给 solver；失败分支统一走 `hideContainer(...)`，可见态则走 `updateContainerFrame(_:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applyLayout() / hideContainer(resetFrame:usingPreferredSize:) / updateContainerFrame(_:)
// 功能说明: 修改后 layout 失败分支不再写回 0 尺寸约束，而是改成 hidden + frame 管理，避免重新把 live 内容树压回冲突环境。
private func applyLayout() {
    guard currentSnapshot.isEmpty == false else {
        hideContainer(resetFrame: true)
        return
    }

    let preferredSize = preferredContainerSize()
    guard preferredSize.width > 0, preferredSize.height > 0 else {
        hideContainer(resetFrame: true)
        return
    }

    guard let currentLayoutContext else {
        hideContainer(usingPreferredSize: preferredSize)
        return
    }

    guard let frame = layoutSolver.resolveHostFrame(
        preferredSize: preferredSize,
        layoutContext: currentLayoutContext
    ) else {
        hideContainer(usingPreferredSize: preferredSize)
        return
    }

    containerView.isHidden = false
    isHidden = false
    updateContainerFrame(frame)
}

private func hideContainer(
    resetFrame: Bool = false,
    usingPreferredSize preferredSize: CGSize? = nil
) {
    containerView.isHidden = true
    isHidden = true

    guard
        resetFrame == false,
        let preferredSize,
        preferredSize.width > 0,
        preferredSize.height > 0
    else {
        updateContainerFrame(.zero)
        return
    }

    // Keep a legal non-zero content frame while hidden so AppKit never
    // re-measures the live stack inside a 0x0 parent container.
    updateContainerFrame(
        CGRect(origin: .zero, size: preferredSize)
    )
}

private func updateContainerFrame(_ frame: CGRect) {
    let standardizedFrame = frame.standardized
    let sanitizedSize = CanvasChromeLayoutGeometry.sanitizedSize(
        standardizedFrame.size
    )
    containerView.frame = CGRect(
        x: standardizedFrame.minX,
        y: standardizedFrame.minY,
        width: sanitizedSize.width,
        height: sanitizedSize.height
    )
    stackView.frame = CGRect(origin: .zero, size: sanitizedSize)
}
```

这里的关键差异不是“简单把约束删掉”，而是把“无解态如何表达”从 `0` 尺寸约束改成显式 `hidden + frame`，从根上断开原先的闭环。

## 修改三：首选尺寸测量从 live `stackView.fittingSize` 改成 item 聚合测量

### 修改前

`preferredContainerSize()` 直接读取 `stackView.fittingSize`，而 item view 自己没有提供独立测量 helper。这意味着首选尺寸会直接受 live 栈视图当前约束环境影响。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: preferredContainerSize() / macOSCanvasInputIndicatorItemView.apply(text:)
// 功能说明: 修改前宿主直接读取 stackView.fittingSize，item view 没有单独暴露自然尺寸测量入口。
private func preferredContainerSize() -> CGSize {
    CanvasChromeLayoutGeometry.sanitizedSize(stackView.fittingSize)
}

private final class macOSCanvasInputIndicatorItemView: NSView {
    func apply(text: String) {
        label.stringValue = text
        setAccessibilityLabel(text)
    }
}
```

### 修改后

现在宿主先从 `currentSnapshot.items` 找到对应的 item view，再按每个 item 的自然尺寸聚合出最大宽度和总高度；item view 新增了 `measuredSize()` 作为单独的测量入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: preferredContainerSize() / macOSCanvasInputIndicatorItemView.measuredSize()
// 功能说明: 修改后宿主不再依赖 live stack fitting，而是按每个胶囊项的自然尺寸做聚合测量。
private func preferredContainerSize() -> CGSize {
    let itemSizes = currentSnapshot.items.compactMap { item in
        itemViewsByID[item.id]?.measuredSize()
    }
    guard itemSizes.isEmpty == false else {
        return .zero
    }

    let maximumWidth = itemSizes.map(\.width).max() ?? 0
    let totalHeight = itemSizes.reduce(CGFloat(0)) { partialResult, size in
        partialResult + size.height
    }
    let spacingHeight = CGFloat(max(itemSizes.count - 1, 0)) * Layout.itemSpacing
    return CanvasChromeLayoutGeometry.sanitizedSize(
        CGSize(
            width: maximumWidth,
            height: totalHeight + spacingHeight
        )
    )
}

private final class macOSCanvasInputIndicatorItemView: NSView {
    func apply(text: String) {
        label.stringValue = text
        setAccessibilityLabel(text)
    }

    func measuredSize() -> CGSize {
        let labelSize = CanvasChromeLayoutGeometry.sanitizedSize(label.fittingSize)
        return CanvasChromeLayoutGeometry.sanitizedSize(
            CGSize(
                width: labelSize.width + Layout.horizontalInset * 2,
                height: labelSize.height + Layout.verticalInset * 2
            )
        )
    }
}
```

这一改动的目的，是把“内容自然尺寸测量”与“宿主 frame 落位”解耦；solver 继续只负责位置求解，不再顺带承担 live 内容树的测量稳定性。

## 验证结果

### `macOS` 构建

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build
# 功能说明: 验证共享宿主视图重构后 macOS 目标仍可编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build
#
# 实际结果:
# ** BUILD SUCCEEDED **
```

### `iOS Simulator` 构建

首次尝试选了本机不存在的模拟器名，命令没有进入真正构建阶段：

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build
# 功能说明: 首次 iOS 模拟器验证使用了本机不存在的设备名，因此 destination 解析失败。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" build
#
# 实际结果:
# xcodebuild: error: Unable to find a device matching the provided destination specifier:
#   { platform:iOS Simulator, OS:latest, name:iPad Pro 13-inch (M4) }
```

随后改用本机实际可用的 `iPad Pro 13-inch (M5)`，构建通过：

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1" build
# 功能说明: 重新使用本机可用的 iPad 模拟器验证共享宿主文件在 iOS 目标上仍可编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=26.1" build
#
# 实际结果:
# ** BUILD SUCCEEDED **
```

额外检查结果：

- `ReadLints` 针对 `CanvasInputIndicatorHostView.swift` 未发现新增 linter 错误
- 当前 `git status` 仅显示本次修改的 `CanvasInputIndicatorHostView.swift` 处于已修改状态

## 当前结论

这次改动已经把 `macOS` 输入指示器宿主的根因链路从：

- `0` 尺寸约束容器
- live `stackView.fittingSize`
- solver 无解后再次回写 `0x0`

改成了：

- frame-driven `containerView`
- item 自然尺寸聚合测量
- `hidden + frame` 失败态表达

从代码结构上，已经对齐这次修复计划里要求的根因方案；但运行态是否完全消除了 `Conflicting constraints detected`，仍需要后续手工输入回归来最终确认。
