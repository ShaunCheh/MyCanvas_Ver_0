# 20260413_214155_ios_input_indicator_animation_fix_record

## 记录说明

本记录基于本次 `iOS` 输入胶囊动画根因修复的实际 `git status`、`git diff --stat`、当前代码状态与构建结果整理，不包含原始 `git diff` 文本。

本次业务代码实际只涉及 `1` 个文件：

- `MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift`

写入本记录前，工作区里还存在一个非业务代码的辅助修改：

- `.cursor/plans/ios输入胶囊修复_d3e05468.plan.md`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前位于 `feat/cross-platform-input-indicator`
- 当前工作区有 `2` 处修改：`1` 个业务代码文件、`1` 个计划 `.md` 文件
- `git diff --stat -- "MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift"` 显示本次代码改动规模为 `1 file changed, 129 insertions(+), 33 deletions(-)`
- `macOS` 与 `iPhone Simulator` 的 `xcodebuild build` 均已通过
- 本记录写入时，`iPhone` 端手工回归尚未执行，因此本记录不声称“从左上角飞入问题已在设备上最终确认消失”

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对 `.cursor/plans/ios输入胶囊修复_d3e05468.plan.md` 的内容改写
- `iPhone` 真机/模拟器手工回归结论

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date +"%Y%m%d_%H%M%S"
#
# 实际输出:
# 20260413_214155
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 提取写记录前的真实工作区状态，区分业务代码改动与辅助计划文件改动。
git status --short --branch
#
# 实际输出:
# ## feat/cross-platform-input-indicator
#  M ".cursor/plans/ios输入胶囊修复_d3e05468.plan.md"
#  M MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --stat
# 功能说明: 统计本次 iOS 输入胶囊宿主修复的真实代码改动规模。
git diff --stat -- \
  "MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift"
#
# 实际输出:
#  .../CanvasInputIndicatorHostView.swift             | 162 ++++++++++++++++-----
#  1 file changed, 129 insertions(+), 33 deletions(-)
```

## 本次修复的真实目标

这一步不是新增输入语义，而是修正 `iOS` 输入胶囊宿主的动画根因：

1. 不再让 `containerView` 的落位和胶囊 item 的入场动画混在同一个 `UIView.animate` 事务里。
2. 让宿主先无动画稳定到底部目标位置，再播放 item 自身的 `alpha + transform` 动画。
3. 保留“新胶囊从底部冒出、旧胶囊向上推移”的栈式视觉，而不是简单把左上角飞入问题改成“没有动画”。
4. 让快速连续输入时，旧胶囊的位移动画基于当前视觉位置衔接，而不是基于静态 frame 生硬跳变。

## 修改一：`updateLayout(...)` 不再把宿主落位直接暴露为可动画的布局插值

### 修改前

`updateLayout(layoutContext:)` 在收到 layout context 后，直接调用 `applyLayout()` 再 `layoutIfNeeded()`。当 `applySnapshot(_:animated:)` 后续又把这两步包进 `UIView.animate` 时，宿主容器就可能从默认左上角状态被整体插值到底部。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: updateLayout(layoutContext:) / applyLayout()
// 功能说明: 修改前 iOS 宿主收到 layout context 后只负责刷新约束，后续若落在动画事务中，containerView 的整体位移也会被动画化。
func updateLayout(layoutContext: CanvasChromeLayoutContext) {
    currentLayoutContext = layoutContext
    applyLayout()
    layoutIfNeeded()
}

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
```

### 修改后

现在 `applyLayout()` 改为显式返回是否拿到合法布局结果，并引入 `commitResolvedLayout()` 统一用 `UIView.performWithoutAnimation` 提交宿主约束，再由 `setHostHidden(_:)` 决定是否显示 host。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: updateLayout(layoutContext:) / applyLayout() / commitResolvedLayout() / setHostHidden(_:)
// 功能说明: 修改后宿主约束提交被显式收口为“无动画落位”，把 containerView 的位置变化从 item 动画事务里隔离出去。
func updateLayout(layoutContext: CanvasChromeLayoutContext) {
    currentLayoutContext = layoutContext
    let didResolveLayout = commitResolvedLayout()
    setHostHidden(currentSnapshot.isEmpty || didResolveLayout == false)
}

