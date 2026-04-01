# 20260401_180500_video_timeline_phase1_record

## 记录范围

- 记录内容：实施 `@.cursor/plans/视频时间线轨道改造_4a257c8b.plan.md` 的 `phase1`，把共享取帧服务升级为“缩放感知时间线 strip”。
- 记录内容：本次只改共享层与测试层，不提前改 iOS/macOS 底部轨道 UI。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift`
- 本记录不包含：git commit / push。

## 修改一：扩展共享时间线契约，让 strip 结果可以承载真实缩略图帧

### 修改前

- `CanvasVideoTimelineViewport.with(...)` 只能覆写 `playheadTimeSeconds`、`zoomScale`、`visibleWidth`、`contentOffsetX`、`minimumContentWidth`，还不能在服务层把请求里的伪 duration 归一化成视频真实 duration。
- `CanvasVideoTimeline.swift` 只有 `CanvasVideoTimelineStripRequest` / `CanvasVideoTimelineStripResult` 这样的几何抽象，没有真正承载 `CGImage` 的 strip frame/strip 模型。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: CanvasVideoTimelineViewport.with(...) / CanvasVideoTimelineStripResult
// 功能说明: 修改前时间线契约只能表达几何和 sample 索引，无法承载共享 strip 服务真正生成出的缩略图帧集合。
import Foundation

struct CanvasVideoTimelineViewport: Equatable {
    // ... 省略前文

    func with(
        playheadTimeSeconds: Double? = nil,
        zoomScale: CanvasVideoTimelineScale? = nil,
        visibleWidth: Double? = nil,
        contentOffsetX: Double? = nil,
        minimumContentWidth: Double? = nil
    ) -> CanvasVideoTimelineViewport {
        CanvasVideoTimelineViewport(
            durationSeconds: durationSeconds,
            playheadTimeSeconds: playheadTimeSeconds ?? self.playheadTimeSeconds,
            zoomScale: zoomScale ?? self.zoomScale,
            visibleWidth: visibleWidth ?? self.visibleWidth,
            contentOffsetX: contentOffsetX ?? self.contentOffsetX,
            minimumContentWidth: minimumContentWidth ?? self.minimumContentWidth
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

### 修改后

- `CanvasVideoTimelineViewport.with(...)` 新增 `durationSeconds` 覆写参数，服务层可以把外部请求统一归一化到视频真实时长。
- 新增 `CanvasVideoTimelineStripFrame` 和 `CanvasVideoTimelineStrip`，用来表达“服务实际生成出的时间线帧结果”，包含：
- `cgImage`
- `requestedTimeSeconds`
- `actualTimeSeconds`
- `contentX`

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift
// 类型/函数: CanvasVideoTimelineViewport.with(...) / CanvasVideoTimelineStripFrame / CanvasVideoTimelineStrip
// 功能说明: 修改后共享时间线契约既能归一化真实 duration，也能承接服务层返回的缩略图帧与轨道位置。
import CoreGraphics
import Foundation

struct CanvasVideoTimelineViewport: Equatable {
    // ... 省略前文

    func with(
        durationSeconds: Double? = nil,
        playheadTimeSeconds: Double? = nil,
        zoomScale: CanvasVideoTimelineScale? = nil,
        visibleWidth: Double? = nil,
        contentOffsetX: Double? = nil,
        minimumContentWidth: Double? = nil
    ) -> CanvasVideoTimelineViewport {
        CanvasVideoTimelineViewport(
            durationSeconds: durationSeconds ?? self.durationSeconds,
            playheadTimeSeconds: playheadTimeSeconds ?? self.playheadTimeSeconds,
            zoomScale: zoomScale ?? self.zoomScale,
            visibleWidth: visibleWidth ?? self.visibleWidth,
            contentOffsetX: contentOffsetX ?? self.contentOffsetX,
            minimumContentWidth: minimumContentWidth ?? self.minimumContentWidth
        )
    }
}

struct CanvasVideoTimelineStripFrame {
    let cgImage: CGImage
    let requestedTimeSeconds: Double
    let actualTimeSeconds: Double
    let contentX: Double
}

struct CanvasVideoTimelineStrip {
    let request: CanvasVideoTimelineStripRequest
    let frames: [CanvasVideoTimelineStripFrame]

    var visibleTimeRange: ClosedRange<Double> {
        request.visibleTimeRange
    }

    var requestedTimeRange: ClosedRange<Double> {
        request.requestedTimeRange
    }

    var highlightedFrameIndex: Int? {
        guard frames.isEmpty == false else {
            return nil
        }

        let playheadContentX = request.viewport.playheadContentX
        return frames.enumerated().min { lhs, rhs in
            abs(lhs.element.contentX - playheadContentX)
                < abs(rhs.element.contentX - playheadContentX)
        }?.offset
    }
}
```

