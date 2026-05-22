# 20260522_102448_CST_hand_drawing_brush_engine_phase2_input_builder_record

## 记录范围

- 记录内容：
  - 实施手绘笔刷引擎方案一的 `phase 2`，新增共享 `InputNormalizer` 与 `StrokeBuilder`，把草稿链路与提交链路的样本构造统一到同一套共享入口。
  - 收缩 `iOS` 平台层职责：`HandDrawingCanvasSurfaceView` 只负责产出原始 Pencil 样本，不再在平台层提前做最小 pressure clamp。
  - 调整 `HandDrawingEditorCoordinator` 与 `HandDrawingEditorEngine`，让 `draftStroke` 与 `appendStroke(brush:samples:)` 不再各自手写一套 `HandDrawingInputSample -> HandDrawingSamplePoint` 映射。
  - 新增归一化与 builder 回归测试，锁定 phase 2 的输入合同。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift`
  - `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift`
  - `MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift`
  - `MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift`
- 参考现状：
  - 生成本记录前，执行系统 `date` 命令得到时间戳：`20260522_102448_CST`，本文件按该时间戳命名。
  - 生成本记录前，针对本次已跟踪文件执行 `git diff --stat -- ...`，结果为：`3 files changed, 27 insertions(+), 40 deletions(-)`。
  - 生成本记录前，针对本次相关文件执行 `git status --short -- ...`，结果显示：
    - 3 个已跟踪修改文件：`HandDrawingEditorEngine.swift`、`HandDrawingEditorCoordinator.swift`、`HandDrawingCanvasSurfaceView.swift`
    - 4 个新增未跟踪文件：`HandDrawingInputNormalizer.swift`、`HandDrawingStrokeBuilder.swift`、`HandDrawingInputNormalizerTests.swift`、`HandDrawingStrokeBuilderTests.swift`
  - 因此，本记录同时参考 `git diff` 与 `current changes`；新增文件由 `git status` 与当前文件内容共同说明。
- 本记录不包含：
  - `phase 1` 的 `BrushDynamics` 与统一半径求解器重构记录。
  - `phase 3` 的 tilt-aware stamp 渲染与几何升级。
  - 任何 `.md` 之外的提交操作。

## 命名与当前 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_CST"
# 功能说明: 使用系统命令生成本次 phase 2 markdown 记录文件的时间戳前缀。
20260522_102448_CST
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
# 功能说明: 汇总本次 phase 2 已跟踪文件的 diff 统计；新增未跟踪文件不会出现在这里。
.../Editing/HandDrawingEditorEngine.swift          | 18 +++------
.../HandDrawingEditorCoordinator.swift             | 47 ++++++++++------------
.../UI/HandDrawingCanvasSurfaceView.swift          |  2 +-
3 files changed, 27 insertions(+), 40 deletions(-)
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short -- MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
# 功能说明: 记录本次 phase 2 触达文件的当前 changes 状态，补充显示新增未跟踪文件。
M MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
M MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift
?? MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift
?? MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift
?? MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
```

## 当前 changes 摘要

- 新增 `HandDrawingInputNormalizer`，把原始输入样本的清洗、最小间距过滤、近重复样本替换、时间戳单调化、force 与角度归一化集中到共享层。
- 新增 `HandDrawingStrokeBuilder`，统一把 `HandDrawingInputSample` 构造成 `HandDrawingSamplePoint` / `HandDrawingStroke`，成为 `draftStroke` 与 `appendStroke(brush:samples:)` 的共同入口。
- `HandDrawingEditorEngine.appendStroke(brush:samples:)` 不再自己 map 样本，而是委托给共享 builder。
- `HandDrawingEditorCoordinator` 不再维护“未经归一化的 active 样本 + 手写 draft 映射”，而是维护 `activeStrokeInputSamples`，并统一走 normalizer + builder。
- `HandDrawingCanvasSurfaceView` 取消平台层最小 pressure clamp，把 `force` 原始值直接传给共享层，由 normalizer 负责兜底。
- 新增 `HandDrawingInputNormalizerTests` 和 `HandDrawingStrokeBuilderTests`，锁定 phase 2 合同。