@discardableResult
private func applyLayout() -> Bool {
    guard
        currentSnapshot.isEmpty == false,
        let currentLayoutContext
    else {
        updateContainerConstraints(.zero)
        return false
    }

    let preferredSize = preferredContainerSize()
    guard let frame = layoutSolver.resolveHostFrame(
        preferredSize: preferredSize,
        layoutContext: currentLayoutContext
    ) else {
        updateContainerConstraints(.zero)
        return false
    }

    updateContainerConstraints(frame)
    return true
}

@discardableResult
private func commitResolvedLayout() -> Bool {
    let didResolveLayout = applyLayout()
    UIView.performWithoutAnimation {
        self.layoutIfNeeded()
    }
    return didResolveLayout
}

private func setHostHidden(_ hidden: Bool) {
    containerView.isHidden = hidden
    isHidden = hidden
}
```

这一改动对应的根因修复点是：把“宿主落位”从可动画事务里拆出来，让它始终先到最终底部位置。

## 修改二：`applySnapshot(...)` 改成“先重建、再落位、后动画 item”的三段式流程

### 修改前

旧实现里，`applySnapshot(_:animated:)` 会先重建 `stackView`，然后在同一个 `UIView.animate` 里同时：

- 把新胶囊 `alpha` 从 `0` 动到目标值
- 把胶囊 `transform` 还原到 `.identity`
- 调 `applyLayout()` / `layoutIfNeeded()`

这意味着宿主 `containerView` 和 item 动画绑死在一起，左上角飞入问题就来自这里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applySnapshot(_:animated:)
// 功能说明: 修改前 applySnapshot 在同一动画事务里同时推进宿主布局和 item 入场动画，导致宿主整体从默认位置被插值到底部。
private func applySnapshot(
    _ snapshot: CanvasInputIndicatorQueueSnapshot,
    animated: Bool
) {
    // ... 省略移除旧 item、创建新 item、重建 arrangedSubviews ...

    currentSnapshot = snapshot
    containerView.isHidden = false
    isHidden = false

    let applyVisualState = {
        for item in snapshot.items {
            guard let view = self.itemViewsByID[item.id] else {
                continue
            }
            view.alpha = item.opacity
            view.transform = .identity
        }
        self.applyLayout()
        self.layoutIfNeeded()
    }

    if animated {
        UIView.animate(
            withDuration: Layout.animationDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            applyVisualState()
        }
    } else {
        applyVisualState()
    }
}
```

### 修改后

现在 `applySnapshot(_:animated:)` 改成三段式：

1. 先采样旧视觉 frame、重建 `stackView`
2. 再无动画提交宿主最终底部布局
3. 最后只对 item 做入场/上推动画

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applySnapshot(_:animated:) / rebuildArrangedSubviews(using:) / applyFinalVisualState(for:)
// 功能说明: 修改后宿主先稳定落位到底部，再只动画 item 视觉状态，切断左上角飞入轨迹。
private func applySnapshot(
    _ snapshot: CanvasInputIndicatorQueueSnapshot,
    animated: Bool
) {
    layoutIfNeeded()
    let previousFramesByID = currentVisualFramesByID()
    let previousIDs = Set(currentSnapshot.items.map(\.id))
    let nextIDs = Set(snapshot.items.map(\.id))
    let insertedIDs = nextIDs.subtracting(previousIDs)
    let removedIDs = previousIDs.subtracting(nextIDs)
    removedIDs.forEach(removeItemView)

    // ... 省略空快照与 item 构建逻辑 ...

    rebuildArrangedSubviews(using: orderedViews)
    currentSnapshot = snapshot

    guard commitResolvedLayout() else {
        applyFinalVisualState(for: snapshot)
        setHostHidden(true)
        return
    }

    setHostHidden(false)

    guard animated else {
        applyFinalVisualState(for: snapshot)
        return
    }

    prepareAnimatedVisualState(
        for: snapshot,
        insertedIDs: insertedIDs,
        previousFramesByID: previousFramesByID
    )

    UIView.animate(
        withDuration: Layout.animationDuration,
        delay: 0,
        options: [.curveEaseOut, .beginFromCurrentState]
    ) {
        self.applyFinalVisualState(for: snapshot)
    }
}

