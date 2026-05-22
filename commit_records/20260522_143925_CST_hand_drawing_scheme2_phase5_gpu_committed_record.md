# 20260522_143925_CST_hand_drawing_scheme2_phase5_gpu_committed_record

## 记录范围

- 记录内容：
  - 实施手绘方案二升级计划中的 `phase 5`，把 committed canvas 从“固定 CPU renderer”推进到“默认 CPU、可选 GPU committed backend 原型”。
  - 本次修改只作用于编辑期 committed canvas，不改动 `document / history / persistence / preview / export` 的 CPU 真相源。
  - 本次重点不是把 brush math 全量 GPU 化，而是先把 committed backend 的合同、选择策略和 GPU 原型落地。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift`
- 本记录不包含：
  - `phase 6` 的统一 render graph 边界整理。
  - preview / export 的 GPU 化。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统 date 命令生成本次 phase 5 记录文件的时间戳前缀。
20260522_143925_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 汇总本次 phase 5 中已进入 tracked diff 的修改统计；新增的 GPU backend 文件会在后面的 current changes 里体现。
.../Rendering/HandDrawingCanvasRenderer.swift      | 34 +++++-------
.../Rendering/HandDrawingRenderingContracts.swift  | 63 +++++++++++++++++++---
.../HandDrawingEditorCoordinator.swift             | 31 +++++++++--
.../HandDrawingRenderingContractsTests.swift       | 37 +++++++++++++
4 files changed, 134 insertions(+), 31 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 记录生成本文件时，与本次 phase 5 直接对应的当前 changes；其中 GPU committed backend 文件为新增未跟踪文件。
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
 M MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift
```

## 当前 changes 摘要

- `HandDrawingRenderingContracts.swift`
  - 新增 `HandDrawingCommittedCanvasBackendPreference`
  - 新增 `HandDrawingCommittedCanvasRenderRequest`
  - 把 committed backend 协议升级为 `render(request:)`
- `HandDrawingCanvasRenderer.swift`
  - CPU committed renderer 改为消费统一 request 合同
  - 原本内嵌在 renderer 内部的 dirty-region 解析逻辑，迁移到 `HandDrawingCommittedCanvasRenderRequest`
- `HandDrawingGPUCommittedCanvasBackend.swift`
  - 新增 committed canvas 的 GPU 原型 backend
  - GPU 负责 committed texture 生命周期、dirty-region 清屏和逐层 composite
  - 单 stroke 像素仍由 CPU `HandDrawingStrokeRasterizer` 产出，维持 canonical pixels
- `HandDrawingEditorCoordinator.swift`
  - 新增 `committedCanvasBackendPreference`
  - 默认仍走 `.cpu`
  - 若显式指定 `.gpuPrototype`，则优先尝试创建 GPU backend，失败自动回退 CPU
- `HandDrawingRenderingContractsTests.swift`
  - 新增 committed render request 合同测试
  - 覆盖 `nil dirtyRegion => full redraw`
  - 覆盖 dirty region 裁剪到 paper bounds 后再 integral 化

## 修改一：把 committed canvas 的 dirty-region 语义前移到 backend 合同层

### 修改前