## 修改一：新增共享 `HandDrawingInputNormalizer`

### 修改前

- `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift` 文件不存在。
- `coordinator` 只做了非常局部的“最后一个样本完全相等就跳过”，没有统一处理：
  - 最小间距过滤
  - 邻近样本替换
  - 时间戳单调性
  - 非法坐标/角度
  - force clamp

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift（修改前文件不存在）
// 函数名: 无（新增文件）
// 功能说明: 修改前没有共享输入归一化器，输入清洗逻辑分散在平台层与 coordinator 的局部实现中。
// 文件不存在
```

### 修改后

- 新增 `HandDrawingInputNormalizer.Configuration`，显式定义：
  - `minimumSampleDistance`
  - `minimumTimestampDelta`
  - `minimumForce`
  - `maximumForce`
- 新增 `normalized(_:appendingTo:configuration:)`，支持持续把新输入追加到既有样本序列。
- 统一处理：
  - 非法坐标丢弃
  - 非法时间戳回落
  - force clamp
  - 非法角度清空
  - 邻近样本替换
  - 时间戳强制单调递增

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingInputNormalizer.swift
// 函数名: HandDrawingInputNormalizer.normalized(_:appendingTo:configuration:) / sanitized(_:previousSample:configuration:)
// 功能说明: 修改后共享输入归一化器统一负责原始 Pencil 样本到编辑器共享样本的清洗与归一化。
enum HandDrawingInputNormalizer {
    struct Configuration: Equatable {
        static let brushStroke = Configuration()

        let minimumSampleDistance: CGFloat
        let minimumTimestampDelta: TimeInterval
        let minimumForce: CGFloat
        let maximumForce: CGFloat
    }

    static func normalized(
        _ rawSamples: [HandDrawingInputSample],
        appendingTo existingSamples: [HandDrawingInputSample] = [],
        configuration: Configuration = .brushStroke
    ) -> [HandDrawingInputSample] {
        var normalizedSamples = existingSamples

        for rawSample in rawSamples {
            guard
                var sample = sanitized(
                    rawSample,
                    previousSample: normalizedSamples.last,
                    configuration: configuration
                )
            else {
                continue
            }

            if let previousSample = normalizedSamples.last {
                let distance = hypot(
                    sample.location.x - previousSample.location.x,
                    sample.location.y - previousSample.location.y
                )
                if distance < configuration.minimumSampleDistance {
                    normalizedSamples[normalizedSamples.count - 1] = sample
                    continue
                }

                if sample.timestamp <= previousSample.timestamp {
                    sample.timestamp = previousSample.timestamp
                        + configuration.minimumTimestampDelta
                }
            }

            normalizedSamples.append(sample)
        }

        return normalizedSamples
    }
}
```

## 修改二：新增共享 `HandDrawingStrokeBuilder`

### 修改前