private func rebuildArrangedSubviews(
    using orderedViews: [iOSCanvasInputIndicatorItemView]
) {
    stackView.arrangedSubviews.forEach { arrangedSubview in
        stackView.removeArrangedSubview(arrangedSubview)
    }
    orderedViews.forEach { view in
        stackView.addArrangedSubview(view)
    }
}

private func applyFinalVisualState(
    for snapshot: CanvasInputIndicatorQueueSnapshot
) {
    for item in snapshot.items {
        guard let view = itemViewsByID[item.id] else {
            continue
        }
        view.alpha = item.opacity
        view.transform = .identity
    }
}
```

这一改动的结果，是宿主容器不再参与入场动画；真正被动画的只有胶囊 item 自己。

## 修改三：补 item 级 FLIP，上推动画不再依赖宿主位移“顺带产生”

### 修改前

旧实现里，新胶囊只有固定的 `translationY` 初始位移，旧胶囊没有独立的位移补偿逻辑。之前之所以还能“看起来有点往上推”，很大程度是宿主整体位置也在动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applySnapshot(_:animated:)
// 功能说明: 修改前只有新插入 item 带固定 insertionTranslationY，旧 item 没有基于旧位置到新位置的独立位移补偿。
let newView = iOSCanvasInputIndicatorItemView()
newView.alpha = 0
newView.transform = CGAffineTransform(
    translationX: 0,
    y: Layout.insertionTranslationY
)

// ...

for item in snapshot.items {
    guard let view = self.itemViewsByID[item.id] else {
        continue
    }
    view.alpha = item.opacity
    view.transform = .identity
}
```

### 修改后

现在为 iOS host 增加了 `currentVisualFramesByID()` / `currentVisualFrame(for:)` / `prepareAnimatedVisualState(...)` 这组 helper：

- 先读旧 item 当前视觉 frame
- 新布局落定后计算旧 item 的 `deltaY`
- 新 item 继续使用 `Layout.insertionTranslationY`
- 旧 item 则先带着 `deltaY` 呈现，再在动画里回到 `.identity`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: prepareAnimatedVisualState(for:insertedIDs:previousFramesByID:) / currentVisualFramesByID() / currentVisualFrame(for:)
// 功能说明: 修改后 iOS 输入胶囊使用 item 级 FLIP 位移动画，保留“旧胶囊上推”的视觉，同时避免宿主整体位移。
private func prepareAnimatedVisualState(
    for snapshot: CanvasInputIndicatorQueueSnapshot,
    insertedIDs: Set<UUID>,
    previousFramesByID: [UUID: CGRect]
) {
    for item in snapshot.items {
        guard let view = itemViewsByID[item.id] else {
            continue
        }

        if insertedIDs.contains(item.id) {
            view.alpha = 0
            view.transform = CGAffineTransform(
                translationX: 0,
                y: Layout.insertionTranslationY
            )
            continue
        }

        guard let previousFrame = previousFramesByID[item.id] else {
            view.transform = .identity
            continue
        }

        let deltaY = previousFrame.minY - view.frame.minY
        if abs(deltaY) > .ulpOfOne {
            view.transform = CGAffineTransform(
                translationX: 0,
                y: deltaY
            )
        } else {
            view.transform = .identity
        }
    }
}

private func currentVisualFramesByID() -> [UUID: CGRect] {
    itemViewsByID.reduce(into: [:]) { partialResult, entry in
        guard let currentFrame = currentVisualFrame(for: entry.value) else {
            return
        }
        partialResult[entry.key] = currentFrame
    }
}

