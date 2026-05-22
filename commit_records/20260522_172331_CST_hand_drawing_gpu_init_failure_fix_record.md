# 20260522_172331_CST_hand_drawing_gpu_init_failure_fix_record

## 记录范围

- 记录内容：
  - 定位并修复手绘 realtime draft GPU renderer 的初始化失败问题。
  - 明确问题根因：`HandDrawingCanvasSurfaceView.swift` 内联 Metal shader 的 vertex 函数里，把局部数组 `unitQuad` 错误声明成了 `constant float2 unitQuad[4]`，导致运行时动态编译 `shaderSource` 失败。
  - 补充 GPU 初始化成功 / 失败日志，避免后续只能看到模糊的 `Compiler failed to build request`，无法直接确认当前会话是否真的启用了 GPU renderer。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
- 如实说明：
  - 本记录只覆盖当前工作区中与“GPU 初始化失败修复”直接相关的 1 个代码文件。
  - 这次没有修改测试文件；验证主要依赖 `xcrun metal` 的最小化编译复现、iOS build，以及真机 Debug 控制台日志。
  - 这次记录不包含后续出现的 `HandDrawingToolPaletteView` Auto Layout 冲突；那是另一个独立问题，不属于 GPU 初始化失败的根因链路。
- 本记录不包含：
  - sticky fallback 的设计与实现说明。
  - `predictedTouches` 的开启决策。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统自带 date 命令生成本次 GPU 初始化失败修复记录文件的时间戳前缀。
20260522_172331_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
# 功能说明: 记录本轮 GPU 初始化失败修复对应的当前 changes 范围。
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
# 功能说明: 汇总本轮 GPU 初始化失败修复的改动规模，不粘贴原始 git diff。
.../UI/HandDrawingCanvasSurfaceView.swift          | 33 ++++++++++++++++++++--
1 file changed, 30 insertions(+), 3 deletions(-)
```

## 问题原因

- GPU realtime draft renderer 在初始化时，会通过 `device.makeLibrary(source: shaderSource, options: nil)` 动态编译 `shaderSource`。
- 修改前，`handDrawingDraftVertex` 里把函数内部局部数组 `unitQuad` 声明成了 `constant float2 unitQuad[4]`。
- 在 Metal 里，**自动变量（局部变量）不能带 address-space qualifier**，因此这段 shader 会在运行时编译阶段直接失败。
- 失败不是发生在 draw 阶段，而是更早发生在 GPU renderer 构建阶段，所以 `HandDrawingGPURealtimeDraftRendererView` 根本起不来。

### 根因代码（修改前）

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeRenderPipelineState(device:) / shaderSource.handDrawingDraftVertex
// 功能说明: 修改前 GPU 初始化会在这里动态编译 shaderSource；但 vertex shader 内部的局部数组写法本身就是非法的，导致 makeLibrary(...) 直接失败。
private static func makeRenderPipelineState(
    device: MTLDevice
) throws -> MTLRenderPipelineState {
    let library = try device.makeLibrary(source: shaderSource, options: nil)
    guard
        let vertexFunction = library.makeFunction(
            name: "handDrawingDraftVertex"
        ),
        let fragmentFunction = library.makeFunction(
            name: "handDrawingDraftFragment"
        )
    else {
        throw HandDrawingGPURealtimeDraftRendererSetupError
            .pipelineFunctionMissing
    }
    // ... 省略 descriptor 配置 ...
}

vertex VertexOut handDrawingDraftVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant StampInstance *instances [[buffer(0)]],
    constant float2 &canvasSize [[buffer(1)]]
) {
    constant float2 unitQuad[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    // ... 省略后续几何换算 ...
}
```

### 最小化复现证据

```sh
# 文件路径: 无（终端命令）
# 函数名: printf ... | xcrun -sdk macosx metal -x metal -c - -o /tmp/handdrawing_draft_fail.air
# 功能说明: 用最小化 Metal shader 直接复现“局部数组被写成 constant float2[...]”时的编译器错误。
<stdin>:4:21: error: automatic variable qualified with an address space
    constant float2 unitQuad[4] = {
                    ^
1 error generated.
```

## 修改一：修正 realtime draft shader 的非法局部数组声明

### 修改前

- `handDrawingDraftVertex` 的局部数组使用了 `constant float2 unitQuad[4]`。
- 这种写法会让 `device.makeLibrary(source: shaderSource, options: nil)` 在运行时直接抛错，GPU renderer 无法初始化。

```metal
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: shaderSource.handDrawingDraftVertex
// 功能说明: 修改前 vertex shader 的局部数组带有非法的 constant address-space qualifier，会在 Metal 编译阶段失败。
vertex VertexOut handDrawingDraftVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant StampInstance *instances [[buffer(0)]],
    constant float2 &canvasSize [[buffer(1)]]
) {
    constant float2 unitQuad[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    // ... 省略后续逻辑 ...
}
```

### 修改后

- 将 `constant float2 unitQuad[4]` 改成合法的局部数组 `float2 unitQuad[4]`。
- 同时在代码里加了一条简短注释，明确这不是风格问题，而是 Metal 的编译规则要求。

```metal
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: shaderSource.handDrawingDraftVertex
// 功能说明: 修改后把 unitQuad 改成合法的局部数组声明，消除 makeLibrary(...) 的编译阻塞点。
vertex VertexOut handDrawingDraftVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant StampInstance *instances [[buffer(0)]],
    constant float2 &canvasSize [[buffer(1)]]
) {
    // Metal 函数内的局部数组不能带 address-space qualifier。
    float2 unitQuad[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    // ... 省略后续逻辑 ...
}
```

## 修改二：把 GPU 初始化失败日志从模糊文本改成结构化诊断文本

### 修改前

