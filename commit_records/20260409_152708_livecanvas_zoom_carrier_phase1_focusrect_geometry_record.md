# 20260409_152708_livecanvas_zoom_carrier_phase1_focusrect_geometry_record

## 记录范围

- 记录内容：`livecanvas_zoom_carrier` 计划 `Phase 1` 的实施记录。
- 记录目标：先把 boardlist 与转场链路中的几何语义统一成 `focusRect + cardRect`，为后续 `liveCanvas carrier` 真正接管 opening / closing 铺平边界。
- 记录依据：
  - 系统命令 `date +%Y%m%d_%H%M%S` 返回：`20260409_152708`
  - 当前工作树 `git status --short -- <Phase 1 相关文件>`
  - 当前工作树 `git diff -- <Phase 1 相关文件>`
  - 修改后的源码内容
- 对应计划文件：`.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md`
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionFocusRectResolver.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift`
  - `MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift`
- 本记录不包含：
  - `Phase 2` 的 `CanvasTransitionLiveContentProviding` 边界接入
  - `Phase 3` / `Phase 4` 的 `iOSLiveCanvasCarrier` 实现
  - 对 `.cursor/plans/livecanvas_zoom_carrier_43f1e1e5.plan.md` 的时序补充
  - git commit

## 问题背景

- 在本轮修改前，转场几何的语义是不对称的：
  - source 侧有 `cardRect` 与 `previewRect`
  - target 侧只有 `cardRect`
- 与此同时，`snapshotShell` carrier 在 opening / closing 两端都只消费 `cardRect`，没有实际使用 source 侧已有的缩略图区域。
- 结果是：
  - opening 仍然从整张卡片放大
  - closing 仍然向整张卡片缩回
  - 即使 source 侧已经采到了缩略图区域，target 侧和 carrier 也无法形成对称闭环
- `Phase 1` 的目标不是马上做 live reparent，而是先把“缩略图锚点”从零散字段升级成统一契约，并让现有 snapshot carrier 优先按这个契约消费。

## 修改一：共享转场几何从 `previewRect` 升级为对称的 `focusRect + cardRect`

### 修改前

- `BoardListCanvasTransitionSourceGeometry` 使用 `previewRect` 表示 source 侧缩略图区域。
- `BoardListCanvasTransitionTargetGeometry` 只有 `cardRect`，没有对称的缩略图锚点。
- 两端都没有统一的“优先缩略图、兜底整卡”的访问入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift
// 函数名/符号名: BoardListCanvasTransitionSourceGeometry / BoardListCanvasTransitionTargetGeometry
// 功能说明: 修改前 source 侧使用 previewRect，target 侧只有 cardRect；缩略图锚点没有统一语义，也没有 preferredRect 这种消费入口。
struct BoardListCanvasTransitionSourceGeometry: Hashable, Sendable {
    var cardRect: CGRect?
    var previewRect: CGRect?

    init(
        cardRect: CGRect? = nil,
        previewRect: CGRect? = nil
    ) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
        self.previewRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            previewRect
        )
    }
}

struct BoardListCanvasTransitionTargetGeometry: Hashable, Sendable {
    var cardRect: CGRect?

    init(cardRect: CGRect? = nil) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
    }
}
```

### 修改后

- `previewRect` 正式升级为统一语义的 `focusRect`。
- `BoardListCanvasTransitionTargetGeometry` 同步新增 `focusRect`，source / target 结构对称。
- 两边都新增 `preferredRect`，表达“优先 `focusRect`，兜底 `cardRect`”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift
// 函数名/符号名: BoardListCanvasTransitionSourceGeometry / BoardListCanvasTransitionTargetGeometry
// 功能说明: 修改后 source 与 target 都具备 focusRect + cardRect，对外统一通过 preferredRect 表达“优先缩略图、兜底整卡”的转场锚点。
struct BoardListCanvasTransitionSourceGeometry: Hashable, Sendable {
    var cardRect: CGRect?
    var focusRect: CGRect?

    init(
        cardRect: CGRect? = nil,
        focusRect: CGRect? = nil
    ) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
        self.focusRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            focusRect
        )
    }

    var preferredRect: CGRect? {
        focusRect ?? cardRect
    }
}