## 修改二：在共享视频帧服务里新增缩放感知 strip API 与内存缓存

### 修改前

- `CanvasVideoFrameService` 只有旧的 `previewStrip(from:frameCount:maxPixelSize:)`，仍然是固定帧数的均匀采样。
- 服务层没有会话级内存缓存；缩放或拖动时间线时，如果未来反复请求不同可见范围，只能重复全量解码。
- 也没有任何可供测试验证的 cache key / cache reset 辅助入口。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: CanvasVideoFrameService.previewStrip(from:frameCount:maxPixelSize:)
// 功能说明: 修改前共享取帧服务只能按固定 frameCount 返回旧式 preview strip，尚未感知 viewport、zoom、overscan 和缓存。
enum CanvasVideoFrameService {
    static func previewStrip(
        from localFileURL: URL,
        frameCount: Int,
        maxPixelSize: Int
    ) throws -> CanvasVideoPreviewStrip {
        let asset = AVURLAsset(url: localFileURL)
        let filename = localFileURL.lastPathComponent
        let durationSeconds = sanitizedDurationSeconds(asset.duration)
        let requestedFrameCount = max(frameCount, 1)
        let sampleTimes = previewSampleTimes(
            durationSeconds: durationSeconds,
            frameCount: requestedFrameCount
        )
        let imageGenerator = makeImageGenerator(
            for: asset,
            quality: .previewStripThumbnail(maxPixelSize: maxPixelSize)
        )
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try makeFrameImage(
                from: asset,
                filename: filename,
                at: sampleTime,
                imageGenerator: imageGenerator
            )
            return CanvasVideoPreviewStripFrame(
                cgImage: frameImage.cgImage,
                timeSeconds: frameImage.actualTimeSeconds
            )
        }
        return CanvasVideoPreviewStrip(
            durationSeconds: durationSeconds,
            frames: frames
        )
    }
}
```

### 修改后

- 新增 `CanvasVideoTimelineStripCacheKey`，把视频路径、请求时间范围、缩放密度、内容宽度、缩略图宽度、帧数、`maxPixelSize` 统一分桶到缓存 key。
- 新增 `CanvasVideoTimelineStripCache`，用 `NSLock + LRU 风格 orderedKeys` 做会话级内存缓存，并按 count/cost 双阈值驱逐。
- 新增 `timelineStrip(from:request:)`，支持：
- 根据真实视频 duration 归一化 request
- 根据 `CanvasVideoTimelineStripRequest` 生成 sample times
- 返回真正的 `CanvasVideoTimelineStrip`
- 命中缓存时直接复用
- 新增 `timelineStripCacheEntryCount()`、`resetTimelineStripCache()`、`timelineStripCacheKeyDescription(...)`，用于测试和可验证性。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: CanvasVideoTimelineStripCacheKey / CanvasVideoTimelineStripCache
// 功能说明: 修改后共享视频帧服务新增 timeline strip 缓存键与内存缓存，实现按视频路径、时间范围、缩放密度等维度复用缩略图段结果。
private struct CanvasVideoTimelineStripCacheKey {
    private static let timeBucketScale = 1_000.0
    private static let densityBucketScale = 1_000.0
    private static let layoutBucketScale = 100.0

    let sourceVideoPath: String
    let requestedTimeLowerBucket: Int
    let requestedTimeUpperBucket: Int
    let pointsPerSecondBucket: Int
    let contentWidthBucket: Int
    let thumbnailWidthBucket: Int
    let targetFrameCount: Int
    let maxPixelSize: Int

    init(
        localFileURL: URL,
        request: CanvasVideoTimelineStripRequest
    ) {
        sourceVideoPath = localFileURL
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        requestedTimeLowerBucket = Self.bucket(
            request.requestedTimeRange.lowerBound,
            scale: Self.timeBucketScale
        )
        requestedTimeUpperBucket = Self.bucket(
            request.requestedTimeRange.upperBound,
            scale: Self.timeBucketScale
        )
        pointsPerSecondBucket = Self.bucket(
            request.viewport.zoomScale.pointsPerSecond,
            scale: Self.densityBucketScale
        )
        contentWidthBucket = Self.bucket(
            request.viewport.contentWidth,
            scale: Self.layoutBucketScale
        )
        thumbnailWidthBucket = Self.bucket(
            request.thumbnailWidth,
            scale: Self.layoutBucketScale
        )
        targetFrameCount = request.targetFrameCount
        maxPixelSize = request.maxPixelSize
    }
}

private final class CanvasVideoTimelineStripCache {
    private final class Entry {
        let strip: CanvasVideoTimelineStrip
        let cost: Int

        init(strip: CanvasVideoTimelineStrip) {
            self.strip = strip
            self.cost = max(
                strip.frames.reduce(0) { partialResult, frame in
                    partialResult + max(frame.cgImage.width * frame.cgImage.height * 4, 1)
                },
                1
            )
        }
    }

    private let lock = NSLock()
    private let countLimit: Int
    private let costLimit: Int
    private var entries: [NSString: Entry] = [:]
    private var orderedKeys: [NSString] = []
    private var totalCost = 0

    func strip(
        for key: CanvasVideoTimelineStripCacheKey
    ) -> CanvasVideoTimelineStrip? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key.cacheKey] else {
            return nil
        }

        touch(key.cacheKey)
        return entry.strip
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift
// 类型/函数: CanvasVideoFrameService.timelineStrip(from:request:) / timelineStripCacheEntryCount() / resetTimelineStripCache() / timelineStripCacheKeyDescription(from:request:)
// 功能说明: 修改后共享服务可按时间线 request 生成缩略图段，并暴露测试所需的缓存观测与清理入口。
enum CanvasVideoFrameService {
    private static let timelineStripCache = CanvasVideoTimelineStripCache()

    static func timelineStrip(
        from localFileURL: URL,
        request: CanvasVideoTimelineStripRequest
    ) throws -> CanvasVideoTimelineStrip {
        let asset = AVURLAsset(url: localFileURL)
        let normalizedRequest = CanvasVideoTimelineStripRequest(
            viewport: request.viewport.with(
                durationSeconds: sanitizedDurationSeconds(asset.duration)
            ),
            thumbnailWidth: request.thumbnailWidth,
            maxPixelSize: request.maxPixelSize,
            overscanWidth: request.overscanWidth
        )
        let cacheKey = CanvasVideoTimelineStripCacheKey(
            localFileURL: localFileURL,
            request: normalizedRequest
        )
        if let cachedStrip = timelineStripCache.strip(for: cacheKey) {
            return cachedStrip
        }

        let filename = localFileURL.lastPathComponent
        let imageGenerator = makeImageGenerator(
            for: asset,
            quality: .previewStripThumbnail(
                maxPixelSize: normalizedRequest.maxPixelSize
            )
        )
        let sampleTimes = normalizedRequest.sampleTimes()
        let frames = try sampleTimes.map { sampleTime in
            let frameImage = try makeFrameImage(
                from: asset,
                filename: filename,
                at: sampleTime,
                imageGenerator: imageGenerator
            )
            return CanvasVideoTimelineStripFrame(
                cgImage: frameImage.cgImage,
                requestedTimeSeconds: sampleTime,
                actualTimeSeconds: frameImage.actualTimeSeconds,
                contentX: normalizedRequest.viewport.contentX(
                    forTimeSeconds: frameImage.actualTimeSeconds
                )
            )
        }
        let strip = CanvasVideoTimelineStrip(
            request: normalizedRequest,
            frames: frames
        )
        timelineStripCache.insert(strip, for: cacheKey)
        return strip
    }

    static func timelineStripCacheEntryCount() -> Int {
        timelineStripCache.entryCount
    }

    static func resetTimelineStripCache() {
        timelineStripCache.removeAll()
    }
}
```

