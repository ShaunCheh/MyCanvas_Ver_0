# 20260401_191007_video_timeline_phase4_record

## 记录范围

- 记录内容：实施 `@.cursor/plans/视频时间线轨道改造_4a257c8b.plan.md` 的 `phase4`，把 iOS/macOS 视频选帧页的时间同步逻辑收口为共享 preview state。
- 记录内容：统一顶部时间 label、顶部 slider、`AVPlayer` 当前时间、底部时间线 playhead、当前 poster 预选状态的派生来源。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Video/CanvasVideoEditorPreviewState.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift`
- 本记录不包含：`git commit` / `git push`

## 修改一：新增共享的 preview state 状态模型

### 修改前

- 项目里还没有独立的共享 preview state 文件。
- 当前预览时间、交互源集合、交互结束后的播放恢复意图，分别散落在 iOS/macOS 控制器内部。
- “当前帧是否已经是 poster” 也没有抽成统一判断，只能在控制器里各自维护按钮可用性语义。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoEditorPreviewState.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前项目中还没有共享的 preview state；时间同步、交互暂停恢复和 poster 预选判断都散落在平台控制器里。
```

### 修改后

- 新增 `CanvasVideoEditorPreviewState`、`CanvasVideoEditorPreviewSnapshot`、`CanvasVideoEditorPlaybackIntent`、`CanvasVideoEditorPreviewInteractionSource`。
- 统一封装时间 clamp、poster 预选容差、交互中是否允许接受 player 回调、交互开始/结束时的暂停与恢复语义。
- 控制器改为只读 `snapshot` 刷 UI，只在收到 slider / timeline / player 事件时写入这份共享状态。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Video/CanvasVideoEditorPreviewState.swift
// 类型/函数: CanvasVideoEditorPreviewSnapshot / CanvasVideoEditorPreviewState / beginInteraction(_:wasPlaying:) / endInteraction(_:)
// 功能说明: 修改后新增共享状态模型，把当前时间、poster 时间、交互源集合和播放恢复意图统一收口，供双端控制器派生 UI。
import Foundation

enum CanvasVideoEditorPreviewInteractionSource: Hashable {
    case slider
    case timeline
}

enum CanvasVideoEditorPlaybackIntent: Equatable {
    case none
    case pause
    case resume
}

struct CanvasVideoEditorPreviewSnapshot: Equatable {
    static let posterSelectionToleranceSeconds = max(
        1.0 / 30.0,
        CanvasVideoTimelineMath.frameBoundaryEpsilonSeconds * 2
    )

    let currentTimeSeconds: Double
    let posterTimeSeconds: Double
    let durationSeconds: Double
    let activeInteractionSources: Set<CanvasVideoEditorPreviewInteractionSource>

    var shouldAcceptPlayerTimeUpdates: Bool {
        activeInteractionSources.isEmpty
    }

    var isCurrentPosterSelected: Bool {
        abs(currentTimeSeconds - posterTimeSeconds)
            <= Self.posterSelectionToleranceSeconds
    }

    func isInteracting(
        with source: CanvasVideoEditorPreviewInteractionSource
    ) -> Bool {
        activeInteractionSources.contains(source)
    }
}

struct CanvasVideoEditorPreviewState {
    private(set) var currentTimeSeconds: Double
    private(set) var posterTimeSeconds: Double
    private(set) var durationSeconds: Double
    private(set) var activeInteractionSources: Set<
        CanvasVideoEditorPreviewInteractionSource
    > = []
    private(set) var shouldResumePlaybackAfterInteraction = false

    var snapshot: CanvasVideoEditorPreviewSnapshot {
        CanvasVideoEditorPreviewSnapshot(
            currentTimeSeconds: currentTimeSeconds,
            posterTimeSeconds: posterTimeSeconds,
            durationSeconds: durationSeconds,
            activeInteractionSources: activeInteractionSources
        )
    }