struct BoardListCanvasTransitionTargetGeometry: Hashable, Sendable {
    var cardRect: CGRect?
    var focusRect: CGRect?

    init(
        cardRect: CGRect? = nil,
        focusRect: CGRect? = nil
    ) {
        self.cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            cardRect
        )
        self.focusRect = BoardListCanvasTransitionGeometry.sanitizedRect(
            focusRect
        )
    }

    var preferredRect: CGRect? {
        focusRect ?? cardRect
    }
}
```

## 修改二：新增共享 `focusRect` fallback 解析器，统一 grid / list / placeholder 几何规则

### 修改前

- 项目里不存在一份共享的 `focusRect` fallback 解析器。
- 当 cell / item 当前不可见时，BoardList 只能退回 `transitionCardRect(...)`，无法继续推导缩略图区域。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionFocusRectResolver.swift
// 函数名/符号名: （新增文件，修改前不存在）
// 功能说明: 修改前没有统一的 focusRect fallback 解析器，不可见项只能退回整卡 cardRect。
// 无
```

### 修改后

- 新增 `BoardListCanvasTransitionFocusRectResolver`。
- 它统一承载：
  - `grid` 模式下 preview 区域
  - `list` 模式下 preview 区域
  - `placeholder grid` 图标区域
  - `placeholder list` 图标区域
- 这样 source/target 的 fallback 逻辑不用再散落在 iOS/macOS 两套 BoardList 控制器里。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionFocusRectResolver.swift
// 函数名/符号名: BoardListCanvasTransitionFocusRectResolver.focusRect(in:displayMode:isPlaceholder:)
// 功能说明: 修改后共享 resolver 统一根据 displayMode 与 placeholder 状态推导 focusRect，为不可见 cell/item 的 source/target fallback 提供稳定几何。
enum BoardListCanvasTransitionFocusRectResolver {
    private enum Layout {
        static let previewInset: CGFloat = 12
        static let previewGridHeight: CGFloat = 120
        static let previewListSize = CGSize(width: 72, height: 72)
        static let placeholderIconSize = CGSize(width: 22, height: 22)
        static let placeholderListLeadingInset: CGFloat = 24
    }

    static func focusRect(
        in cardRect: CGRect?,
        displayMode: BoardListDisplayMode,
        isPlaceholder: Bool
    ) -> CGRect? {
        guard
            let cardRect = BoardListCanvasTransitionGeometry.sanitizedRect(
                cardRect
            )
        else {
            return nil
        }

        let rawRect: CGRect
        switch (isPlaceholder, displayMode) {
        case (false, .grid):
            rawRect = CGRect(
                x: cardRect.minX + Layout.previewInset,
                y: cardRect.minY + Layout.previewInset,
                width: cardRect.width - (Layout.previewInset * 2),
                height: Layout.previewGridHeight
            )
        case (false, .list):
            rawRect = CGRect(
                x: cardRect.minX + Layout.previewInset,
                y: cardRect.midY - (Layout.previewListSize.height / 2),
                width: Layout.previewListSize.width,
                height: Layout.previewListSize.height
            )
        case (true, .grid):
            rawRect = CGRect(
                x: cardRect.midX - (Layout.placeholderIconSize.width / 2),
                y: cardRect.midY - (Layout.placeholderIconSize.height / 2),
                width: Layout.placeholderIconSize.width,
                height: Layout.placeholderIconSize.height
            )
        case (true, .list):
            rawRect = CGRect(
                x: cardRect.minX + Layout.placeholderListLeadingInset,
                y: cardRect.midY - (Layout.placeholderIconSize.height / 2),
                width: Layout.placeholderIconSize.width,
                height: Layout.placeholderIconSize.height
            )
        }

        return BoardListCanvasTransitionGeometry.sanitizedRect(rawRect)
    }
}
```

## 修改三：iOS / macOS cell 与 item 改为直接产出 `focusRect`

### 修改前

- `iOSBoardCollectionViewCell.transitionGeometry(in:)` / `macOSBoardCollectionItem.transitionGeometry(in:)` 会先返回 `cardRect`，再额外带一个 `previewRect`。
- 当 `previewView.isHidden == true` 时，`previewRect` 就直接是 `nil`，placeholder icon 不会形成正式锚点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: transitionGeometry(in:)
// 功能说明: 修改前 iOS cell 只在 previewView 可见时输出 previewRect，placeholder icon 不参与转场锚点建模。
func transitionGeometry(
    in coordinateSpaceView: UIView
) -> BoardListCanvasTransitionSourceGeometry {
    contentView.layoutIfNeeded()
    let cardRect = coordinateSpaceView.convert(
        contentView.bounds,
        from: contentView
    )
    let previewRect: CGRect?
    if previewView.isHidden {
        previewRect = nil
    } else {
        previewRect = coordinateSpaceView.convert(
            previewView.bounds,
            from: previewView
        )
    }

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        previewRect: previewRect
    )
}
```