- `MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift` 文件不存在。
- `HandDrawingEditorEngine` 和 `HandDrawingEditorCoordinator` 都各自手写了一份 `HandDrawingInputSample -> HandDrawingSamplePoint` 的映射逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift（修改前文件不存在）
// 函数名: 无（新增文件）
// 功能说明: 修改前没有共享 stroke builder，草稿链路与提交链路各自维护一份样本构造逻辑。
// 文件不存在
```

### 修改后

- 新增 `makeStroke(brush:samples:transform:normalization:)`，允许直接从原始输入样本构造 stroke。
- 新增 `makeStroke(brush:normalizedSamples:transform:)`，允许 coordinator 在已经归一化后直接生成草稿或提交 stroke。
- 新增 `makeSamplePoints(from:)` / `makeSamplePoints(fromNormalizedSamples:)`，把 sample point 映射逻辑收敛到同一入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingStrokeBuilder.swift
// 函数名: makeStroke(brush:samples:transform:normalization:) / makeStroke(brush:normalizedSamples:transform:) / makeSamplePoints(fromNormalizedSamples:)
// 功能说明: 修改后共享 stroke builder 统一负责把输入样本构造成 samplePoints 与 HandDrawingStroke，成为 draft 与 commit 的共同样本真相源。
enum HandDrawingStrokeBuilder {
    static func makeStroke(
        brush: HandDrawingBrushStyle,
        samples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity,
        normalization: HandDrawingInputNormalizer.Configuration = .brushStroke
    ) -> HandDrawingStroke? {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            samples,
            configuration: normalization
        )
        return makeStroke(
            brush: brush,
            normalizedSamples: normalizedSamples,
            transform: transform
        )
    }

    static func makeStroke(
        brush: HandDrawingBrushStyle,
        normalizedSamples: [HandDrawingInputSample],
        transform: HandDrawingStrokeTransform = .identity
    ) -> HandDrawingStroke? {
        let samplePoints = makeSamplePoints(
            fromNormalizedSamples: normalizedSamples
        )
        guard samplePoints.isEmpty == false else {
            return nil
        }
        return HandDrawingStroke(
            brush: brush,
            samplePoints: samplePoints,
            transform: transform
        )
    }

    static func makeSamplePoints(
        fromNormalizedSamples normalizedSamples: [HandDrawingInputSample]
    ) -> [HandDrawingSamplePoint] {
        normalizedSamples.map {
            HandDrawingSamplePoint(
                point: $0.location,
                force: Double($0.force),
                timestamp: $0.timestamp,
                azimuthRadians: $0.azimuthRadians.map(Double.init),
                altitudeRadians: $0.altitudeRadians.map(Double.init)
            )
        }
    }
}
```

## 修改三：`HandDrawingEditorEngine` 改为委托共享 builder

### 修改前

- `appendStroke(brush:samples:transform:)` 在 `engine` 内部直接把输入样本 map 成 `HandDrawingSamplePoint`。
- 这导致提交链路自己维护一份样本映射语义，和草稿链路并不共享同一个 builder。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift（修改前）
// 函数名: appendStroke(brush:samples:transform:)
// 功能说明: 修改前 engine 在提交时自己把输入样本逐个映射成 samplePoints，没有共享 builder。
mutating func appendStroke(
    brush: HandDrawingBrushStyle,
    samples: [HandDrawingInputSample],
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke? {
    guard samples.isEmpty == false else {
        return nil
    }
    let stroke = HandDrawingStroke(
        brush: brush,
        samplePoints: samples.map {
            HandDrawingSamplePoint(
                point: $0.location,
                force: Double($0.force),
                timestamp: $0.timestamp,
                azimuthRadians: $0.azimuthRadians.map(Double.init),
                altitudeRadians: $0.altitudeRadians.map(Double.init)
            )
        },
        transform: transform
    )
    return appendStroke(stroke)
}
```

### 修改后

- `engine` 改为直接委托 `HandDrawingStrokeBuilder.makeStroke(...)`。
- 如果 builder 返回 `nil`，则视为没有有效样本，不提交 stroke。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/HandDrawing/Editing/HandDrawingEditorEngine.swift
// 函数名: appendStroke(brush:samples:transform:)
// 功能说明: 修改后 engine 不再重复维护输入到 samplePoints 的映射，而是统一委托共享 builder。
mutating func appendStroke(
    brush: HandDrawingBrushStyle,
    samples: [HandDrawingInputSample],
    transform: HandDrawingStrokeTransform = .identity
) -> HandDrawingStroke? {
    guard let stroke = HandDrawingStrokeBuilder.makeStroke(
        brush: brush,
        samples: samples,
        transform: transform
    )
    else {
        return nil
    }
    return appendStroke(stroke)
}
```

## 修改四：`HandDrawingEditorCoordinator` 统一草稿与提交链路

### 修改前

- `coordinator` 维护的是未经共享归一化的 `activeStrokeSamples`。
- `draftStroke` 里直接手写 `activeStrokeSamples.map { HandDrawingSamplePoint(...) }`。
- `appendStrokeSamples(_:)` 只做“与最后一个样本完全相等就跳过”的局部去重。
- 抬笔提交时，把 `activeStrokeSamples` 原样交给 `engine.appendStroke(...)`，仍然要再走一遍另一套映射。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift（修改前）
// 函数名: draftStroke / appendStrokeSamples(_:) / handlePencilStrokeEnded(_:)
// 功能说明: 修改前 coordinator 的草稿链路和提交链路各自维护一份样本处理语义，容易出现“预览一套、提交一套”。
private var activeStrokeSamples: [HandDrawingInputSample] = []

private var draftStroke: HandDrawingStroke? {
    guard
        let activeStrokeBrush,
        activeStrokeSamples.isEmpty == false
    else {
        return nil
    }
    return HandDrawingStroke(
        brush: activeStrokeBrush,
        samplePoints: activeStrokeSamples.map {
            HandDrawingSamplePoint(
                point: $0.location,
                force: Double($0.force),
                timestamp: $0.timestamp,
                azimuthRadians: $0.azimuthRadians.map(Double.init),
                altitudeRadians: $0.altitudeRadians.map(Double.init)
            )
        }
    )
}

private func appendStrokeSamples(_ samples: [HandDrawingInputSample]) {
    for sample in samples {
        if activeStrokeSamples.last == sample {
            continue
        }
        activeStrokeSamples.append(sample)
    }
}

// ... 抬笔时再把 activeStrokeSamples 交给 engine.appendStroke(brush:samples:) ...
```

### 修改后

- `coordinator` 改为维护 `activeStrokeInputSamples`，它始终保存共享 normalizer 处理后的输入样本。
- `touch began` 时就先归一化首样本。
- `appendStrokeSamples(_:)` 统一走 `HandDrawingInputNormalizer.normalized(..., appendingTo:)`。
- `draftStroke` 直接走 `HandDrawingStrokeBuilder.makeStroke(brush:normalizedSamples:)`。
- 抬笔提交也先用相同 builder 构造 `committedStroke`，再交给 `engine.appendStroke(_:)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/Presentation/HandDrawingEditorCoordinator.swift
// 函数名: handlePencilStrokeBegan(_:) / handlePencilStrokeEnded(_:) / draftStroke / appendStrokeSamples(_:)
// 功能说明: 修改后 coordinator 统一缓存已归一化的输入样本，并让 draft 与 commit 共享同一 builder。
private var activeStrokeInputSamples: [HandDrawingInputSample] = []

func handlePencilStrokeBegan(_ sample: HandDrawingInputSample) {
    // ... 省略 guard 与 tool 分支 ...
    activeStrokeBrush = currentBrushStyle
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        [sample]
    )
    publishSurfaceState()
}

