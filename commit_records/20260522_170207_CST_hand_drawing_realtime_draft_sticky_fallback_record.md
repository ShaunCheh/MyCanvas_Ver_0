# 20260522_170207_CST_hand_drawing_realtime_draft_sticky_fallback_record

## 记录范围

- 记录内容：
  - 修复手绘 realtime draft renderer 的 fallback 路径，让 GPU 初始化失败后的 CPU fallback 变成 sticky fallback。
  - 避免 `HandDrawingRealtimeDraftHostView` 在每次 revision 到来时都重新尝试创建 GPU renderer，进而反复重建 CPU host、清空 CPU packet accumulator。
  - 为 sticky fallback 路由语义补齐专门的契约测试。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift`
- 如实说明：
  - 本记录只覆盖当前工作区里与这次 sticky fallback 修复直接相关的 3 个文件。
  - 本轮没有排查或修复 GPU 初始化失败的根因，只修复“失败后反复重试并重建 host”的 fallback 行为。
  - `HandDrawingCanvasSurfaceView.swift` 里有一个一并落下的小整理：`touchesEnded` 改成先保存 `inputBatch` 再回调，便于 ended 路径与 moved 路径保持一致；这不是行为语义变更。
- 本记录不包含：
  - `predictedTouches` 是否开启的决策。
  - GPU 初始化失败根因的调查与修复。
  - 任何提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date +"%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统自带 date 命令生成本次 sticky fallback 记录文件的时间戳前缀。
20260522_170207_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 确认当前工作区里与本轮 sticky fallback 修复对应的实际改动文件。
 M MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
 M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
 M MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
# 功能说明: 汇总本轮 sticky fallback 修复的改动规模，不贴原始 git diff。
.../Rendering/HandDrawingRenderingContracts.swift  | 45 ++++++++++++
.../UI/HandDrawingCanvasSurfaceView.swift          | 83 ++++++++++++++++------
.../HandDrawingRenderingContractsTests.swift       | 37 ++++++++++
3 files changed, 142 insertions(+), 23 deletions(-)
```

## 当前 changes 摘要

- `HandDrawingRenderingContracts.swift` 新增 `HandDrawingRealtimeDraftHostSwitchAction` 和 `HandDrawingRealtimeDraftHostRoutingState`，把 realtime draft host 的切换语义从 view 内联判断，收口成可复用、可测试的状态机。
- `HandDrawingRealtimeDraftHostView` 不再只靠 `activeBackend` 判断是否切 host，而是显式区分“当前装着什么 renderer”与“当前 resolved backend 请求是否已经被满足”。
- 当 `gpuPreferred` 首次创建 GPU renderer 失败时，路由状态会把这次 resolved backend 请求标记为“已由 CPU fallback 满足”，后续 revision 不会再次尝试创建 GPU renderer。
- `HandDrawingGPURealtimeDraftRendererView.makeIfSupported()` 不再静默 `try?` 吞掉错误，而是在 `DEBUG` 下保留一次性的 GPU setup 失败日志，便于后续继续追根因。
- 新增两条测试，分别锁定：
  - GPU 首次失败后 CPU fallback 会保持 sticky，不再重试。
  - 显式切回 CPU 后，再次请求 GPU 时允许重试。

## 修改一：把 fallback 切换语义抽成显式路由状态机

### 修改前

