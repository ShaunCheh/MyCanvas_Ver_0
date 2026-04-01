# 20260401_173807_video_timeline_phase0_record

## 记录范围

- 记录内容：实施 `@.cursor/plans/视频时间线轨道改造_4a257c8b.plan.md` 的阶段 0，只落“共享时间线契约 + 现有编辑器最小接线 + 纯逻辑测试”。
- 记录内容：本次没有提前实现真正的单轨时间线 UI，也没有改视频导入、poster 持久化、board assets 或上下文菜单链路。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasVideoTimelineContractTests.swift`
- 本记录不包含：git commit / push。

## 修改一：新增共享时间线契约文件，抽出连续时间线的纯值模型

### 修改前

- 工程里只有 `CanvasVideoPreviewStripFrame` / `CanvasVideoPreviewStrip` 这样的离散帧条模型。
- 缺少统一的时间线数学层，无法表达：
- `zoomScale`
- `visibleWidth`
- `contentOffsetX`
- `contentWidth`
- `visibleTimeRange`
- `time <-> contentX`
- 后续 iOS/macOS 如果继续做时间线，只能把这些几何和映射逻辑散落在两个控制器里重复实现。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前工程内没有独立的共享时间线契约文件，视频编辑页只能围绕离散 preview strip 做“按索引选帧”。
// 文件不存在。
```

### 修改后

- 新增 `CanvasVideoTimeline.swift`，把阶段 0 需要的基础抽象一次性收口到共享层。
- 主要新增：
- `CanvasVideoTimelineMath`
- `CanvasVideoTimelineScale`
- `CanvasVideoTimelineViewport`
- `CanvasVideoTimelineStripRequest`
- `CanvasVideoTimelineStripResult`
- 这些类型解决的是“时间线数学契约”问题，不直接承担 UI 绘制责任，正好符合阶段 0 的边界。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: CanvasVideoTimelineMath / CanvasVideoTimelineScale / CanvasVideoTimelineViewport
// 功能说明: 修改后新增共享时间线数学与 viewport 契约，统一负责时间边界、缩放密度、可见范围以及 time <-> contentX 的映射。
import Foundation

enum CanvasVideoTimelineMath {
    static let frameBoundaryEpsilonSeconds = 1.0 / 600.0

    static func sanitizedTimeSeconds(_ timeSeconds: Double) -> Double {
        guard timeSeconds.isFinite else {
            return 0
        }

        return max(timeSeconds, 0)
    }

    static func upperBoundTimeSeconds(durationSeconds: Double) -> Double {
        let durationSeconds = sanitizedDurationSeconds(durationSeconds)
        guard durationSeconds > 0 else {
            return 0
        }

        return max(durationSeconds - frameBoundaryEpsilonSeconds, 0)
    }

    static func clampedTimeSeconds(
        _ timeSeconds: Double,
        durationSeconds: Double
    ) -> Double {
        let upperBoundTimeSeconds = upperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
        guard upperBoundTimeSeconds > 0 else {
            return 0
        }

        return min(
            sanitizedTimeSeconds(timeSeconds),
            upperBoundTimeSeconds
        )
    }
}

struct CanvasVideoTimelineScale: Equatable {
    static let defaultBasePointsPerSecond = 18.0
    static let defaultMinZoomScale = 1.0
    static let defaultMaxZoomScale = 32.0

    let zoomScale: Double
    let basePointsPerSecond: Double
    let minZoomScale: Double
    let maxZoomScale: Double

    var pointsPerSecond: Double {
        basePointsPerSecond * zoomScale
    }

    var nominalSecondsPerPoint: Double {
        guard pointsPerSecond > 0 else {
            return 0
        }

        return 1 / pointsPerSecond
    }
}

struct CanvasVideoTimelineViewport: Equatable {
    let durationSeconds: Double
    let playheadTimeSeconds: Double
    let zoomScale: CanvasVideoTimelineScale
    let visibleWidth: Double
    let contentOffsetX: Double
    let minimumContentWidth: Double

    var upperBoundTimeSeconds: Double {
        CanvasVideoTimelineMath.upperBoundTimeSeconds(
            durationSeconds: durationSeconds
        )
    }

    var contentWidth: Double {
        max(intrinsicContentWidth, minimumContentWidth)
    }

    var visibleTimeRange: ClosedRange<Double> {
        timeRange(forContentRange: visibleContentRange)
    }

    var playheadContentX: Double {
        contentX(forTimeSeconds: playheadTimeSeconds)
    }