### 修改后

- iOS / macOS 两端都统一改成返回 `focusRect`。
- 若 `previewView` 可见，则 `focusRect` 指向缩略图区域。
- 若 `previewView` 隐藏但 `placeholderIconView` 可见，则 `focusRect` 指向占位 icon 区域。
- 这样 placeholder 也正式进入转场几何模型，不再只是“没有 previewRect 的特殊情况”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/符号名: transitionGeometry(in:) / transitionFocusRect(in:)
// 功能说明: 修改后 iOS cell 把缩略图或 placeholder icon 统一抽象成 focusRect，并作为 sourceGeometry 的正式字段返回。
func transitionGeometry(
    in coordinateSpaceView: UIView
) -> BoardListCanvasTransitionSourceGeometry {
    contentView.layoutIfNeeded()
    let cardRect = coordinateSpaceView.convert(
        contentView.bounds,
        from: contentView
    )

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(in: coordinateSpaceView)
    )
}

private func transitionFocusRect(
    in coordinateSpaceView: UIView
) -> CGRect? {
    if previewView.isHidden == false {
        return coordinateSpaceView.convert(
            previewView.bounds,
            from: previewView
        )
    }

    if placeholderIconView.isHidden == false {
        return coordinateSpaceView.convert(
            placeholderIconView.bounds,
            from: placeholderIconView
        )
    }

    return nil
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/符号名: transitionGeometry(in:) / transitionFocusRect(in:)
// 功能说明: 修改后 macOS item 与 iOS 对称，也改成优先返回 preview / placeholder icon 的 focusRect。
func transitionGeometry(
    in coordinateSpaceView: NSView
) -> BoardListCanvasTransitionSourceGeometry {
    view.layoutSubtreeIfNeeded()
    let cardRect = coordinateSpaceView.convert(
        view.bounds,
        from: view
    )

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(in: coordinateSpaceView)
    )
}

private func transitionFocusRect(
    in coordinateSpaceView: NSView
) -> CGRect? {
    if previewView.isHidden == false {
        return coordinateSpaceView.convert(
            previewView.bounds,
            from: previewView
        )
    }

    if placeholderIconView.isHidden == false {
        return coordinateSpaceView.convert(
            placeholderIconView.bounds,
            from: placeholderIconView
        )
    }

    return nil
}
```

## 修改四：iOS / macOS BoardList fallback 也能为不可见项推导 `focusRect`

### 修改前

- 当 cell / item 当前不可见时：
  - source 侧 fallback 只会返回 `transitionCardRect(...)`
  - target 侧 fallback 也只会返回 `cardRect`
- 也就是说，一旦目标板不在当前可见 cell 范围内，closing 就会退回整卡几何，无法保持“缩略图锚点”的语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(at:) / resolveTransitionTargetGeometry(for:)
// 功能说明: 修改前 iOS BoardList 对不可见项的 source/target fallback 都只返回整卡 cardRect，focus 锚点在 fallback 路径里会丢失。
private func transitionSourceGeometry(
    at indexPath: IndexPath
) -> BoardListCanvasTransitionSourceGeometry {
    collectionView.layoutIfNeeded()
    if let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell {
        return cell.transitionGeometry(in: view)
    }

    return BoardListCanvasTransitionSourceGeometry(
        cardRect: transitionCardRect(at: indexPath)
    )
}

private func resolveTransitionTargetGeometry(
    for boardID: UUID
) -> BoardListClosingTargetPreparationResult? {
    // ... 省略 indexPath 解析 ...
    if let cell = collectionView.cellForItem(
        at: resolvedIndexPath
    ) as? iOSBoardCollectionViewCell {
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: cell.transitionGeometry(in: view).cardRect
        )
    } else {
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: transitionCardRect(at: resolvedIndexPath)
        )
    }
    // ... 省略其余逻辑 ...
}
```

