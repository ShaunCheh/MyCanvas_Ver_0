# 20260317_204732_minimap_phase7_extensibility_provider_record

## 记录范围

- 记录内容：
  1. 为 minimap 新增通用 node provider 层，把图片节点生产逻辑从 `CanvasMiniMapRenderer` 中拆出。
  2. 为 minimap 新增统一的 render context，避免 renderer 方法签名继续被图片专属参数绑死。
  3. 更新 iOS / macOS controller 的 minimap 刷新入口，改为传入 `CanvasMiniMapRenderContext`。
  4. 保留计划文件中的阶段状态同步结果。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
  - `.cursor/plans/minimap分阶段计划_b0c25ff2.plan.md`
- 本记录不包含：
  - 原始 git diff
  - git commit / push
  - 未来文字 / 贴纸 / 形状 runtime model 的完整实现

## 修改一：新增 minimap node provider 层

### 修改前

- `CanvasMiniMapRenderer` 直接依赖：
  - `CanvasImagePresentationResolver`
  - `CanvasScene.orderedItems()`
  - `CanvasImageItem`
  - 图片裁切 / 旋转预览态
- 这意味着未来要接入文字、贴纸、形状时，只能继续往 renderer 里塞更多元素专属逻辑，renderer 会重新变成“多分支总控”。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(...) / makeNode(for:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 自己直接遍历 CanvasImageItem 并生成 image-only 的 minimap node。
struct CanvasMiniMapRenderer {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeSnapshot(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        inlineEditState: CanvasInlineEditState? = nil,
        rotationPreviewState: CanvasRotationPreviewState? = nil
    ) -> CanvasMiniMapSnapshot {
        let visibleWorldRect = sanitizedWorldRect(camera.visibleWorldRect) ?? .zero
        let nodes = scene.orderedItems().map { item in
            makeNode(
                for: item,
                inlineEditState: inlineEditState,
                rotationPreviewState: rotationPreviewState
            )
        }
        // ...
    }

    private func makeNode(
        for item: CanvasImageItem,
        inlineEditState: CanvasInlineEditState?,
        rotationPreviewState: CanvasRotationPreviewState?
    ) -> CanvasMiniMapNode {
        let presentation = presentationResolver.resolve(
            item: item,
            inlineEditState: inlineEditState,
            rotationPreviewState: rotationPreviewState
        )
        return CanvasMiniMapNode(
            id: presentation.itemID,
            kind: .image,
            worldQuad: presentation.visibleWorldQuad,
            zIndex: presentation.zIndex,
            isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
        )
    }
}
```

### 修改后

- 新增 `CanvasMiniMapNodeProvider.swift`，把“如何从某类元素生产 minimap node”抽成独立 provider。
- 当前先落地图片版 provider：`CanvasMiniMapImageNodeProvider`
- 这样未来要加文字 / 贴纸 / 形状时，只需要补新的 provider，而不用推翻 minimap renderer / snapshot / layout / 平台 view。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: CanvasMiniMapNodeProviding / CanvasMiniMapImageNodeProvider.makeNodes(context:)
// 功能说明: 新增通用 minimap node provider 抽象，并用图片 provider 承接当前 image-only 的节点生成逻辑。
protocol CanvasMiniMapNodeProviding {
    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode]
}

// Renderer stays provider-driven so future text/sticker/shape support can add
// new node providers without rewriting snapshot/layout/platform minimap views.
struct CanvasMiniMapImageNodeProvider: CanvasMiniMapNodeProviding {
    private let presentationResolver = CanvasImagePresentationResolver()

    func makeNodes(
        context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        context.scene.orderedItems().map { item in
            let presentation = presentationResolver.resolve(
                item: item,
                inlineEditState: context.imageInlineEditState,
                rotationPreviewState: context.imageRotationPreviewState
            )
            return CanvasMiniMapNode(
                id: presentation.itemID,
                kind: .image,
                worldQuad: presentation.visibleWorldQuad,
                zIndex: presentation.zIndex,
                isPreviewActive: presentation.isCropPreviewActive || presentation.isRotationPreviewActive
            )
        }
    }
}
```

## 修改二：为 renderer 新增统一的 render context

### 修改前

- `CanvasMiniMapRenderer.makeSnapshot(...)` 直接暴露图片当前所需的全部参数：
  - `scene`
  - `boardState`
  - `camera`
  - `inlineEditState`
  - `rotationPreviewState`
- 如果以后再接更多元素预览态，renderer 方法签名会持续膨胀。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(scene:boardState:camera:inlineEditState:rotationPreviewState:)
// 功能说明: 修改前 renderer 入口仍然带着图片专属预览态参数。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil
) -> CanvasMiniMapSnapshot
```

### 修改后

- 新增：
  - `CanvasMiniMapNodeProviderContext`
  - `CanvasMiniMapRenderContext`
- `CanvasMiniMapRenderContext` 负责把 board / camera / provider input 收拢起来。
- 这样未来即使再增加其他 provider 所需的数据，也可以先往 context 里扩展，而不是把 renderer API 越改越碎。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift
// 函数名: CanvasMiniMapNodeProviderContext / CanvasMiniMapRenderContext.init(...)
// 功能说明: 新增 minimap render context，把 renderer 运行所需输入统一收口。
struct CanvasMiniMapNodeProviderContext {
    let scene: CanvasScene
    let imageInlineEditState: CanvasInlineEditState?
    let imageRotationPreviewState: CanvasRotationPreviewState?
}

struct CanvasMiniMapRenderContext {
    let boardState: CanvasBoardState?
    let camera: CanvasCamera
    let nodeProviderContext: CanvasMiniMapNodeProviderContext

    init(
        scene: CanvasScene,
        boardState: CanvasBoardState? = nil,
        camera: CanvasCamera,
        imageInlineEditState: CanvasInlineEditState? = nil,
        imageRotationPreviewState: CanvasRotationPreviewState? = nil
    ) {
        self.init(
            boardState: boardState,
            camera: camera,
            nodeProviderContext: CanvasMiniMapNodeProviderContext(
                scene: scene,
                imageInlineEditState: imageInlineEditState,
                imageRotationPreviewState: imageRotationPreviewState
            )
        )
    }
}
```