func handlePencilStrokeEnded(_ samples: [HandDrawingInputSample]) {
    // ... 省略 guard 与 tool 分支 ...
    appendStrokeSamples(samples)
    guard activeStrokeInputSamples.isEmpty == false else {
        clearActiveStroke()
        publishSurfaceState()
        return
    }
    let committedStroke = HandDrawingStrokeBuilder.makeStroke(
        brush: activeStrokeBrush,
        normalizedSamples: activeStrokeInputSamples
    )
    clearActiveStroke()
    guard
        let committedStroke,
        engine.appendStroke(committedStroke) != nil
    else {
        publishSurfaceState()
        publishPaletteState()
        return
    }
    refreshCommittedImageAndPublishState()
}

private var draftStroke: HandDrawingStroke? {
    guard
        let activeStrokeBrush,
        activeStrokeInputSamples.isEmpty == false
    else {
        return nil
    }
    return HandDrawingStrokeBuilder.makeStroke(
        brush: activeStrokeBrush,
        normalizedSamples: activeStrokeInputSamples
    )
}

private func appendStrokeSamples(_ samples: [HandDrawingInputSample]) {
    activeStrokeInputSamples = HandDrawingInputNormalizer.normalized(
        samples,
        appendingTo: activeStrokeInputSamples
    )
}
```

## 修改五：平台层回退为原始输入采样职责

### 修改前

- `HandDrawingCanvasSurfaceView.makeSample(from:)` 在平台层直接做了最小 force clamp：`max(touch.force / maximumPossibleForce, 0.05)`。
- 这会让共享层无法完全掌控原始输入样本的归一化策略。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift（修改前）
// 函数名: makeSample(from:)
// 功能说明: 修改前平台层在采样时就提前做了最小 pressure clamp。
private func makeSample(from touch: UITouch) -> HandDrawingInputSample? {
    guard touch.type == .pencil else {
        return nil
    }
    let maximumPossibleForce = max(touch.maximumPossibleForce, 1)
    return HandDrawingInputSample(
        location: touch.location(in: self),
        force: max(touch.force / maximumPossibleForce, 0.05),
        timestamp: touch.timestamp,
        azimuthRadians: touch.azimuthAngle(in: self),
        altitudeRadians: touch.altitudeAngle
    )
}
```