- contracts 层只有 `HandDrawingRealtimeDraftBackendPreference`，只声明“偏好 CPU / 偏好 GPU”。
- 没有一个数据结构去记录“当前装进去的 renderer backend”和“当前 resolved backend 请求是否已经被满足”。
- 结果是：sticky fallback 只能依赖 `HandDrawingRealtimeDraftHostView` 的瞬时判断，无法被单独测试，也无法表达“GPU 请求已被 CPU fallback 接住”的状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift（修改前）
// 函数名: HandDrawingRealtimeDraftBackendPreference
// 功能说明: 修改前 contracts 层只有 backend 偏好枚举，没有 sticky fallback 路由状态。
enum HandDrawingRealtimeDraftBackendPreference: Equatable {
    case cpu
    case gpuPreferred
}
```

### 修改后

- 新增 `HandDrawingRealtimeDraftHostSwitchAction`，把 host 层允许执行的切换动作限制为 `.none / .installCPU / .installGPU`。
- 新增 `HandDrawingRealtimeDraftHostRoutingState`，显式维护：
  - `installedRendererBackend`：当前真的装在 view 上的 renderer backend。
  - `satisfiedResolvedBackend`：当前 resolved backend 请求是否已经被满足。
- `resolveSwitchAction(...)` 在 `gpuPreferred` 首次失败时会把 `satisfiedResolvedBackend` 记成 `.gpuPreferred`，即“这次 GPU 请求已由 CPU fallback 兜住”，后续相同 resolved backend 直接返回 `.none`，不再重试。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Rendering/HandDrawingRenderingContracts.swift
// 函数名: HandDrawingRealtimeDraftHostSwitchAction / HandDrawingRealtimeDraftHostRoutingState.resolveSwitchAction(for:gpuRendererCreationSucceeded:)
// 功能说明: 修改后用显式状态机记录 sticky fallback 的切换语义，避免 host 每次 revision 都重新猜 backend。
enum HandDrawingRealtimeDraftHostSwitchAction: Equatable {
    case none
    case installCPU
    case installGPU
}

struct HandDrawingRealtimeDraftHostRoutingState: Equatable {
    private(set) var installedRendererBackend: HandDrawingRealtimeDraftBackendPreference = .cpu
    private(set) var satisfiedResolvedBackend: HandDrawingRealtimeDraftBackendPreference = .cpu

    mutating func resolveSwitchAction(
        for resolvedBackend: HandDrawingRealtimeDraftBackendPreference,
        gpuRendererCreationSucceeded: Bool? = nil
    ) -> HandDrawingRealtimeDraftHostSwitchAction {
        guard resolvedBackend != satisfiedResolvedBackend else {
            return .none
        }

        switch resolvedBackend {
        case .cpu:
            satisfiedResolvedBackend = .cpu
            guard installedRendererBackend != .cpu else {
                return .none
            }
            installedRendererBackend = .cpu
            return .installCPU
        case .gpuPreferred:
            satisfiedResolvedBackend = .gpuPreferred
            let didCreateGPUHost = gpuRendererCreationSucceeded ?? false
            if didCreateGPUHost {
                guard installedRendererBackend != .gpuPreferred else {
                    return .none
                }
                installedRendererBackend = .gpuPreferred
                return .installGPU
            }
            guard installedRendererBackend != .cpu else {
                return .none
            }
            installedRendererBackend = .cpu
            return .installCPU
        }
    }
}
```

## 修改二：host 不再每个 revision 都重试 GPU 初始化

### 修改前

- `HandDrawingRealtimeDraftHostView` 只维护 `activeBackend`。
- 进入 `gpuPreferred` 时，只要 `resolvedBackend != activeBackend`，就会再次尝试 `HandDrawingGPURealtimeDraftRendererView.makeIfSupported()`。
- 一旦 GPU 初始化失败，host 会再次安装一个新的 CPU renderer，但 `activeBackend` 仍然只是 `.cpu`。
- 下一次 revision 到来时，`resolvedBackend` 还是 `.gpuPreferred`，又会和 `.cpu` 不相等，于是再次重试 GPU，形成“GPU 失败 -> 新 CPU host -> accumulator 重置 -> 下个 revision 再试 GPU”的循环。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingRealtimeDraftHostView.installPreferredRendererIfNeeded(for:)
// 功能说明: 修改前 host 只看 activeBackend，GPU 失败后不会记住“这次 gpuPreferred 已被 CPU fallback 满足”。
private final class HandDrawingRealtimeDraftHostView: UIView {
    private var rendererHost: HandDrawingRealtimeDraftRendererHosting
    private var activeBackend: HandDrawingRealtimeDraftBackendPreference = .cpu