## 修改三：让 renderer 改为“收集 provider 节点”，不再自己理解图片类型

### 修改前

- renderer 自己做图片节点解析，职责同时包含：
  - 取图片元素
  - 解析图片预览态
  - 生产 minimap node
  - 合成 snapshot
- 这让 renderer 自身和图片元素强耦合。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: makeSnapshot(...) / makeNode(...)
// 功能说明: 修改前 renderer 兼任“节点来源组织者”和“图片节点解释器”两种角色。
let nodes = scene.orderedItems().map { item in
    makeNode(
        for: item,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
}
```

### 修改后

- renderer 改成持有 `nodeProviders`
- 默认仍只装一个 provider：`CanvasMiniMapImageNodeProvider()`
- 但 renderer 自身已经只负责：
  - 组织 provider 输入
  - 汇总所有节点
  - 稳定排序
  - 合成最终 snapshot

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift
// 函数名: init(nodeProviders:) / makeSnapshot(context:) / resolveNodes(using:)
// 功能说明: 修改后 renderer 只负责编排 provider 输出并合成 snapshot，不再直接耦合图片节点解析细节。
struct CanvasMiniMapRenderer {
    private let nodeProviders: [any CanvasMiniMapNodeProviding]

    init(nodeProviders: [any CanvasMiniMapNodeProviding]? = nil) {
        self.nodeProviders = nodeProviders ?? [CanvasMiniMapImageNodeProvider()]
    }

    func makeSnapshot(
        context: CanvasMiniMapRenderContext
    ) -> CanvasMiniMapSnapshot {
        let visibleWorldRect = sanitizedWorldRect(context.camera.visibleWorldRect) ?? .zero
        let nodes = resolveNodes(using: context.nodeProviderContext)
        // ...
    }

    private func resolveNodes(
        using context: CanvasMiniMapNodeProviderContext
    ) -> [CanvasMiniMapNode] {
        nodeProviders
            .flatMap { $0.makeNodes(context: context) }
            .sorted { lhs, rhs in
                if lhs.zIndex == rhs.zIndex {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.zIndex < rhs.zIndex
            }
    }
}
```

## 修改四：controller 改为传入统一的 minimap render context

### 修改前

- iOS / macOS controller 都直接把图片链路参数逐个传进 minimap renderer。
- 调用点已经带有图片专属语义，不利于后续扩展别的 provider。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: refreshMiniMap()
// 功能说明: 修改前 iOS controller 直接把 scene / board / camera / 图片预览态逐个传给 renderer。
private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    miniMapView.apply(snapshot)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshMiniMap()
// 功能说明: 修改前 macOS controller 也采用同样的逐参数调用方式。
private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        scene: scene,
        boardState: boardState,
        camera: camera,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState
    )
    miniMapView.apply(snapshot)
}
```

### 修改后

- iOS / macOS controller 统一改成构造 `CanvasMiniMapRenderContext`
- 这样 controller 的 minimap 刷新入口也不再绑定到“只有图片”的参数形态

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: refreshMiniMap()
// 功能说明: 修改后 iOS controller 先构造 minimap render context，再交给 renderer 统一处理。
private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            imageInlineEditState: inlineEditState,
            imageRotationPreviewState: rotationPreviewState
        )
    )
    miniMapView.apply(snapshot)
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: refreshMiniMap()
// 功能说明: 修改后 macOS controller 与 iOS 保持同构，统一通过 render context 驱动 minimap renderer。
private func refreshMiniMap() {
    let snapshot = miniMapRenderer.makeSnapshot(
        context: CanvasMiniMapRenderContext(
            scene: scene,
            boardState: boardState,
            camera: camera,
            imageInlineEditState: inlineEditState,
            imageRotationPreviewState: rotationPreviewState
        )
    )
    miniMapView.apply(snapshot)
}
```