    mutating func setCurrentTimeSeconds(_ timeSeconds: Double) {
        currentTimeSeconds = CanvasVideoTimelineMath.clampedTimeSeconds(
            timeSeconds,
            durationSeconds: durationSeconds
        )
    }

    mutating func beginInteraction(
        _ source: CanvasVideoEditorPreviewInteractionSource,
        wasPlaying: Bool
    ) -> CanvasVideoEditorPlaybackIntent {
        let insertionResult = activeInteractionSources.insert(source)
        guard insertionResult.inserted else {
            return .none
        }
        guard activeInteractionSources.count == 1 else {
            return .none
        }

        shouldResumePlaybackAfterInteraction = wasPlaying
        return .pause
    }

    mutating func endInteraction(
        _ source: CanvasVideoEditorPreviewInteractionSource
    ) -> CanvasVideoEditorPlaybackIntent {
        guard activeInteractionSources.remove(source) != nil else {
            return .none
        }
        guard activeInteractionSources.isEmpty else {
            return .none
        }

        defer {
            shouldResumePlaybackAfterInteraction = false
        }
        return shouldResumePlaybackAfterInteraction ? .resume : .none
    }
}
```

## 修改二：iOS 编辑器改为从共享状态派生 UI

### 修改前

- `iOSVideoDisplayFrameEditorViewController` 自己持有 `currentPreviewTimeSeconds`、`activeInteractionSources`、`shouldResumePlaybackAfterInteraction`。
- `applyInitialState()`、`handlePlayerTimeUpdate(_:)`、`currentTimeSecondsDidChange(...)`、`beginPreviewInteraction(_:)`、`endPreviewInteraction(_:)` 各自处理一部分同步职责。
- 提交按钮只根据 `isCommitting` 决定可用性，无法统一表达“当前帧已经是现有 poster”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / applyInitialState() / handlePlayerTimeUpdate(_:) / currentTimeSecondsDidChange(_:updateSlider:updateTimeline:) / beginPreviewInteraction(_:) / endPreviewInteraction(_:) / updateCommitButtonConfiguration()
// 功能说明: 修改前 iOS 控制器自己维护当前时间、交互态和播放恢复语义，UI 刷新逻辑分散在多个方法里。
private var currentPreviewTimeSeconds: Double
private var activeInteractionSources: Set<PreviewInteractionSource> = []
private var shouldResumePlaybackAfterInteraction = false

private func applyInitialState() {
    timelineView.configure(
        durationSeconds: editorContext.durationSeconds,
        playheadTimeSeconds: currentPreviewTimeSeconds
    )
    currentTimeSecondsDidChange(
        currentPreviewTimeSeconds,
        updateSlider: true,
        updateTimeline: false
    )
}

private func handlePlayerTimeUpdate(_ time: CMTime) {
    guard isPreviewInteracting == false else {
        return
    }
    // ... 省略其它现有逻辑
}

private func currentTimeSecondsDidChange(
    _ timeSeconds: Double,
    updateSlider: Bool,
    updateTimeline: Bool
) {
    currentPreviewTimeSeconds = clampedTimeSeconds(timeSeconds)
    currentTimeLabel.text = formatVideoDisplayFrameEditorSeconds(
        currentPreviewTimeSeconds
    )
    durationLabel.text = formatVideoDisplayFrameEditorSeconds(
        editorContext.durationSeconds
    )
    if updateSlider, activeInteractionSources.contains(.slider) == false {
        timeSlider.value = Float(currentPreviewTimeSeconds)
    }
    if updateTimeline {
        timelineView.setPlayheadTimeSeconds(
            currentPreviewTimeSeconds,
            animated: false
        )
    }
}

private func updateCommitButtonConfiguration() {
    var configuration = UIButton.Configuration.filled()
    configuration.title = isCommitting
        ? "Setting Display Frame..."
        : "Use Current Frame"
    setDisplayFrameButton.configuration = configuration
    setDisplayFrameButton.isEnabled = isCommitting == false
}

private func beginPreviewInteraction(_ source: PreviewInteractionSource) {
    let wasEmpty = activeInteractionSources.isEmpty
    activeInteractionSources.insert(source)
    guard wasEmpty else {
        return
    }

    shouldResumePlaybackAfterInteraction = player.timeControlStatus == .playing
    pausePlayback()
}

private func endPreviewInteraction(_ source: PreviewInteractionSource) {
    activeInteractionSources.remove(source)
    guard activeInteractionSources.isEmpty else {
        return
    }

    if shouldResumePlaybackAfterInteraction {
        player.play()
        updatePlayPauseButtonConfiguration()
    }
    shouldResumePlaybackAfterInteraction = false
}
```