## 修改三：在 EditorSession 暴露时间线 strip 入口，UI 后续只接 Session 不碰视频 URL

### 修改前

- `CanvasEditorSession` 只有 `videoPreviewStrip(...)`，返回的还是旧式 `CanvasVideoPreviewStrip`。
- 后续 iOS/macOS 轨道 UI 如果要接新的共享 strip 服务，只能越过 Session 直接去调 `CanvasVideoFrameService`，边界不干净。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: CanvasEditorSession.videoPreviewStrip(for:frameCount:maxPixelSize:)
// 功能说明: 修改前编辑会话层只暴露旧 preview strip 入口，尚未为新时间线 strip 服务提供统一接线点。
func videoPreviewStrip(
    for itemID: CanvasItemID,
    frameCount: Int = 9,
    maxPixelSize: Int = 160
) throws -> CanvasVideoPreviewStrip {
    let editorContext = try videoEditorContext(for: itemID)
    return try CanvasVideoFrameService.previewStrip(
        from: editorContext.sourceVideoURL,
        frameCount: frameCount,
        maxPixelSize: maxPixelSize
    )
}
```

### 修改后

- 新增 `videoTimelineStrip(for:request:)`。
- 这个入口在 Session 层先做一次 request 归一化，把 viewport 的 `durationSeconds` 修正为当前视频真实时长，再转给 `CanvasVideoFrameService.timelineStrip(...)`。
- poster 提交路径保持不变，本次没有碰 `commitVideoPosterFrame(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: CanvasEditorSession.videoTimelineStrip(for:request:)
// 功能说明: 修改后编辑会话层对外暴露新的时间线 strip 入口，后续双端轨道 UI 可以继续只依赖 Session，不直接依赖视频 URL 与底层服务。
func videoTimelineStrip(
    for itemID: CanvasItemID,
    request: CanvasVideoTimelineStripRequest
) throws -> CanvasVideoTimelineStrip {
    let editorContext = try videoEditorContext(for: itemID)
    let normalizedRequest = CanvasVideoTimelineStripRequest(
        viewport: request.viewport.with(
            durationSeconds: editorContext.durationSeconds
        ),
        thumbnailWidth: request.thumbnailWidth,
        maxPixelSize: request.maxPixelSize,
        overscanWidth: request.overscanWidth
    )
    return try CanvasVideoFrameService.timelineStrip(
        from: editorContext.sourceVideoURL,
        request: normalizedRequest
    )
}
```

## 修改四：新增时间线 strip 服务测试，验证缓存、分桶和 duration 归一化

### 修改前

- 工程里还没有专门验证共享 strip 服务的测试文件。
- 这意味着即便服务层已经支持 request/cache，后续阶段继续接 UI 时也没有自动化约束它的缓存命中、时间范围扩张和 duration 归一化行为。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前工程内没有专门验证时间线 strip 服务缓存与请求归一化行为的测试文件。
// 文件不存在。
```

### 修改后

- 新增 `CanvasVideoTimelineStripServiceTests.swift`。
- 核心覆盖：
- 重复请求命中缓存
- zoom / time range 改变导致 cache key 改变
- strip request 会按真实视频时长归一化，并在 overscan 下扩大 requested range
- 测试里用 `AVAssetWriter` 现场生成 `.mov` 文件，避免依赖外部固定测试资源。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift
// 类型/函数: CanvasVideoTimelineStripServiceTests.testTimelineStripCachesRepeatedRequestForSameVideo() / testTimelineStripCacheKeyChangesWhenZoomOrTimeRangeChanges() / testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan()
// 功能说明: 修改后新增共享 strip 服务测试，直接锁定缓存命中、key 分桶和真实视频时长归一化的行为边界。
import AVFoundation
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasVideoTimelineStripServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CanvasVideoFrameService.resetTimelineStripCache()
    }

    override func tearDown() {
        CanvasVideoFrameService.resetTimelineStripCache()
        super.tearDown()
    }

    func testTimelineStripCachesRepeatedRequestForSameVideo() throws {
        let videoURL = try makeTestVideoURL()
        defer { try? FileManager.default.removeItem(at: videoURL) }
        try writeTestVideo(to: videoURL)

        let request = makeTimelineStripRequest(
            durationSeconds: resolvedDurationSeconds(for: videoURL),
            playheadTimeSeconds: 0.8,
            zoomScale: 1,
            visibleWidth: 30,
            contentOffsetX: 2,
            overscanWidth: 8
        )

        let firstStrip = try CanvasVideoFrameService.timelineStrip(
            from: videoURL,
            request: request
        )
        XCTAssertEqual(CanvasVideoFrameService.timelineStripCacheEntryCount(), 1)

        let secondStrip = try CanvasVideoFrameService.timelineStrip(
            from: videoURL,
            request: request
        )

        XCTAssertEqual(CanvasVideoFrameService.timelineStripCacheEntryCount(), 1)
        XCTAssertEqual(
            firstStrip.frames.map(\.actualTimeSeconds),
            secondStrip.frames.map(\.actualTimeSeconds)
        )
    }

    func testTimelineStripCacheKeyChangesWhenZoomOrTimeRangeChanges() {
        let videoURL = URL(fileURLWithPath: "/tmp/timeline-cache-key.mov")
        let baseRequest = makeTimelineStripRequest(
            durationSeconds: 10,
            playheadTimeSeconds: 2,
            zoomScale: 1,
            visibleWidth: 30,
            contentOffsetX: 0,
            overscanWidth: 8
        )
        let zoomedRequest = makeTimelineStripRequest(
            durationSeconds: 10,
            playheadTimeSeconds: 2,
            zoomScale: 2,
            visibleWidth: 30,
            contentOffsetX: 0,
            overscanWidth: 8
        )

        let baseKey = CanvasVideoFrameService.timelineStripCacheKeyDescription(
            from: videoURL,
            request: baseRequest
        )
        let zoomedKey = CanvasVideoFrameService.timelineStripCacheKeyDescription(
            from: videoURL,
            request: zoomedRequest
        )

        XCTAssertNotEqual(baseKey, zoomedKey)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift
// 类型/函数: writeTestVideo(to:frameCount:frameRate:width:height:) / makeSolidColorPixelBuffer(width:height:red:green:blue:)
// 功能说明: 修改后测试文件通过 AVAssetWriter 现生成小视频，确保 strip 服务测试不依赖仓库中的外部视频样本。
private func writeTestVideo(
    to videoURL: URL,
    frameCount: Int = 24,
    frameRate: Int32 = 12,
    width: Int = 24,
    height: Int = 24
) throws {
    let writer = try AVAssetWriter(url: videoURL, fileType: .mov)
    let outputSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height
    ]
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: outputSettings
    )
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
    )
    // ... 省略 writer session 启动与逐帧 append 代码
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增 lint error：
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoTimeline.swift`
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoFrameService.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0Tests/CanvasVideoTimelineStripServiceTests.swift`
- `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-timeline-phase1-macos"` 通过。
- `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvas_Ver_0-timeline-phase1-ios"` 通过。
- 新增测试通过：
- `CanvasVideoTimelineStripServiceTests.testTimelineStripCachesRepeatedRequestForSameVideo()`
- `CanvasVideoTimelineStripServiceTests.testTimelineStripCacheKeyChangesWhenZoomOrTimeRangeChanges()`
- `CanvasVideoTimelineStripServiceTests.testTimelineStripNormalizesDurationAndExpandsRequestedRangeWithOverscan()`
- 阶段 0 既有测试继续通过：
- `CanvasVideoTimelineContractTests`
- `BoardVideoStorageTests`
- `CanvasImportTypeIdentifierResolutionTests`
- 构建输出中仍有几条既有的 Swift 6 actor-isolation warning，位置在 `BoardSaveCoordinator`、`BoardDocumentMapper`、`CanvasToolbarPlacementSolver` 等旧文件，本次 `phase1` 未新增相关 warning。