    func contentX(forTimeSeconds timeSeconds: Double) -> Double {
        guard upperBoundTimeSeconds > 0, contentWidth > 0 else {
            return 0
        }

        let clampedTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: durationSeconds
        )
        return (clampedTimeSeconds / upperBoundTimeSeconds) * contentWidth
    }

    func timeSeconds(forContentX contentX: Double) -> Double {
        guard upperBoundTimeSeconds > 0, contentWidth > 0 else {
            return 0
        }

        let clampedContentX = min(max(contentX, 0), contentWidth)
        return (clampedContentX / contentWidth) * upperBoundTimeSeconds
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: CanvasVideoTimelineStripRequest / CanvasVideoTimelineStripResult
// 功能说明: 修改后新增时间线 strip request/result 契约，用于表达“当前 viewport 需要哪一段缩略图”和“当前 playhead 对应哪一个采样点”。
struct CanvasVideoTimelineStripRequest: Equatable {
    let viewport: CanvasVideoTimelineViewport
    let thumbnailWidth: Double
    let maxPixelSize: Int
    let overscanWidth: Double

    var requestedTimeRange: ClosedRange<Double> {
        viewport.timeRange(forContentRange: requestedContentRange)
    }

    var targetFrameCount: Int {
        let requestedWidth = requestedContentRange.upperBound
            - requestedContentRange.lowerBound
        guard requestedWidth > 0 else {
            return 1
        }

        return max(Int(ceil(requestedWidth / thumbnailWidth)) + 1, 2)
    }

    func sampleTimes(frameCount: Int? = nil) -> [Double] {
        CanvasVideoTimelineMath.evenlySpacedSampleTimes(
            in: requestedTimeRange,
            frameCount: max(frameCount ?? targetFrameCount, 1)
        )
    }
}

struct CanvasVideoTimelineStripResult: Equatable {
    struct Sample: Equatable {
        let timeSeconds: Double
        let contentX: Double
    }

    let request: CanvasVideoTimelineStripRequest
    let samples: [Sample]

    var highlightedSampleIndex: Int? {
        guard samples.isEmpty == false else {
            return nil
        }

        let playheadContentX = request.viewport.playheadContentX
        return samples.enumerated().min { lhs, rhs in
            abs(lhs.element.contentX - playheadContentX)
                < abs(rhs.element.contentX - playheadContentX)
        }?.offset
    }
}
```

## 修改二：让共享视频帧服务复用新的时间边界与采样数学

### 修改前

- `CanvasVideoFrameService` 自己维护了一套 `previewSampleTimes`、`sanitizedTimeSeconds`、`sanitizedDurationSeconds`、`clampedTimeSeconds`、`previewUpperBoundTimeSeconds`。
- 这些时间边界逻辑和后续时间线数学没有共享入口，未来如果时间线缩放或 viewport 规则继续演进，容易出现“服务层一套、控制器一套”的漂移。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: previewSampleTimes(durationSeconds:frameCount:) / sanitizedTimeSeconds(_:) / sanitizedDurationSeconds(_:) / clampedTimeSeconds(_:for:) / previewUpperBoundTimeSeconds(durationSeconds:)
// 功能说明: 修改前 CanvasVideoFrameService 独立维护时间采样与裁剪规则，尚未与即将引入的共享时间线数学打通。
private static func previewSampleTimes(
    durationSeconds: Double,
    frameCount: Int
) -> [Double] {
    guard frameCount > 1 else {
        return [0]
    }

    let upperBound = previewUpperBoundTimeSeconds(
        durationSeconds: durationSeconds
    )
    guard upperBound > 0 else {
        return Array(repeating: 0, count: frameCount)
    }

    let denominator = Double(frameCount - 1)
    return (0..<frameCount).map { index in
        (upperBound * Double(index)) / denominator
    }
}

private static func sanitizedTimeSeconds(
    _ timeSeconds: Double
) -> Double {
    guard timeSeconds.isFinite else {
        return 0
    }

    return max(timeSeconds, 0)
}
```

### 修改后

- `CanvasVideoFrameService` 的采样和边界处理改为直接依赖 `CanvasVideoTimelineMath`。
- 这样后续阶段 1 扩展“缩放感知 strip 服务”时，可以在同一套基础数学上继续演进，而不用再次收口时间规则。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: previewSampleTimes(durationSeconds:frameCount:) / sanitizedTimeSeconds(_:) / sanitizedDurationSeconds(_:) / clampedTimeSeconds(_:for:) / previewUpperBoundTimeSeconds(durationSeconds:)
// 功能说明: 修改后共享视频帧服务统一复用 CanvasVideoTimelineMath，避免时间边界、采样规则在多个层之间继续分叉。
private static func previewSampleTimes(
    durationSeconds: Double,
    frameCount: Int
) -> [Double] {
    let upperBound = previewUpperBoundTimeSeconds(
        durationSeconds: durationSeconds
    )
    return CanvasVideoTimelineMath.evenlySpacedSampleTimes(
        in: 0...upperBound,
        frameCount: frameCount
    )
}

private static func sanitizedTimeSeconds(
    _ timeSeconds: Double
) -> Double {
    CanvasVideoTimelineMath.sanitizedTimeSeconds(timeSeconds)
}

private static func sanitizedDurationSeconds(
    _ duration: CMTime
) -> Double {
    CanvasVideoTimelineMath.sanitizedDurationSeconds(duration.seconds)
}

private static func clampedTimeSeconds(
    _ timeSeconds: Double,
    for asset: AVAsset
) -> Double {
    CanvasVideoTimelineMath.clampedTimeSeconds(
        timeSeconds,
        durationSeconds: sanitizedDurationSeconds(asset.duration)
    )
}

private static func previewUpperBoundTimeSeconds(
    durationSeconds: Double
) -> Double {
    CanvasVideoTimelineMath.upperBoundTimeSeconds(
        durationSeconds: durationSeconds
    )
}
```

## 修改三：iOS 编辑页不再自己维护“最近一帧索引”算法

### 修改前

- iOS 视频编辑页通过 `nearestPreviewFrameIndex(for:)` 直接在 `previewFrames` 里做“当前时间和每个采样时间的绝对值差最小”比较。
- `clampedTimeSeconds(_:)` 也在控制器里自己维护一套时间边界逻辑。
- 这会导致阶段 0 之后，控制器仍然绑定在“离散帧索引”模型上，没有开始切向“共享时间线 viewport + strip result”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:) / nearestPreviewFrameIndex(for:) / clampedTimeSeconds(_:)
// 功能说明: 修改前 iOS 编辑页直接按 preview frame 数组做最近邻比较，并在控制器内维护时间裁剪规则。
private func updateSelectedPreviewFrameIndex(
    for timeSeconds: Double,
    shouldScrollToSelection: Bool
) {
    let nextIndex = nearestPreviewFrameIndex(for: timeSeconds)
    guard selectedPreviewFrameIndex != nextIndex else {
        return
    }
    // ... 省略 reload 与 scroll 逻辑
}

private func nearestPreviewFrameIndex(
    for timeSeconds: Double
) -> Int? {
    guard previewFrames.isEmpty == false else {
        return nil
    }

    return previewFrames.enumerated().min { lhs, rhs in
        abs(lhs.element.timeSeconds - timeSeconds) <
            abs(rhs.element.timeSeconds - timeSeconds)
    }?.offset
}

private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
    guard editorContext.durationSeconds > 0 else {
        return 0
    }

    let upperBound = max(editorContext.durationSeconds - (1.0 / 600.0), 0)
    guard timeSeconds.isFinite else {
        return 0
    }

    return min(max(timeSeconds, 0), upperBound)
}
```

### 修改后

- iOS 控制器新增 `timelineScale`，并通过 `makePreviewStripTimelineResult(for:)` 把当前时间、可见宽度、滚动偏移、缩略图尺寸统一投影到共享时间线契约里。
- 当前高亮的缩略图不再由本地最近邻函数决定，而是改由 `CanvasVideoTimelineStripResult.highlightedSampleIndex` 得出。
- `clampedTimeSeconds(_:)` 也改成走 `CanvasVideoTimelineViewport.clampedTimeSeconds(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: timelineScale / updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:) / clampedTimeSeconds(_:) / makePreviewStripTimelineResult(for:)
// 功能说明: 修改后 iOS 编辑页开始接入共享时间线契约，用统一 viewport 与 strip result 计算当前高亮 sample，而不是继续维持控制器私有的最近邻索引算法。
private let timelineScale = CanvasVideoTimelineScale()

private func updateSelectedPreviewFrameIndex(
    for timeSeconds: Double,
    shouldScrollToSelection: Bool
) {
    let nextIndex = makePreviewStripTimelineResult(
        for: timeSeconds
    ).highlightedSampleIndex
    guard selectedPreviewFrameIndex != nextIndex else {
        return
    }
    // ... 省略 reload 与 scroll 逻辑
}

private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
    CanvasVideoTimelineViewport.clampedTimeSeconds(
        timeSeconds,
        durationSeconds: editorContext.durationSeconds
    )
}

private func makePreviewStripTimelineResult(
    for timeSeconds: Double
) -> CanvasVideoTimelineStripResult {
    let visibleWidth = Double(
        max(previewStripCollectionView.bounds.width, 1)
    )
    let viewport = CanvasVideoTimelineViewport(
        durationSeconds: editorContext.durationSeconds,
        playheadTimeSeconds: timeSeconds,
        zoomScale: timelineScale,
        visibleWidth: visibleWidth,
        contentOffsetX: Double(previewStripCollectionView.contentOffset.x),
        minimumContentWidth: visibleWidth
    )
    let request = CanvasVideoTimelineStripRequest(
        viewport: viewport,
        thumbnailWidth: 92,
        maxPixelSize: 180
    )
    return CanvasVideoTimelineStripResult(
        request: request,
        sampleTimes: previewFrames.map(\.timeSeconds)
    )
}
```

## 修改四：macOS 编辑页同步切到共享时间线契约

### 修改前

- macOS 编辑页和 iOS 一样，也是在控制器里维护了一套 `nearestPreviewFrameIndex(for:)` 与本地 `clampedTimeSeconds(_:)`。
- 双端虽然逻辑相近，但还是各自保留着离散索引驱动的假设，后续时间线缩放会继续复制两份实现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:) / nearestPreviewFrameIndex(for:) / clampedTimeSeconds(_:)
// 功能说明: 修改前 macOS 编辑页同样依赖本地最近邻索引算法和控制器私有时间裁剪，未接入共享时间线数学。
private func updateSelectedPreviewFrameIndex(
    for timeSeconds: Double,
    shouldScrollToSelection: Bool
) {
    let nextIndex = nearestPreviewFrameIndex(for: timeSeconds)
    guard selectedPreviewFrameIndex != nextIndex else {
        return
    }
    // ... 省略 reload 与 selectItems 逻辑
}