### 修改后

- 控制器改为只持有 `previewState`，初始化时把 `currentPosterTimeSeconds` 和 `durationSeconds` 注入共享状态。
- `currentTimeSecondsDidChange(...)` 只负责写入状态，统一由 `applyPreviewState(...)` 刷时间 label、slider、timeline、提交按钮。
- `handlePlayerTimeUpdate(_:)` 改为读取 `previewState.snapshot.shouldAcceptPlayerTimeUpdates`，避免交互中回跳。
- 提交按钮接入 `snapshot.isCurrentPosterSelected`，当前帧已经是 poster 时显示 `Current Frame Already Used` 并禁用。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / applyInitialState() / handlePlayerTimeUpdate(_:) / currentTimeSecondsDidChange(_:updateSlider:updateTimeline:) / applyPreviewState(updateSlider:updateTimeline:) / beginPreviewInteraction(_:) / endPreviewInteraction(_:) / updateCommitButtonConfiguration()
// 功能说明: 修改后 iOS 控制器把时间状态和交互恢复语义交给共享 preview state，自身只负责派发意图和从 snapshot 派生 UI。
private var previewState: CanvasVideoEditorPreviewState

private func applyInitialState() {
    let snapshot = previewState.snapshot
    timelineView.configure(
        durationSeconds: snapshot.durationSeconds,
        playheadTimeSeconds: snapshot.currentTimeSeconds
    )
    currentTimeSecondsDidChange(
        snapshot.currentTimeSeconds,
        updateSlider: true,
        updateTimeline: false
    )
}

private func handlePlayerTimeUpdate(_ time: CMTime) {
    guard previewState.snapshot.shouldAcceptPlayerTimeUpdates else {
        return
    }
    // ... 省略其它现有逻辑
}

private func currentTimeSecondsDidChange(
    _ timeSeconds: Double,
    updateSlider: Bool,
    updateTimeline: Bool
) {
    previewState.setCurrentTimeSeconds(timeSeconds)
    applyPreviewState(
        updateSlider: updateSlider,
        updateTimeline: updateTimeline
    )
}

private func applyPreviewState(
    updateSlider: Bool,
    updateTimeline: Bool
) {
    let snapshot = previewState.snapshot
    currentTimeLabel.text = formatVideoDisplayFrameEditorSeconds(
        snapshot.currentTimeSeconds
    )
    durationLabel.text = formatVideoDisplayFrameEditorSeconds(
        snapshot.durationSeconds
    )
    if updateSlider, snapshot.isInteracting(with: .slider) == false {
        timeSlider.value = Float(snapshot.currentTimeSeconds)
    }
    if updateTimeline {
        timelineView.setPlayheadTimeSeconds(
            snapshot.currentTimeSeconds,
            animated: false
        )
    }
    updateCommitButtonConfiguration()
}

private func updateCommitButtonConfiguration() {
    let snapshot = previewState.snapshot
    var configuration = UIButton.Configuration.filled()
    configuration.title = isCommitting
        ? "Setting Display Frame..."
        : (snapshot.isCurrentPosterSelected
            ? "Current Frame Already Used"
            : "Use Current Frame")
    setDisplayFrameButton.configuration = configuration
    setDisplayFrameButton.isEnabled = (
        isCommitting == false &&
            snapshot.isCurrentPosterSelected == false
    )
}