- 失败路径只有一条：
  - `failedToCreateRenderer error=\(error)`
- 这通常只能看到类似 `Compiler failed to build request` 之类的模糊描述，无法直接知道 `domain`、`code`、`reason`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported()
// 功能说明: 修改前 GPU 初始化失败日志只打印 error 本身，诊断信息粒度不够。
static func makeIfSupported() -> HandDrawingGPURealtimeDraftRendererView? {
    guard let device = MTLCreateSystemDefaultDevice() else {
        return nil
    }
    do {
        return try HandDrawingGPURealtimeDraftRendererView(device: device)
    } catch {
        #if DEBUG
        print(
            "[HandDrawingDraftRender][GPUSetup] " +
            "failedToCreateRenderer error=\(error)"
        )
        #endif
        return nil
    }
}
```

### 修改后

- 新增 `formattedSetupError(_:)`，展开 `NSError` 的 `domain / code / description / reason / recovery`。
- 失败日志继续只打一条，但现在能直接带出更可读的错误详情。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported() / HandDrawingGPURealtimeDraftRendererView.formattedSetupError(_:)
// 功能说明: 修改后 GPU 初始化失败日志会输出更完整的诊断字段，避免后续只能看到模糊的错误文本。
static func makeIfSupported() -> HandDrawingGPURealtimeDraftRendererView? {
    guard let device = MTLCreateSystemDefaultDevice() else {
        return nil
    }
    do {
        let renderer = try HandDrawingGPURealtimeDraftRendererView(device: device)
        return renderer
    } catch {
        #if DEBUG
        print(
            "[HandDrawingDraftRender][GPUSetup] " +
            "failedToCreateRenderer " +
            Self.formattedSetupError(error)
        )
        #endif
        return nil
    }
}

private static func formattedSetupError(_ error: Error) -> String {
    let nsError = error as NSError
    var components = [
        "domain=\(nsError.domain)",
        "code=\(nsError.code)",
        "description=\(nsError.localizedDescription)"
    ]
    if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
       reason.isEmpty == false {
        components.append("reason=\(reason)")
    }
    if let recovery = nsError.userInfo[NSLocalizedRecoverySuggestionErrorKey] as? String,
       recovery.isEmpty == false {
        components.append("recovery=\(recovery)")
    }
    return components.joined(separator: " ")
}
```

## 修改三：补充 GPU 初始化成功日志，便于真机直接确认当前会话是否启用了 GPU

### 修改前

- 成功路径没有日志。
- 所以即使没有失败日志，也只能“推测 GPU 可能成功”，不能在控制台里看到明确的正向证据。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported()
// 功能说明: 修改前成功路径静默返回 renderer，控制台没有正向成功证据。
do {
    return try HandDrawingGPURealtimeDraftRendererView(device: device)
} catch {
    // ... 失败日志 ...
    return nil
}
```

### 修改后

- 成功创建 renderer 后，在 `DEBUG` 下打印一条一次性日志：
  - `initializedRenderer device=...`
- 这样真机画第一笔时，就能直接确认当前会话已经启用了 GPU renderer。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported()
// 功能说明: 修改后成功路径会明确打印 initializedRenderer，便于用真机控制台直接确认 GPU renderer 已启用。
do {
    let renderer = try HandDrawingGPURealtimeDraftRendererView(device: device)
    #if DEBUG
    print(
        "[HandDrawingDraftRender][GPUSetup] " +
        "initializedRenderer device=\(device.name)"
    )
    #endif
    return renderer
} catch {
    // ... 失败日志 ...
    return nil
}
```

## 验证

### 验证一：最小化 Metal shader 复现“修改前失败 / 修改后通过”

```sh
# 文件路径: 无（终端命令）
# 函数名: printf ... | xcrun -sdk macosx metal -x metal -c - -o /tmp/handdrawing_draft_fail.air
# 功能说明: 证明修改前的写法会被 Metal 编译器直接拒绝。
<stdin>:4:21: error: automatic variable qualified with an address space
    constant float2 unitQuad[4] = {
                    ^
1 error generated.
```

```sh
# 文件路径: 无（终端命令）
# 函数名: printf ... | xcrun -sdk macosx metal -x metal -c - -o /tmp/handdrawing_draft_fixed.air
# 功能说明: 证明把 unitQuad 改成普通局部数组后，Metal 编译器可以通过。
# 结果: 无输出，exit_code = 0
```

### 验证二：iOS 目标构建通过

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvasGPUInitFixiOSBuild"
# 功能说明: 验证修正 shader 根因后的 iOS 目标可以正常编译。
** BUILD SUCCEEDED **
exit_code: 0
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvasGPUSetupSuccessLogiOSBuild"
# 功能说明: 验证补充成功日志后，iOS 目标仍然保持可编译状态。
** BUILD SUCCEEDED **
exit_code: 0
```

### 验证三：真机 Debug 控制台确认 GPU 初始化成功

```sh
# 文件路径: 真机 Debug 控制台日志（用户现场运行）
# 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported()
# 功能说明: 真机画笔输入后，控制台出现 initializedRenderer，说明 GPU renderer 已成功创建并启用。
[HandDrawingDraftRender][GPUSetup] initializedRenderer device=Apple M4 GPU
```

## 结论

- 这次 GPU 初始化失败的根因不是 host 路由、不是 command queue 创建逻辑，而是 realtime draft shader 自身的 Metal 语法错误。
- 修复后，`shaderSource` 的运行时编译阻塞点已经被清掉，GPU realtime draft renderer 可以正常初始化。
- 同时，新加的成功 / 失败日志已经把后续诊断路径收口清楚：
  - 成功看 `initializedRenderer device=...`
  - 失败看 `failedToCreateRenderer domain=... code=... description=...`