private func nearestPreviewFrameIndex(
    for timeSeconds: Double
) -> Int? {
    guard previewFrames.isEmpty == false else {
        return nil
    }

    return previewFrames.enumerated().min { lhs, rhs in
        abs(lhs.element.timeSeconds - timeSeconds) <
            abs(rhs.element.timeSeconds - timeSeconds)
    }?.offset
}

private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
    guard editorContext.durationSeconds > 0 else {
        return 0
    }

    let upperBound = max(editorContext.durationSeconds - (1.0 / 600.0), 0)
    guard timeSeconds.isFinite else {
        return 0
    }

    return min(max(timeSeconds, 0), upperBound)
}
```

### 修改后

- macOS 控制器和 iOS 一样新增 `timelineScale`，并用 `makePreviewStripTimelineResult(for:)` 把当前 scrollView 的几何状态转成统一的时间线 strip result。
- 这样双端在“阶段 0 的选择逻辑”上已经开始共用同一套抽象，后面做真实单轨时间线 UI 时，状态层可以直接承接。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: timelineScale / updateSelectedPreviewFrameIndex(for:shouldScrollToSelection:) / clampedTimeSeconds(_:) / makePreviewStripTimelineResult(for:)
// 功能说明: 修改后 macOS 编辑页也改为通过共享时间线 viewport 与 strip result 计算当前高亮 sample，开始摆脱离散卡片索引驱动。
private let timelineScale = CanvasVideoTimelineScale()

private func updateSelectedPreviewFrameIndex(
    for timeSeconds: Double,
    shouldScrollToSelection: Bool
) {
    let nextIndex = makePreviewStripTimelineResult(
        for: timeSeconds
    ).highlightedSampleIndex
    guard selectedPreviewFrameIndex != nextIndex else {
        return
    }
    // ... 省略 reload 与 selectItems 逻辑
}

private func clampedTimeSeconds(_ timeSeconds: Double) -> Double {
    CanvasVideoTimelineViewport.clampedTimeSeconds(
        timeSeconds,
        durationSeconds: editorContext.durationSeconds
    )
}

private func makePreviewStripTimelineResult(
    for timeSeconds: Double
) -> CanvasVideoTimelineStripResult {
    let visibleWidth = Double(
        max(previewStripScrollView.contentSize.width, 1)
    )
    let viewport = CanvasVideoTimelineViewport(
        durationSeconds: editorContext.durationSeconds,
        playheadTimeSeconds: timeSeconds,
        zoomScale: timelineScale,
        visibleWidth: visibleWidth,
        contentOffsetX: Double(
            previewStripScrollView.contentView.bounds.origin.x
        ),
        minimumContentWidth: visibleWidth
    )
    let request = CanvasVideoTimelineStripRequest(
        viewport: viewport,
        thumbnailWidth: 92,
        maxPixelSize: 180
    )
    return CanvasVideoTimelineStripResult(
        request: request,
        sampleTimes: previewFrames.map(\.timeSeconds)
    )
}
```