private func beginPreviewInteraction(
    _ source: CanvasVideoEditorPreviewInteractionSource
) {
    let playbackIntent = previewState.beginInteraction(
        source,
        wasPlaying: player.timeControlStatus == .playing
    )
    if playbackIntent == .pause {
        pausePlayback()
    }
    updateCommitButtonConfiguration()
}

private func endPreviewInteraction(
    _ source: CanvasVideoEditorPreviewInteractionSource
) {
    let playbackIntent = previewState.endInteraction(source)
    if playbackIntent == .resume {
        player.play()
        updatePlayPauseButtonConfiguration()
    }
    updateCommitButtonConfiguration()
}
```

## 修改三：macOS 编辑器对齐到同一套共享状态语义

### 修改前

- `macOSVideoDisplayFrameEditorViewController` 和 iOS 一样，也在控制器里单独维护当前时间、交互源和播放恢复状态。
- `currentTimeSecondsDidChange(...)` 同时承担写状态和刷 UI 的职责。
- 提交按钮同样只根据 `isCommitting` 启用/禁用，无法表达“当前帧已经是 poster”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / applyInitialState() / handlePlayerTimeUpdate(_:) / currentTimeSecondsDidChange(_:updateSlider:updateTimeline:) / beginPreviewInteraction(_:) / endPreviewInteraction(_:) / updateCommitButtonAppearance()
// 功能说明: 修改前 macOS 控制器和 iOS 类似，状态同步逻辑直接写在控制器里，双端语义靠复制维护。
private var currentPreviewTimeSeconds: Double
private var activeInteractionSources: Set<PreviewInteractionSource> = []
private var shouldResumePlaybackAfterInteraction = false

private func applyInitialState() {
    timelineView.configure(
        durationSeconds: editorContext.durationSeconds,
        playheadTimeSeconds: currentPreviewTimeSeconds
    )
    currentTimeSecondsDidChange(
        currentPreviewTimeSeconds,
        updateSlider: true,
        updateTimeline: false
    )
}

private func handlePlayerTimeUpdate(_ time: CMTime) {
    guard isPreviewInteracting == false else {
        return
    }
    // ... 省略其它现有逻辑
}

private func currentTimeSecondsDidChange(
    _ timeSeconds: Double,
    updateSlider: Bool,
    updateTimeline: Bool
) {
    currentPreviewTimeSeconds = clampedTimeSeconds(timeSeconds)
    currentTimeLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
        currentPreviewTimeSeconds
    )
    durationLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
        editorContext.durationSeconds
    )
    if updateSlider, activeInteractionSources.contains(.slider) == false {
        timeSlider.doubleValue = currentPreviewTimeSeconds
    }
    if updateTimeline {
        timelineView.setPlayheadTimeSeconds(
            currentPreviewTimeSeconds,
            animated: false
        )
    }
}

private func updateCommitButtonAppearance() {
    setDisplayFrameButton.title = isCommitting
        ? "Setting Display Frame..."
        : "Use Current Frame"
    setDisplayFrameButton.isEnabled = isCommitting == false
}

private func beginPreviewInteraction(_ source: PreviewInteractionSource) {
    let wasEmpty = activeInteractionSources.isEmpty
    activeInteractionSources.insert(source)
    guard wasEmpty else {
        return
    }

    shouldResumePlaybackAfterInteraction = player.timeControlStatus == .playing
    pausePlayback()
}

private func endPreviewInteraction(_ source: PreviewInteractionSource) {
    activeInteractionSources.remove(source)
    guard activeInteractionSources.isEmpty else {
        return
    }

    if shouldResumePlaybackAfterInteraction {
        player.play()
        updatePlayPauseButtonAppearance()
    }
    shouldResumePlaybackAfterInteraction = false
}
```

### 修改后