### 修改后

- 平台层直接上传 `touch.force / maximumPossibleForce`。
- 最小值 clamp 改由共享 `HandDrawingInputNormalizer` 统一处理。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/HandDrawing/UI/HandDrawingCanvasSurfaceView.swift
// 函数名: makeSample(from:)
// 功能说明: 修改后平台层只负责产出原始 Pencil 样本，pressure clamp 统一延后到共享 normalizer。
private func makeSample(from touch: UITouch) -> HandDrawingInputSample? {
    guard touch.type == .pencil else {
        return nil
    }
    let maximumPossibleForce = max(touch.maximumPossibleForce, 1)
    return HandDrawingInputSample(
        location: touch.location(in: self),
        force: touch.force / maximumPossibleForce,
        timestamp: touch.timestamp,
        azimuthRadians: touch.azimuthAngle(in: self),
        altitudeRadians: touch.altitudeAngle
    )
}
```

## 修改六：新增 phase 2 回归测试

### 6.1 `HandDrawingInputNormalizerTests.swift`

#### 修改前

- `MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift` 文件不存在。
- 没有任何测试直接锁定：
  - 邻近样本替换
  - 时间戳单调性
  - 非法位置丢弃
  - 角度清洗
  - force clamp

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift（修改前文件不存在）
// 函数名: 无（新增文件）
// 功能说明: 修改前没有 InputNormalizer 的独立回归测试。
// 文件不存在
```

#### 修改后

- 新增 `testHandDrawingInputNormalizerReplacesNearbySamplesAndMonotonizesTimestamps()`
- 新增 `testHandDrawingInputNormalizerDropsSamplesWithInvalidLocations()`
- 直接锁住 phase 2 的输入归一化合同。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests.swift
// 函数名: testHandDrawingInputNormalizerReplacesNearbySamplesAndMonotonizesTimestamps() / testHandDrawingInputNormalizerDropsSamplesWithInvalidLocations()
// 功能说明: 修改后独立测试文件直接锁定输入归一化的核心合同。
final class HandDrawingInputNormalizerTests: XCTestCase {
    func testHandDrawingInputNormalizerReplacesNearbySamplesAndMonotonizesTimestamps() throws {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 10, y: 10),
                    force: 0,
                    timestamp: 1,
                    azimuthRadians: 0.2,
                    altitudeRadians: 0.4
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 10.2, y: 10.2),
                    force: 0.4,
                    timestamp: 0.5,
                    azimuthRadians: .infinity,
                    altitudeRadians: -.infinity
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 12, y: 10),
                    force: 1.4,
                    timestamp: 0.5,
                    azimuthRadians: 0.8,
                    altitudeRadians: 0.6
                )
            ]
        )

        XCTAssertEqual(normalizedSamples.count, 2)
        XCTAssertEqual(normalizedSamples[0].force, 0.4, accuracy: 0.001)
        XCTAssertEqual(normalizedSamples[1].force, 1, accuracy: 0.001)
        XCTAssertNil(normalizedSamples[0].azimuthRadians)
        XCTAssertNil(normalizedSamples[0].altitudeRadians)
    }
}
```

### 6.2 `HandDrawingStrokeBuilderTests.swift`

#### 修改前

- `MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift` 文件不存在。
- 没有任何测试直接证明：
  - builder 会把归一化输入准确映射成 sample points
  - 同一串输入在草稿构造与最终提交时 samplePoints 完全一致

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift（修改前文件不存在）
// 函数名: 无（新增文件）
// 功能说明: 修改前没有 StrokeBuilder 的独立回归测试。
// 文件不存在
```

#### 修改后