### 修改后

- iOS / macOS 两端都新增了基于 entry、displayMode 和 cardRect 的 `transitionFocusRect(...)` helper。
- 可见 cell / item 路径会直接透传 `cellGeometry.focusRect`。
- 不可见 fallback 路径会基于共享 resolver 推导出 `focusRect`，不再只剩 `cardRect`。
- iOS target-ready trace 也同步补了 `hasFocusRect`，便于后续确认 closing 是否真正命中缩略图锚点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(at:) / resolveTransitionTargetGeometry(for:) / transitionFocusRect(at:cardRect:)
// 功能说明: 修改后 iOS BoardList 无论 cell 可见还是不可见，都能维持 focusRect 语义；target-ready 日志也能直接显示 hasFocusRect。
private func transitionSourceGeometry(
    at indexPath: IndexPath
) -> BoardListCanvasTransitionSourceGeometry {
    collectionView.layoutIfNeeded()
    if let cell = collectionView.cellForItem(at: indexPath) as? iOSBoardCollectionViewCell {
        return cell.transitionGeometry(in: view)
    }

    let cardRect = transitionCardRect(at: indexPath)
    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(
            at: indexPath,
            cardRect: cardRect
        )
    )
}

private func resolveTransitionTargetGeometry(
    for boardID: UUID
) -> BoardListClosingTargetPreparationResult? {
    // ... 省略 indexPath 解析 ...
    if let cell = collectionView.cellForItem(
        at: resolvedIndexPath
    ) as? iOSBoardCollectionViewCell {
        let cellGeometry = cell.transitionGeometry(in: view)
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: cellGeometry.cardRect,
            focusRect: cellGeometry.focusRect
        )
        usedFallbackGeometry = false
    } else {
        let cardRect = transitionCardRect(at: resolvedIndexPath)
        geometry = BoardListCanvasTransitionTargetGeometry(
            cardRect: cardRect,
            focusRect: transitionFocusRect(
                at: resolvedIndexPath,
                cardRect: cardRect
            )
        )
        usedFallbackGeometry = true
    }

    logClosingTransitionTiming(
        phase: "resolveTransitionTargetGeometry",
        extra:
            "boardID=\(boardID.uuidString) " +
            "usedFallbackGeometry=\(usedFallbackGeometry) " +
            "hasCardRect=\(geometry.cardRect != nil) " +
            "hasFocusRect=\(geometry.focusRect != nil)"
    )
    // ... 省略其余逻辑 ...
}