- macOS 控制器同样改为只持有 `previewState`，和 iOS 共用同一套状态机语义。
- `currentTimeSecondsDidChange(...)`、`applyPreviewState(...)`、`beginPreviewInteraction(_:)`、`endPreviewInteraction(_:)` 的职责和 iOS 对齐，双端不再分叉。
- 提交按钮也接入 `snapshot.isCurrentPosterSelected`，避免重复提交当前 poster。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift
// 类型/函数: 属性区块 / applyInitialState() / handlePlayerTimeUpdate(_:) / currentTimeSecondsDidChange(_:updateSlider:updateTimeline:) / applyPreviewState(updateSlider:updateTimeline:) / beginPreviewInteraction(_:) / endPreviewInteraction(_:) / updateCommitButtonAppearance()
// 功能说明: 修改后 macOS 控制器改为共享 preview state 驱动，把 slider、timeline、player、poster 预选状态统一收口到同一份时间状态。
private var previewState: CanvasVideoEditorPreviewState

private func applyInitialState() {
    let snapshot = previewState.snapshot
    timelineView.configure(
        durationSeconds: snapshot.durationSeconds,
        playheadTimeSeconds: snapshot.currentTimeSeconds
    )
    currentTimeSecondsDidChange(
        snapshot.currentTimeSeconds,
        updateSlider: true,
        updateTimeline: false
    )
}

private func handlePlayerTimeUpdate(_ time: CMTime) {
    guard previewState.snapshot.shouldAcceptPlayerTimeUpdates else {
        return
    }
    // ... 省略其它现有逻辑
}

private func currentTimeSecondsDidChange(
    _ timeSeconds: Double,
    updateSlider: Bool,
    updateTimeline: Bool
) {
    previewState.setCurrentTimeSeconds(timeSeconds)
    applyPreviewState(
        updateSlider: updateSlider,
        updateTimeline: updateTimeline
    )
}

private func applyPreviewState(
    updateSlider: Bool,
    updateTimeline: Bool
) {
    let snapshot = previewState.snapshot
    currentTimeLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
        snapshot.currentTimeSeconds
    )
    durationLabel.stringValue = formatVideoDisplayFrameEditorSeconds(
        snapshot.durationSeconds
    )
    if updateSlider, snapshot.isInteracting(with: .slider) == false {
        timeSlider.doubleValue = snapshot.currentTimeSeconds
    }
    if updateTimeline {
        timelineView.setPlayheadTimeSeconds(
            snapshot.currentTimeSeconds,
            animated: false
        )
    }
    updateCommitButtonAppearance()
}

private func updateCommitButtonAppearance() {
    let snapshot = previewState.snapshot
    setDisplayFrameButton.title = isCommitting
        ? "Setting Display Frame..."
        : (snapshot.isCurrentPosterSelected
            ? "Current Frame Already Used"
            : "Use Current Frame")
    setDisplayFrameButton.isEnabled = (
        isCommitting == false &&
            snapshot.isCurrentPosterSelected == false
    )
}

private func beginPreviewInteraction(
    _ source: CanvasVideoEditorPreviewInteractionSource
) {
    let playbackIntent = previewState.beginInteraction(
        source,
        wasPlaying: player.timeControlStatus == .playing
    )
    if playbackIntent == .pause {
        pausePlayback()
    }
    updateCommitButtonAppearance()
}

private func endPreviewInteraction(
    _ source: CanvasVideoEditorPreviewInteractionSource
) {
    let playbackIntent = previewState.endInteraction(source)
    if playbackIntent == .resume {
        player.play()
        updatePlayPauseButtonAppearance()
    }
    updateCommitButtonAppearance()
}
```

## 修改四：补齐共享状态的纯逻辑测试

### 修改前

- 项目里还没有专门覆盖 preview state 的测试文件。
- 交互开始/结束时的暂停恢复语义、poster 预选容差、多交互源叠加行为，都没有独立的纯逻辑断言。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift
// 类型/函数: 文件不存在
// 功能说明: 修改前没有 dedicated 的 preview state 测试，状态收口后的边界语义没有被单独固定。
```