    private func installPreferredRendererIfNeeded(
        for preferredBackend: HandDrawingRealtimeDraftBackendPreference
    ) {
        let resolvedBackend = Self.resolveBackend(from: preferredBackend)
        guard resolvedBackend != activeBackend else {
            return
        }

        let installedBackend: HandDrawingRealtimeDraftBackendPreference
        switch resolvedBackend {
        case .cpu:
            setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            installedBackend = .cpu
        case .gpuPreferred:
            #if canImport(MetalKit)
            if let gpuRendererHost = HandDrawingGPURealtimeDraftRendererView.makeIfSupported() {
                setRendererHost(gpuRendererHost)
                installedBackend = .gpuPreferred
            } else {
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
                installedBackend = .cpu
            }
            #else
            setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            installedBackend = .cpu
            #endif
        }
        activeBackend = installedBackend
    }
}
```

### 修改后

- host 初始化时会根据当前 renderer host 生成 `routingState` 初始值。
- `installPreferredRendererIfNeeded(...)` 不再直接比较 `resolvedBackend != activeBackend`，而是交给 `routingState.resolveSwitchAction(...)`。
- 当 `gpuPreferred` 首次创建失败后，`routingState.satisfiedResolvedBackend` 会被置为 `.gpuPreferred`，因此同一会话里后续 revision 会直接返回，不再重复创建新的 CPU host。
- 只有在 resolved backend 明确切回 `.cpu` 后，再次进入 `.gpuPreferred`，才允许重新尝试 GPU。
- 同文件里，`touchesEnded` 改成先保存 `inputBatch` 再回调，只是把 ended 路径的数据流写法和 moved 路径对齐，不改变行为语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingRealtimeDraftHostView.init(rendererHost:) / HandDrawingRealtimeDraftHostView.installPreferredRendererIfNeeded(for:) / HandDrawingRealtimeDraftHostView.installedBackend(for:)
// 功能说明: 修改后 host 用 routingState 持久化 sticky fallback 状态，GPU 首次失败后不会在后续 revision 中再次重试。
private final class HandDrawingRealtimeDraftHostView: UIView {
    private var rendererHost: HandDrawingRealtimeDraftRendererHosting
    private var routingState: HandDrawingRealtimeDraftHostRoutingState

    init(
        rendererHost: HandDrawingRealtimeDraftRendererHosting = HandDrawingCPURealtimeDraftRendererView()
    ) {
        self.rendererHost = rendererHost
        let initialBackend = Self.installedBackend(for: rendererHost)
        routingState = HandDrawingRealtimeDraftHostRoutingState(
            installedRendererBackend: initialBackend,
            satisfiedResolvedBackend: initialBackend
        )
        super.init(frame: .zero)
        installRendererHost(rendererHost)
    }

    private func installPreferredRendererIfNeeded(
        for preferredBackend: HandDrawingRealtimeDraftBackendPreference
    ) {
        let resolvedBackend = Self.resolveBackend(from: preferredBackend)
        switch resolvedBackend {
        case .cpu:
            let switchAction = routingState.resolveSwitchAction(for: .cpu)
            if switchAction == .installCPU {
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            }
        case .gpuPreferred:
            #if canImport(MetalKit)
            guard routingState.satisfiedResolvedBackend != .gpuPreferred else {
                return
            }
            let gpuRendererHost = HandDrawingGPURealtimeDraftRendererView
                .makeIfSupported()
            let switchAction = routingState.resolveSwitchAction(
                for: .gpuPreferred,
                gpuRendererCreationSucceeded: gpuRendererHost != nil
            )
            switch switchAction {
            case .none:
                break
            case .installCPU:
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            case .installGPU:
                guard let gpuRendererHost else {
                    return
                }
                setRendererHost(gpuRendererHost)
            }
            #else
            let switchAction = routingState.resolveSwitchAction(for: .cpu)
            if switchAction == .installCPU {
                setRendererHost(HandDrawingCPURealtimeDraftRendererView())
            }
            #endif
        }
    }
}
```

## 修改三：GPU setup 失败不再静默吞掉

### 修改前

- `HandDrawingGPURealtimeDraftRendererView.makeIfSupported()` 直接 `return try? ...`。
- 这样 GPU setup 报错时，调用方只能拿到 `nil`，没有任何直接证据说明是 `commandQueueUnavailable`、`pipelineFunctionMissing` 还是其他初始化异常。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported()
// 功能说明: 修改前 GPU setup 失败会被 try? 静默吞掉，调用方只能感知到返回 nil。
static func makeIfSupported() -> HandDrawingGPURealtimeDraftRendererView? {
    guard let device = MTLCreateSystemDefaultDevice() else {
        return nil
    }
    return try? HandDrawingGPURealtimeDraftRendererView(device: device)
}
```

### 修改后

- 改成 `do-catch`，保留一次性的 `DEBUG` 日志。
- 这次修复本身并不解决 GPU 初始化失败，但至少不再把 setup error 完全吞掉，方便下一轮继续追根因。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: HandDrawingGPURealtimeDraftRendererView.makeIfSupported()
// 功能说明: 修改后保留一次性的 GPU setup 失败日志，同时仍然安全返回 nil 走 CPU fallback。
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
            "failedToCreateRenderer error=\\(error)"
        )
        #endif
        return nil
    }
}
```

## 修改四：补齐 sticky fallback 回归测试

### 修改前

- `HandDrawingRenderingContractsTests` 只覆盖 packet、render state、committed canvas request 等契约。
- 没有一条测试能证明：
  - GPU 首次失败后 fallback 会保持 sticky。
  - 显式切回 CPU 后再次请求 GPU 时允许重试。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift（修改前）