private func currentVisualFrame(for view: UIView) -> CGRect? {
    if let animatedFrame = view.layer.presentation()?.frame,
       let sanitizedAnimatedFrame = CanvasChromeLayoutGeometry.sanitizedRect(
           animatedFrame
       )
    {
        return sanitizedAnimatedFrame
    }

    return CanvasChromeLayoutGeometry.sanitizedRect(view.frame)
}
```

这里的关键点是：旧胶囊上推动画现在来自 item 自己的位移补偿，而不是依赖宿主容器一起运动。

## 修改四：空快照与无 layout context 场景改成显式 hidden 流程

### 修改前

空快照分支只是清空 `stackView` 后隐藏宿主，并继续调用 `applyLayout()`；如果当前没有合法 layout context，宿主状态和 item 视觉状态的同步边界并不明确。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applySnapshot(_:animated:)
// 功能说明: 修改前空快照分支只是清空并隐藏宿主，布局提交与显隐决策仍散落在 applySnapshot 内。
if snapshot.isEmpty {
    currentSnapshot = snapshot
    stackView.arrangedSubviews.forEach { arrangedSubview in
        stackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }
    itemViewsByID.removeAll()
    containerView.isHidden = true
    isHidden = true
    applyLayout()
    return
}
```

### 修改后

现在空快照和“无合法布局解”的处理都收敛到 `setHostHidden(_:) + commitResolvedLayout()` 上，host 的显隐路径更统一。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/InputIndicator/CanvasInputIndicatorHostView.swift
// 函数名/符号名: applySnapshot(_:animated:) / setHostHidden(_:)
// 功能说明: 修改后空快照与无布局解场景都走统一的 hidden 路径，避免宿主处于“布局未定但已可见”的中间态。
if snapshot.isEmpty {
    currentSnapshot = snapshot
    stackView.arrangedSubviews.forEach { arrangedSubview in
        stackView.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }
    itemViewsByID.removeAll()
    setHostHidden(true)
    _ = commitResolvedLayout()
    return
}

guard commitResolvedLayout() else {
    applyFinalVisualState(for: snapshot)
    setHostHidden(true)
    return
}
```

这一改动的意义在于：host 是否可见不再依赖调用方的时机碰运气，而是由“当前 snapshot + 当前布局解是否有效”共同决定。

## 验证结果

### `macOS` 构建

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build
# 功能说明: 验证共享输入指示器宿主在 macOS 目标上仍可编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" build
#
# 实际结果:
# ** BUILD SUCCEEDED **
```

### `iPhone Simulator` 构建

```bash
# 文件路径: 系统命令 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
# 函数名/命令名: xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" build
# 功能说明: 验证本次 iOS 输入胶囊动画修复在 iPhone 模拟器目标上可编译。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=iOS Simulator,name=iPhone 17,OS=26.1" build
#
# 实际结果:
# ** BUILD SUCCEEDED **
```

额外检查结果：

- `ReadLints` 针对 `CanvasInputIndicatorHostView.swift` 未发现新增 linter 错误
- 当前业务代码修改仍只落在 `CanvasInputIndicatorHostView.swift`
- 当前工作区同时存在辅助计划文件 `.cursor/plans/ios输入胶囊修复_d3e05468.plan.md` 的修改

## 当前结论

这次改动已经把 `iOS` 输入胶囊的动画路径从：

- 宿主落位与 item 入场混在同一动画事务里
- 宿主从默认左上角状态插值到底部
- 旧胶囊上推动画部分依赖宿主整体位移

改成了：

- 宿主先无动画落位到底部
- item 再独立播放入场/渐隐动画
- 旧胶囊使用 item 级 FLIP 位移补偿来维持上推效果

从代码结构上，这已经对齐了本次根因方案；但最终是否完全消除了“从左上角飞到底部”的视觉问题，仍需要后续 `iPhone` 端手工回归来最终确认。