- 新增 `testHandDrawingStrokeBuilderBuildsSamplePointsFromNormalizedInputSamples()`
- 新增 `testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent()`
- 第二个测试直接把 phase 2 的核心合同钉住：同一串输入，`draftStroke` 与 `engine.appendStroke(...)` 产出的 samplePoints 必须一致。

```swift
// 文件路径: MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests.swift
// 函数名: testHandDrawingStrokeBuilderBuildsSamplePointsFromNormalizedInputSamples() / testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent()
// 功能说明: 修改后独立测试文件锁定共享 builder 的 sample 映射正确性，以及 draft / commit 一致性。
@MainActor
final class HandDrawingStrokeBuilderTests: XCTestCase {
    func testHandDrawingStrokeBuilderBuildsSamplePointsFromNormalizedInputSamples() throws {
        let normalizedSamples = HandDrawingInputNormalizer.normalized(
            [
                HandDrawingInputSample(
                    location: CGPoint(x: 18, y: 20),
                    force: 0.3,
                    timestamp: 0,
                    azimuthRadians: 0.1,
                    altitudeRadians: 0.9
                ),
                HandDrawingInputSample(
                    location: CGPoint(x: 54, y: 44),
                    force: 0.8,
                    timestamp: 0.2,
                    azimuthRadians: 0.4,
                    altitudeRadians: 0.7
                )
            ]
        )

        let samplePoints = HandDrawingStrokeBuilder.makeSamplePoints(
            fromNormalizedSamples: normalizedSamples
        )
        XCTAssertEqual(samplePoints.count, 2)
    }

    func testHandDrawingStrokeBuilderDraftAndCommittedStrokeStaySampleEquivalent() throws {
        // ... 省略原始输入构造 ...
        let normalizedSamples = HandDrawingInputNormalizer.normalized(rawSamples)
        let draftStroke = try XCTUnwrap(
            HandDrawingStrokeBuilder.makeStroke(
                brush: brush,
                normalizedSamples: normalizedSamples
            )
        )
        var engine = HandDrawingEditorEngine(
            document: HandDrawingDocument(
                paper: HandDrawingPaper(
                    id: "phase2-paper",
                    size: CGSize(width: 120, height: 120)
                )
            )
        )

        let committedStroke = try XCTUnwrap(
            engine.appendStroke(
                brush: brush,
                samples: rawSamples
            )
        )

        XCTAssertEqual(draftStroke.samplePoints, committedStroke.samplePoints)
    }
}
```

## 验证情况

- `ReadLints` 检查本次 phase 2 修改文件：无新增诊断。
- `macOS` 定向手绘测试通过。
- `iOS Simulator` 构建通过，覆盖本次改到的平台侧代码路径。

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasPhase2Tests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 功能说明: 验证 phase 2 新增 normalizer / builder 以及前两阶段既有手绘基线在 macOS 测试链路下继续成立。
xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvasPhase2Tests" -only-testing:MyCanvas_Ver_0Tests/HandDrawingInputNormalizerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingStrokeBuilderTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingBrushDynamicsTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingDocumentCodecTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingEditorEngineTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPreviewRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingCanvasRendererTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingLassoSelectionTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingPixelEraserToolControllerTests -only-testing:MyCanvas_Ver_0Tests/HandDrawingMoveSelectionTests
# 结果: Exit code 0，定向测试通过。
```

```sh
# 文件路径: 无（终端命令）
# 函数名: xcodebuild build -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvasPhase2iOSBuild"
# 功能说明: 验证 phase 2 改动后的 iOS 平台侧 coordinator 与 surface view 能成功进入 iOS Simulator 构建链。
xcodebuild build -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvasPhase2iOSBuild"
# 结果: Exit code 0，iOS Simulator 构建通过。
```

## 结论

- 这次 `phase 2` 的实际落地结果，是把 hand drawing 的草稿输入链路和提交输入链路统一到了同一套 normalizer + builder。
- 现在同一串输入样本，`draftStroke` 和最终提交 stroke 的 sample 级语义已经共享一套真相源；后续进入 `phase 3` 时，可以在这套统一输入基座上继续推进 tilt-aware 渲染，而不再背着“双份样本映射”的结构债。