// 函数名: testHandDrawingRealtimeDraftRenderStateExposesRenderSnapshotsForCommittedAndPredictedSegments()
// 功能说明: 修改前测试只覆盖 render state 暴露 renderSnapshots 的契约，还没有 sticky fallback 路由语义的测试。
func testHandDrawingRealtimeDraftRenderStateExposesRenderSnapshotsForCommittedAndPredictedSegments() {
    let stroke = makeHandDrawingTestStroke()
    let resolvedStamps = HandDrawingBrushDynamics.resolvedStamps(for: stroke)
    let state = HandDrawingRealtimeDraftRenderState(
        brush: stroke.brush,
        committedResolvedStamps: Array(resolvedStamps.prefix(2)),
        predictedResolvedStamps: Array(resolvedStamps.suffix(2))
    )

    XCTAssertEqual(state.renderSnapshots.count, 2)
    XCTAssertEqual(state.committedRenderSnapshot?.color, stroke.brush.color)
    XCTAssertEqual(state.predictedRenderSnapshot?.color, stroke.brush.color)
}
```

### 修改后

- 新增 `testHandDrawingRealtimeDraftHostRoutingStateMakesCPUFallbackStickyAfterGPUFailure()`：
  - 第一次请求 `gpuPreferred` 且 GPU 创建失败时，断言返回 `.none`，并保留 CPU 已安装状态。
  - 第二次再次请求 `gpuPreferred` 即便假设“这次能创建成功”，也仍然断言返回 `.none`，证明 sticky fallback 生效。
- 新增 `testHandDrawingRealtimeDraftHostRoutingStateAllowsExplicitRetryAfterCPUReset()`：
  - 先模拟失败。
  - 再显式解析一次 `.cpu`。
  - 最后重新请求 `.gpuPreferred` 且创建成功，断言返回 `.installGPU`，证明“CPU reset 后允许重试”的通路仍然打开。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests.swift
// 函数名: testHandDrawingRealtimeDraftHostRoutingStateMakesCPUFallbackStickyAfterGPUFailure() / testHandDrawingRealtimeDraftHostRoutingStateAllowsExplicitRetryAfterCPUReset()
// 功能说明: 修改后用两条测试分别锁定“GPU 首次失败后 sticky fallback”和“显式 CPU reset 后允许重试 GPU”。
func testHandDrawingRealtimeDraftHostRoutingStateMakesCPUFallbackStickyAfterGPUFailure() {
    var routingState = HandDrawingRealtimeDraftHostRoutingState()

    let firstAttempt = routingState.resolveSwitchAction(
        for: .gpuPreferred,
        gpuRendererCreationSucceeded: false
    )
    let secondAttempt = routingState.resolveSwitchAction(
        for: .gpuPreferred,
        gpuRendererCreationSucceeded: true
    )

    XCTAssertEqual(firstAttempt, .none)
    XCTAssertEqual(secondAttempt, .none)
    XCTAssertEqual(routingState.installedRendererBackend, .cpu)
    XCTAssertEqual(routingState.satisfiedResolvedBackend, .gpuPreferred)
}

func testHandDrawingRealtimeDraftHostRoutingStateAllowsExplicitRetryAfterCPUReset() {
    var routingState = HandDrawingRealtimeDraftHostRoutingState()
    _ = routingState.resolveSwitchAction(
        for: .gpuPreferred,
        gpuRendererCreationSucceeded: false
    )

    let resetToCPU = routingState.resolveSwitchAction(for: .cpu)
    let retryGPU = routingState.resolveSwitchAction(
        for: .gpuPreferred,
        gpuRendererCreationSucceeded: true
    )

    XCTAssertEqual(resetToCPU, .none)
    XCTAssertEqual(retryGPU, .installGPU)
    XCTAssertEqual(routingState.installedRendererBackend, .gpuPreferred)
    XCTAssertEqual(routingState.satisfiedResolvedBackend, .gpuPreferred)
}
```

## 验证

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvasPhase7StickyFallbackiOSBuild"
# 功能说明: 验证 sticky fallback 改动不会破坏 iOS 目标编译。
** BUILD SUCCEEDED **
exit_code: 0
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/HandDrawingRenderingContractsTests -derivedDataPath "/tmp/MyCanvasPhase7StickyFallbackMacTests"
# 功能说明: 验证 realtime draft routing contract 及本轮新增 sticky fallback 测试全部通过。
** TEST SUCCEEDED **
Test case 'HandDrawingRenderingContractsTests.testHandDrawingRealtimeDraftHostRoutingStateAllowsExplicitRetryAfterCPUReset()' passed
Test case 'HandDrawingRenderingContractsTests.testHandDrawingRealtimeDraftHostRoutingStateMakesCPUFallbackStickyAfterGPUFailure()' passed
exit_code: 0
```

## 结论

- 这次修复解决的是“GPU 初始化失败后 repeated fallback 导致 CPU renderer 反复重建”的根因链路。
- 修完后，realtime draft host 在一次 GPU setup 失败后会稳定停在同一个 CPU renderer 上，避免移动中的 draft trajectory 因 accumulator 被重置而丢历史。
- 下一步如果继续追手写体验问题，应该分成两个独立方向看：
  - GPU 初始化失败的具体原因。
  - `predictedTouches` 是否需要开启。