## 修改五：新增纯逻辑测试，锁定阶段 0 的时间线契约

### 修改前

- 工程里还没有专门验证“时间线数学”和“缩略图请求几何”的测试。
- 这意味着阶段 0 即便把契约抽出来，也缺少自动化保护，后续阶段 1 和阶段 2/3 容易回归。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineContractTests.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前工程内没有针对视频时间线共享契约的纯逻辑测试文件。
// 文件不存在。
```

### 修改后

- 新增 `CanvasVideoTimelineContractTests.swift`，先把共享层的关键边界锁住。
- 覆盖内容包括：
- zoom clamp 与密度计算
- `time <-> contentX` 往返
- `visibleTimeRange`
- strip request 的 requested range 与 frame count
- playhead 对应 sample 的高亮选择

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineContractTests.swift
// 类型/函数: CanvasVideoTimelineContractTests
// 功能说明: 修改后新增阶段 0 的纯逻辑测试，验证共享时间线契约的几何映射、缩放密度与 strip 采样边界。
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasVideoTimelineContractTests: XCTestCase {
    func testTimelineScaleClampsZoomAndCalculatesNominalDensity() {
        let scale = CanvasVideoTimelineScale(
            zoomScale: 100,
            basePointsPerSecond: 20,
            minZoomScale: 1,
            maxZoomScale: 4
        )

        XCTAssertEqual(scale.zoomScale, 4)
        XCTAssertEqual(scale.pointsPerSecond, 80)
        XCTAssertEqual(scale.nominalSecondsPerPoint, 0.0125, accuracy: 0.0001)
    }

    func testTimelineViewportMapsTimeToContentXAndBack() {
        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: 20,
            playheadTimeSeconds: 6,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 2,
                basePointsPerSecond: 10,
                minZoomScale: 1,
                maxZoomScale: 4
            ),
            visibleWidth: 160,
            contentOffsetX: 40,
            minimumContentWidth: 160
        )

        let contentX = viewport.contentX(forTimeSeconds: 8)
        let roundTrippedTime = viewport.timeSeconds(forContentX: contentX)

        XCTAssertEqual(contentX, 160, accuracy: 0.05)
        XCTAssertEqual(
            roundTrippedTime,
            CanvasVideoTimelineViewport.clampedTimeSeconds(
                8,
                durationSeconds: 20
            ),
            accuracy: 0.001
        )
    }

    func testTimelineStripResultSelectsSampleNearestToPlayhead() {
        let viewport = CanvasVideoTimelineViewport(
            durationSeconds: 20,
            playheadTimeSeconds: 11.6,
            zoomScale: CanvasVideoTimelineScale(
                zoomScale: 1,
                basePointsPerSecond: 10
            ),
            visibleWidth: 120,
            contentOffsetX: 0,
            minimumContentWidth: 120
        )
        let request = CanvasVideoTimelineStripRequest(
            viewport: viewport,
            thumbnailWidth: 40,
            maxPixelSize: 180
        )
        let result = CanvasVideoTimelineStripResult(
            request: request,
            sampleTimes: [0, 5, 10, 15, 19.5]
        )

        XCTAssertEqual(result.highlightedSampleIndex, 2)
    }
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增 lint error：
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift`
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasVideoTimelineContractTests.swift`
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-timeline-phase0-macos"` 通过。
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvas_Ver_0-timeline-phase0-ios"` 通过。
- 新增测试通过：
- `CanvasVideoTimelineContractTests.testTimelineScaleClampsZoomAndCalculatesNominalDensity()`
- `CanvasVideoTimelineContractTests.testTimelineViewportMapsTimeToContentXAndBack()`
- `CanvasVideoTimelineContractTests.testTimelineViewportComputesVisibleTimeRangeFromViewportGeometry()`
- `CanvasVideoTimelineContractTests.testTimelineStripRequestDerivesRequestedRangeAndFrameCount()`
- `CanvasVideoTimelineContractTests.testTimelineStripResultSelectsSampleNearestToPlayhead()`
- 已有测试继续通过：
- `CanvasImportTypeIdentifierResolutionTests`
- `BoardVideoStorageTests`
- 构建输出里仍有几条既有的 Swift 6 actor-isolation warning，位置在 `BoardSaveCoordinator`、`BoardDocumentMapper`、`CanvasToolbarPlacementSolver` 等旧文件，本次阶段 0 未新增相关 warning。