private func transitionFocusRect(
    at indexPath: IndexPath,
    cardRect: CGRect? = nil
) -> CGRect? {
    guard let entry = entry(at: indexPath) else {
        return nil
    }

    return BoardListCanvasTransitionFocusRectResolver.focusRect(
        in: cardRect ?? transitionCardRect(at: indexPath),
        displayMode: displayMode,
        isPlaceholder: entry.isPlaceholder
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift
// 函数名/符号名: transitionSourceGeometry(at:) / transitionTargetGeometry(for:) / transitionFocusRect(at:cardRect:)
// 功能说明: 修改后 macOS BoardList 对可见项与 fallback 项也统一维持 focusRect + cardRect，对称跟上 iOS 侧的几何契约。
private func transitionSourceGeometry(
    at indexPath: IndexPath
) -> BoardListCanvasTransitionSourceGeometry {
    collectionView.layoutSubtreeIfNeeded()
    if let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem {
        return item.transitionGeometry(in: view)
    }

    let cardRect = transitionCardRect(at: indexPath)
    return BoardListCanvasTransitionSourceGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(
            at: indexPath,
            cardRect: cardRect
        )
    )
}

private func transitionTargetGeometry(
    for boardID: UUID
) -> BoardListCanvasTransitionTargetGeometry {
    // ... 省略 indexPath 解析 ...
    if let item = collectionView.item(at: indexPath) as? macOSBoardCollectionItem {
        let itemGeometry = item.transitionGeometry(in: view)
        return BoardListCanvasTransitionTargetGeometry(
            cardRect: itemGeometry.cardRect,
            focusRect: itemGeometry.focusRect
        )
    }

    let cardRect = transitionCardRect(at: indexPath)
    return BoardListCanvasTransitionTargetGeometry(
        cardRect: cardRect,
        focusRect: transitionFocusRect(
            at: indexPath,
            cardRect: cardRect
        )
    )
}
```

## 修改五：snapshot carrier 改成优先消费 `preferredRect`

### 修改前

- iOS / macOS 两端的 snapshot carrier 在 opening / closing 消费几何时都只读取 `cardRect`。
- 即使 source / target 后续具备了 `focusRect`，carrier 也不会真正用到它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningShell(using:) / resolvedClosingTargetFrame(in:)
// 功能说明: 修改前 iOS snapshot carrier 的 opening 与 closing 都只读 cardRect，缩略图锚点不会真正参与壳层动画。
private func prepareOpeningShell(using context: BoardListCanvasTransitionContext) {
    guard
        let overlayHostView,
        let sourceViewController,
        let sourceRect = context.sourceGeometry.cardRect
    else {
        return
    }

    // ... 省略 snapshot 准备逻辑 ...
}

private func resolvedClosingTargetFrame(
    in overlayHostView: UIView
) -> CGRect? {
    guard
        let destinationView = destinationViewController?.view,
        let targetRect = currentContext?.targetGeometry.cardRect
    else {
        return nil
    }

    // ... 省略坐标转换逻辑 ...
}
```

### 修改后

- iOS / macOS 两端都改成优先消费 `preferredRect`。
- 这意味着：
  - 有 `focusRect` 时，opening / closing 都会以缩略图或 placeholder icon 作为壳层锚点
  - 没有 `focusRect` 时，仍然会自动回退到 `cardRect`

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningShell(using:) / resolvedClosingTargetFrame(in:)
// 功能说明: 修改后 iOS snapshot carrier 统一使用 preferredRect，先吃 focusRect，再兜底 cardRect。
private func prepareOpeningShell(using context: BoardListCanvasTransitionContext) {
    guard
        let overlayHostView,
        let sourceViewController,
        let sourceRect = context.sourceGeometry.preferredRect
    else {
        return
    }

    // ... 省略 snapshot 准备逻辑 ...
}

private func resolvedClosingTargetFrame(
    in overlayHostView: UIView
) -> CGRect? {
    guard
        let destinationView = destinationViewController?.view,
        let targetRect = currentContext?.targetGeometry.preferredRect
    else {
        return nil
    }

    // ... 省略坐标转换逻辑 ...
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/AppRoot/macOSBoardListCanvasTransitionCarrier.swift
// 函数名/符号名: prepareOpeningShell(using:) / resolvedClosingTargetFrame(in:)
// 功能说明: 修改后 macOS snapshot carrier 与 iOS 对称，也改成统一消费 preferredRect。
private func prepareOpeningShell(using context: BoardListCanvasTransitionContext) {
    guard
        let overlayHostView,
        let sourceViewController,
        let sourceRect = context.sourceGeometry.preferredRect
    else {
        return
    }

    // ... 省略 snapshot 准备逻辑 ...
}

private func resolvedClosingTargetFrame(
    in overlayHostView: NSView
) -> CGRect? {
    guard
        let destinationView = destinationViewController?.view,
        let targetRect = currentContext?.targetGeometry.preferredRect
    else {
        return nil
    }

    // ... 省略坐标转换逻辑 ...
}
```

## 修改六：iOS closing trace 增加 `hasFocusRect`

### 修改前

- iOS closing trace 只会记录 `hasCardRect`。
- 即使 target-ready 已经开始返回缩略图锚点，也无法从日志上直接确认 carrier 是否具备 `focusRect`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:)
// 功能说明: 修改前 iOS AppRoot 的 closing trace 只能看到 hasCardRect，看不到 target-ready 是否已经具备 focusRect。
logClosingTransitionTrace(
    trace,
    phase: "targetGeometryResolved",
    localDuration: targetResolutionDuration,
    extra:
        "hasCardRect=\(geometry.cardRect != nil) " +
        "expectedBoardID=\(expectedBoardID?.uuidString ?? "nil")"
)
```

### 修改后

- `AppRoot` 的 `targetGeometryResolved` / `carrierAnimateBegin` 都增加了 `hasFocusRect`。
- `iOSBoardListViewController` 的 `resolveTransitionTargetGeometry` / `finishPendingTransitionTargetResolution` / `closingTargetReadySummary` 也同步带上了 `hasFocusRect`。
- 这样后续回归时能直接看出 `Phase 1` 是否真正让 closing 链拿到了缩略图锚点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/AppRoot/iOSAppRootViewController.swift
// 函数名/符号名: handleResolvedClosingTargetGeometry(_:sessionID:expectedBoardID:)
// 功能说明: 修改后 iOS AppRoot 的 closing trace 会同时记录 hasCardRect 与 hasFocusRect，方便验证 target-ready 是否真正命中缩略图锚点。
logClosingTransitionTrace(
    trace,
    phase: "targetGeometryResolved",
    localDuration: targetResolutionDuration,
    extra:
        "hasCardRect=\(geometry.cardRect != nil) " +
        "hasFocusRect=\(geometry.focusRect != nil) " +
        "expectedBoardID=\(expectedBoardID?.uuidString ?? "nil")"
)

logClosingTransitionTrace(
    trace,
    phase: "carrierAnimateBegin",
    extra:
        "hasCardRect=\(geometry.cardRect != nil) " +
        "hasFocusRect=\(geometry.focusRect != nil) " +
        "backButtonToCarrierAnimate=\(backButtonToCarrierAnimateSummary) " +
        "requestTargetGeometryToResolved=\(requestTargetGeometryToResolvedSummary)"
)
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift
// 函数名/符号名: logClosingGuardSummary(...) / finishPendingTransitionTargetResolution(...)
// 功能说明: 修改后 iOS BoardList 的 target-ready 日志和 closing guard summary 也同步记录 hasFocusRect。
private func logClosingGuardSummary(
    boardID: UUID,
    hasCardRect: Bool,
    hasFocusRect: Bool,
    usedFallbackGeometry: Bool? = nil
) {
    // ... 省略 state 解析逻辑 ...
    logClosingTransitionTiming(
        phase: "closingTargetReadySummary",
        extra:
            "boardID=\(boardID.uuidString) " +
            "hasCardRect=\(hasCardRect) " +
            "hasFocusRect=\(hasFocusRect)"
    )
}

logClosingTransitionTiming(
    phase: "finishPendingTransitionTargetResolution",
    localDuration: resolutionDuration,
    extra:
        "boardID=\(boardID.uuidString) " +
        "hasCardRect=\(geometry.cardRect != nil) " +
        "hasFocusRect=\(geometry.focusRect != nil)"
)
```

## 本轮结果

- source / target 的缩略图锚点正式统一成了 `focusRect + cardRect`。
- 可见 cell / item 与不可见 fallback 路径都能给出 `focusRect`。
- iOS / macOS 现有 snapshot carrier 已经切成“优先 `focusRect`，兜底 `cardRect`”。
- iOS closing trace 也已经能直接观测 `hasFocusRect`，为后续 `Phase 2 ~ Phase 4` 验证打基础。

## 校验情况

- 当前工作树中，`Phase 1` 相关文件状态与本记录一致：
  - 8 个已修改文件
  - 1 个新增文件 `BoardListCanvasTransitionFocusRectResolver.swift`
- 已对上述修改文件执行 `ReadLints`，结果为无 lint 错误。
- 已执行：
  - `xcrun --sdk macosx swiftc -frontend -parse MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListDisplayMode.swift MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionGeometry.swift MyCanvas_Ver_0/Platform/Shared/Transition/BoardListCanvasTransitionFocusRectResolver.swift`
  - 结果通过
- 本轮未执行完整 app 动画回归；是否已经在运行时完全表现为“缩略图放大/缩回”，仍需要人工在 iOS / macOS 上实际验证。

## 备注

- 这份记录只覆盖 `Phase 1` 的几何契约与消费改造，不包含 `liveCanvas carrier` 的 provider 边界、live reparent 或 handoff 实现。