### 修改后

- 新增 `CanvasVideoEditorPreviewStateTests`。
- 覆盖时间 clamp 与 poster 预选状态判断。
- 覆盖单交互源进入/退出时的暂停与恢复。
- 覆盖“交互开始前本来就是暂停”以及“多个交互源叠加时最后一个结束才恢复”的边界。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift
// 类型/函数: CanvasVideoEditorPreviewStateTests / testPreviewStateClampsTimeAndTracksPosterSelection() / testPreviewStateBeginsAndEndsSingleInteractionWithPlaybackResume() / testPreviewStateDoesNotResumePlaybackIfInteractionStartedWhilePaused() / testPreviewStateKeepsPlaybackSuspendedUntilAllInteractionSourcesEnd()
// 功能说明: 修改后新增纯逻辑测试，把共享 preview state 的核心边界条件固定下来，避免后续双端时间同步再次漂移。
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasVideoEditorPreviewStateTests: XCTestCase {
    func testPreviewStateClampsTimeAndTracksPosterSelection() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 99,
            posterTimeSeconds: 5,
            durationSeconds: 20
        )

        XCTAssertEqual(
            state.snapshot.currentTimeSeconds,
            CanvasVideoTimelineViewport.clampedTimeSeconds(
                99,
                durationSeconds: 20
            ),
            accuracy: 0.0001
        )
        XCTAssertFalse(state.snapshot.isCurrentPosterSelected)

        state.setCurrentTimeSeconds(5.02)
        XCTAssertTrue(state.snapshot.isCurrentPosterSelected)

        state.setCurrentTimeSeconds(5.2)
        XCTAssertFalse(state.snapshot.isCurrentPosterSelected)
    }

    func testPreviewStateBeginsAndEndsSingleInteractionWithPlaybackResume() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 2,
            posterTimeSeconds: 1,
            durationSeconds: 10
        )

        XCTAssertEqual(
            state.beginInteraction(.slider, wasPlaying: true),
            .pause
        )
        XCTAssertFalse(state.snapshot.shouldAcceptPlayerTimeUpdates)

        XCTAssertEqual(
            state.endInteraction(.slider),
            .resume
        )
        XCTAssertTrue(state.snapshot.shouldAcceptPlayerTimeUpdates)
    }

    func testPreviewStateKeepsPlaybackSuspendedUntilAllInteractionSourcesEnd() {
        var state = CanvasVideoEditorPreviewState(
            currentTimeSeconds: 3,
            posterTimeSeconds: 1,
            durationSeconds: 10
        )

        XCTAssertEqual(
            state.beginInteraction(.slider, wasPlaying: true),
            .pause
        )
        XCTAssertEqual(
            state.beginInteraction(.timeline, wasPlaying: true),
            .none
        )
        XCTAssertFalse(state.snapshot.shouldAcceptPlayerTimeUpdates)

        XCTAssertEqual(
            state.endInteraction(.slider),
            .none
        )
        XCTAssertFalse(state.snapshot.shouldAcceptPlayerTimeUpdates)

        XCTAssertEqual(
            state.endInteraction(.timeline),
            .resume
        )
        XCTAssertTrue(state.snapshot.shouldAcceptPlayerTimeUpdates)
    }
}
```

## 验证结果

- `ReadLints` 检查以下文件，无新增诊断：
- `MyCanvas_Ver_0/Canvas/Video/CanvasVideoEditorPreviewState.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSVideoDisplayFrameEditorViewController.swift`
- `MyCanvas_Ver_0Tests/CanvasVideoEditorPreviewStateTests.swift`
- macOS 测试通过：
- `xcodebuild test -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase4-macos"`
- iOS 构建通过：
- `xcodebuild build -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS Simulator" -derivedDataPath "/tmp/MyCanvas_Ver_0-phase4-ios"`