## 修改五：保留计划文件中的阶段状态同步

### 修改前

- 计划文件里的 `todos` 仍停留在 `pending`

```yaml
# 文件路径: .cursor/plans/minimap分阶段计划_b0c25ff2.plan.md
# 函数名: 顶部 frontmatter.todos
# 功能说明: 修改前计划文件中的 minimap 阶段状态还未同步为完成。
todos:
  - id: extract-presentation-resolver
    status: pending
  - id: add-minimap-renderer
    status: pending
  - id: refactor-overlay-layout
    status: pending
  - id: build-ios-minimap-view
    status: pending
  - id: build-macos-minimap-view
    status: pending
  - id: wire-controller-interactions
    status: pending
  - id: verify-regressions
    status: pending
```

### 修改后

- 当前计划文件里，上述阶段状态已同步为 `completed`
- 这部分变更本身不影响 minimap runtime，但反映了当前阶段执行状态

```yaml
# 文件路径: .cursor/plans/minimap分阶段计划_b0c25ff2.plan.md
# 函数名: 顶部 frontmatter.todos
# 功能说明: 修改后计划文件中的 minimap 已完成阶段状态被同步为 completed。
todos:
  - id: extract-presentation-resolver
    status: completed
  - id: add-minimap-renderer
    status: completed
  - id: refactor-overlay-layout
    status: completed
  - id: build-ios-minimap-view
    status: completed
  - id: build-macos-minimap-view
    status: completed
  - id: wire-controller-interactions
    status: completed
  - id: verify-regressions
    status: completed
```

## 结果与影响

- 这次 `Phase 7` 没有引入新的元素类型功能，但已经把 minimap 架构从“image-only renderer”收口为“provider-driven renderer”
- 当前状态下：
  - `CanvasMiniMapSnapshot` 继续只依赖通用 `CanvasMiniMapNode`
  - iOS / macOS minimap view 不需要知道具体元素类型实现细节
  - controller 刷新链路也已经通过 `CanvasMiniMapRenderContext` 脱离图片专属方法签名
- 后续如果要接入：
  - 文字
  - 贴纸
  - 形状
  
  则优先新增对应 provider，而不是重写 minimap layout / platform view / interaction 结构

## 校验情况

- 已使用 `ReadLints` 检查本次改动文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapNodeProvider.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapRenderer.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 未发现新增诊断
- 已执行 macOS 全链路 `swiftc -typecheck`：
  - `MyCanvas_Ver_0/Canvas/Core/*.swift`
  - `MyCanvas_Ver_0/Canvas/Editing/*.swift`
  - `MyCanvas_Ver_0/Canvas/Storage/*.swift`
  - `MyCanvas_Ver_0/App/*.swift`
  - `MyCanvas_Ver_0/Platform/Shared/Rendering/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/AppRoot/*.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/*.swift`
- typecheck 通过