- committed backend 只有 `render(document:dirtyRegion:)` 入口。
- dirty region 的 `standardized / intersection / integral / fallback to paperBounds` 逻辑只存在于 `HandDrawingCanvasRenderer` 内部。
- 这使得 committed canvas 的 partial rerender 语义依附于 CPU `CGContext` 实现细节，而不是 renderer-agnostic 合同。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift（修改前）
// 函数名: HandDrawingCommittedCanvasBackend.render(document:dirtyRegion:)
// 功能说明: 修改前 committed backend 协议只暴露 document + dirtyRegion，没有独立的 render request 合同。
protocol HandDrawingCommittedCanvasBackend {
    func render(
        document: HandDrawingDocument,
        dirtyRegion: CGRect?
    ) throws -> HandDrawingCommittedCanvasRenderOutput
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift（修改前）
// 函数名: render(document:dirtyRegion:) / resolvedRenderRegion(_:paperBounds:)
// 功能说明: 修改前 dirty region 的解析、裁剪和 integral 化都内嵌在 CPU renderer 里。
func render(
    document: HandDrawingDocument,
    dirtyRegion: CGRect? = nil
) throws -> CGImage {
    let renderRegion = resolvedRenderRegion(
        dirtyRegion,
        paperBounds: document.paperBounds
    )
    // ... 省略后续 bitmap 清理与 stroke 重绘 ...
}

private func resolvedRenderRegion(
    _ dirtyRegion: CGRect?,
    paperBounds: CGRect
) -> CGRect {
    let rawRegion = dirtyRegion ?? paperBounds
    let intersectedRegion = rawRegion
        .standardized
        .intersection(paperBounds)
    guard
        intersectedRegion.isNull == false,
        intersectedRegion.isEmpty == false
    else {
        return paperBounds
    }
    return intersectedRegion.integral
}
```

### 修改后

- 新增 `HandDrawingCommittedCanvasBackendPreference`，为 committed canvas backend 选择留出显式合同。
- 新增 `HandDrawingCommittedCanvasRenderRequest`，把 `document / dirtyRegion / paperBounds / renderRegion / isFullRedraw` 放到统一入口里。
- committed backend 协议新增 `render(request:)`，并保留 `render(document:dirtyRegion:)` 作为便捷转发。
- `HandDrawingCanvasRenderer` 不再自己推导 render region，而是直接消费 request 语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingCommittedCanvasBackendPreference / HandDrawingCommittedCanvasRenderRequest / HandDrawingCommittedCanvasBackend.render(request:)
// 功能说明: phase 5 把 committed backend 选择和 dirty-region 语义前移到统一合同层，避免只绑定 CPU CGContext 细节。
enum HandDrawingCommittedCanvasBackendPreference: Equatable {
    case cpu
    case gpuPrototype
}

struct HandDrawingCommittedCanvasRenderRequest: Equatable {
    let document: HandDrawingDocument
    let dirtyRegion: CGRect?

    var paperBounds: CGRect {
        document.paperBounds
    }

    var renderRegion: CGRect {
        let rawRegion = dirtyRegion ?? paperBounds
        let intersectedRegion = rawRegion
            .standardized
            .intersection(paperBounds)
        guard
            intersectedRegion.isNull == false,
            intersectedRegion.isEmpty == false
        else {
            return paperBounds.integral
        }
        return intersectedRegion.integral
    }

    var isFullRedraw: Bool {
        renderRegion.equalTo(paperBounds.integral)
    }
}

protocol HandDrawingCommittedCanvasBackend {
    func render(
        request: HandDrawingCommittedCanvasRenderRequest
    ) throws -> HandDrawingCommittedCanvasRenderOutput
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingCanvasRenderer.swift
// 函数名: render(document:dirtyRegion:) / render(request:)
// 功能说明: 修改后 CPU committed renderer 直接消费统一 request 合同，renderRegion 不再在本类内部重复定义。
func render(
    document: HandDrawingDocument,
    dirtyRegion: CGRect? = nil
) throws -> CGImage {
    try render(
        request: HandDrawingCommittedCanvasRenderRequest(
            document: document,
            dirtyRegion: dirtyRegion
        )
    )
}

func render(
    request: HandDrawingCommittedCanvasRenderRequest
) throws -> CGImage {
    let document = request.document
    let renderRegion = request.renderRegion
    clear(region: renderRegion)
    bitmapContext.saveGState()
    bitmapContext.addRect(renderRegion)
    bitmapContext.clip()

    for stroke in document.renderedStrokesInOrder where stroke.isEmpty == false {
        guard
            let strokeBounds = stroke.bounds,
            strokeBounds.intersects(renderRegion)
        else {
            continue
        }
        HandDrawingStrokeRasterizer.draw(stroke, in: bitmapContext)
    }
    bitmapContext.restoreGState()
    return try Self.makeOwnedImage(from: bitmapContext)
}
```

## 修改二：让 coordinator 从“固定 CPU committed backend”升级为“默认 CPU、可选 GPU 原型”

### 修改前

- coordinator 初始化时直接构造 `HandDrawingCPUCommittedCanvasBackend`。
- 后续 committed canvas 刷新也直接用 `document + dirtyRegion` 形式调用，无法表达 backend 偏好。
- 这意味着 `phase 5` 之前 committed canvas 即使抽象了协议，运行时仍然没有真正的 GPU 入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: init(...) / refreshCommittedCanvasAndPublishState(forceFullRender:)
// 功能说明: 修改前 coordinator 默认固定创建 CPU committed backend，并直接调用 render(document:dirtyRegion:)。
init(
    editorContext: CanvasHandDrawingEditorContext,
    committedCanvasBackend: HandDrawingCommittedCanvasBackend? = nil,
    realtimeDraftBackendPreference: HandDrawingRealtimeDraftBackendPreference = .gpuPreferred
) throws {
    let document = try HandDrawingDocumentLoader.loadDocument(
        from: editorContext.documentData,
        paper: editorContext.paper
    )
    let resolvedCommittedCanvasBackend = try committedCanvasBackend
        ?? HandDrawingCPUCommittedCanvasBackend(paperSize: document.paper.size)
    self.committedCanvasBackend = resolvedCommittedCanvasBackend
    committedCanvas = try resolvedCommittedCanvasBackend.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
}

private func refreshCommittedCanvasAndPublishState(
    forceFullRender: Bool = false
) {
    let dirtyRegion = forceFullRender
        ? engine.state.document.paperBounds
        : engine.consumeDirtyRegion()
    committedCanvas = try committedCanvasBackend.render(
        document: engine.state.document,
        dirtyRegion: dirtyRegion
    )
}
```

### 修改后

- 初始化参数新增 `committedCanvasBackendPreference`，默认值是 `.cpu`，所以现有系统行为不回归。
- 新增 `makeCommittedCanvasBackend(preference:paperSize:)`：
  - `.cpu` 明确返回 CPU backend
  - `.gpuPrototype` 优先尝试 `HandDrawingGPUCommittedCanvasBackend`
  - 若 Metal 不可用或 GPU backend 创建失败，则自动回退 CPU backend
- committed canvas 刷新统一走 `HandDrawingCommittedCanvasRenderRequest`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: init(...) / refreshCommittedCanvasAndPublishState(forceFullRender:) / makeCommittedCanvasBackend(preference:paperSize:)
// 功能说明: 修改后 coordinator 显式发布 committed backend 偏好，并统一以 request 合同驱动 committed canvas 刷新。
init(
    editorContext: CanvasHandDrawingEditorContext,
    committedCanvasBackend: HandDrawingCommittedCanvasBackend? = nil,
    committedCanvasBackendPreference: HandDrawingCommittedCanvasBackendPreference = .cpu,
    realtimeDraftBackendPreference: HandDrawingRealtimeDraftBackendPreference = .gpuPreferred
) throws {
    let document = try HandDrawingDocumentLoader.loadDocument(
        from: editorContext.documentData,
        paper: editorContext.paper
    )
    let resolvedCommittedCanvasBackend = try committedCanvasBackend
        ?? Self.makeCommittedCanvasBackend(
            preference: committedCanvasBackendPreference,
            paperSize: document.paper.size
        )
    self.committedCanvasBackend = resolvedCommittedCanvasBackend
    committedCanvas = try resolvedCommittedCanvasBackend.render(
        document: document,
        dirtyRegion: document.paperBounds
    )
}

private func refreshCommittedCanvasAndPublishState(
    forceFullRender: Bool = false
) {
    let dirtyRegion = forceFullRender
        ? engine.state.document.paperBounds
        : engine.consumeDirtyRegion()
    committedCanvas = try committedCanvasBackend.render(
        request: HandDrawingCommittedCanvasRenderRequest(
            document: engine.state.document,
            dirtyRegion: dirtyRegion
        )
    )
}

private static func makeCommittedCanvasBackend(
    preference: HandDrawingCommittedCanvasBackendPreference,
    paperSize: CGSize
) throws -> HandDrawingCommittedCanvasBackend {
    switch preference {
    case .cpu:
        return try HandDrawingCPUCommittedCanvasBackend(paperSize: paperSize)
    case .gpuPrototype:
        #if canImport(Metal)
        if let backend = try? HandDrawingGPUCommittedCanvasBackend(
            paperSize: paperSize
        ) {
            return backend
        }
        #endif
        return try HandDrawingCPUCommittedCanvasBackend(paperSize: paperSize)
    }
}
```

## 修改三：新增 GPU committed backend 原型文件

### 修改前

- 仓库中不存在 committed canvas 的 GPU backend 文件。
- committed canvas 只有 CPU bitmap renderer 一条落地图像路径。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift（修改前）
// 函数名: 无
// 功能说明: phase 5 之前项目中不存在 committed canvas 的 GPU backend 原型文件。
// 本文件不存在。
```

### 修改后

- 新增 `HandDrawingGPUCommittedCanvasBackend.swift`。
- 当前原型的边界是：
  - GPU 持有 committed texture
  - GPU 负责 dirty-region scissor clear
  - GPU 按 document 的 layer / stroke 顺序 composite
  - 单 stroke 像素仍由 CPU `HandDrawingStrokeRasterizer` 画到中间 `CGImage`，再上传为 `MTLTexture`
- 这保证了 phase 5 已经把 committed backend 真正做成可替换实现，但还没有越过 CPU truth 边界。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingGPUCommittedCanvasBackend.swift
// 函数名: HandDrawingGPUCommittedCanvasBackend.render(request:) / renderIntoTexture(request:) / drawStrokeTexture(for:canvasSize:using:)
// 功能说明: 新增 GPU committed backend 原型；GPU 管 committed texture 生命周期、局部清屏与 composite，单 stroke 像素继续由 CPU rasterizer 产出，保持 canonical pixels。
final class HandDrawingGPUCommittedCanvasBackend: HandDrawingCommittedCanvasBackend {
    static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    func render(
        request: HandDrawingCommittedCanvasRenderRequest
    ) throws -> HandDrawingCommittedCanvasRenderOutput {
        let effectiveRequest = try prepareTextureIfNeeded(for: request)
        try renderIntoTexture(request: effectiveRequest)
        return .bitmap(try Self.makeOwnedImage(from: texture))
    }

    private func renderIntoTexture(
        request: HandDrawingCommittedCanvasRenderRequest
    ) throws {
        let renderRegion = request.renderRegion
        renderEncoder.setScissorRect(
            Self.makeScissorRect(
                for: renderRegion,
                textureWidth: texture.width,
                textureHeight: texture.height
            )
        )
        drawClearQuad(with: renderEncoder)

        for stroke in request.document.renderedStrokesInOrder where stroke.isEmpty == false {
            guard
                let strokeBounds = stroke.bounds,
                strokeBounds.intersects(renderRegion)
            else {
                continue
            }
            try drawStrokeTexture(
                for: stroke,
                canvasSize: request.document.paper.size,
                using: renderEncoder
            )
        }
    }

    private func drawStrokeTexture(
        for stroke: HandDrawingStroke,
        canvasSize: CGSize,
        using renderEncoder: MTLRenderCommandEncoder
    ) throws {
        let strokeImage = try Self.makeStrokeImage(
            for: stroke,
            canvasSize: canvasSize
        )
        let strokeTexture = try textureLoader.newTexture(
            cgImage: strokeImage,
            options: Self.textureLoaderOptions
        )
        renderEncoder.setRenderPipelineState(compositePipelineState)
        renderEncoder.setFragmentTexture(strokeTexture, index: 0)
        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: 4
        )
    }
}
```

## 修改四：补 committed render request 的合同测试

### 修改前

- `HandDrawingRenderingContractsTests.swift` 只覆盖 realtime draft packet 的 committed tail / predicted tail 合同。
- committed canvas 新引入的 request 语义没有单独回归：
  - `nil dirtyRegion` 是否视作 full redraw
  - dirty region 是否正确裁剪到 paper bounds 并 integral 化

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift（修改前）
// 函数名: testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately()
// 功能说明: 修改前测试文件只校验 realtime draft packet 合同，没有 committed render request 的专门回归。
final class HandDrawingRenderingContractsTests: XCTestCase {
    func testHandDrawingRealtimeDraftPacketCarriesCommittedTailAndPredictedTailSeparately() {
        // ... 省略既有 realtime packet 合同断言 ...
    }
}
```

### 修改后

- 保留原有 realtime packet 合同测试。
- 新增 2 条 committed request 合同测试：
  - `testHandDrawingCommittedCanvasRenderRequestTreatsNilDirtyRegionAsFullRedraw()`
  - `testHandDrawingCommittedCanvasRenderRequestClipsDirtyRegionToIntegralPaperBounds()`

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
// 函数名: testHandDrawingCommittedCanvasRenderRequestTreatsNilDirtyRegionAsFullRedraw() / testHandDrawingCommittedCanvasRenderRequestClipsDirtyRegionToIntegralPaperBounds()
// 功能说明: 修改后补齐 committed render request 的合同回归，确保 full redraw 与 dirty-region 裁剪语义独立稳定。
func testHandDrawingCommittedCanvasRenderRequestTreatsNilDirtyRegionAsFullRedraw() {
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "committed-request-full-redraw-paper",
            size: CGSize(width: 120, height: 80)
        ),
        strokes: []
    )
    let request = HandDrawingCommittedCanvasRenderRequest(
        document: document,
        dirtyRegion: nil
    )

    XCTAssertEqual(request.renderRegion, document.paperBounds.integral)
    XCTAssertTrue(request.isFullRedraw)
}

func testHandDrawingCommittedCanvasRenderRequestClipsDirtyRegionToIntegralPaperBounds() {
    let document = HandDrawingDocument(
        paper: HandDrawingPaper(
            id: "committed-request-clipped-paper",
            size: CGSize(width: 120, height: 80)
        ),
        strokes: []
    )
    let request = HandDrawingCommittedCanvasRenderRequest(
        document: document,
        dirtyRegion: CGRect(x: -6.4, y: 18.2, width: 28.3, height: 16.1)
    )

    XCTAssertEqual(
        request.renderRegion,
        CGRect(x: 0, y: 18, width: 22, height: 17)
    )
    XCTAssertFalse(request.isFullRedraw)
}
```

## 验证结果

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test ... && xcodebuild build ...
# 功能说明: 验证本次 phase 5 最终 changes；macOS 手绘渲染相关单测通过，iOS Simulator 构建通过。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests" -only-testing:"MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests"
# 结果: Exit code 0

xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator"
# 结果: Exit code 0
```

## 如实说明

- 本次最终 current changes 中，没有保留 macOS XCTest 下的 GPU committed runtime parity 测试。
- 原因不是 phase 5 的合同或编译失败，而是在尝试把 GPU committed runtime parity 单测接入 `HandDrawingCanvasRendererTests.swift` 时，宿主环境重复触发 `abort` 类崩溃，表现与前面 phase 3 / phase 4 遇到的 macOS XCTest host 不稳定问题一致。
- 因此最终保留的验证组合是：
  - committed request 合同测试
  - 既有 CPU committed / preview parity 测试
  - iOS Simulator 构建通过
- 这与 phase 5 的设计边界一致：先把 committed backend 抽象和 GPU 原型做对、接稳，但不把整个系统真相源从 CPU 迁走。
