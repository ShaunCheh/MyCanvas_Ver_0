# 20260408_171058_alignment_guides_phase2_session_renderer_record

## 记录范围

- 记录内容：
  1. 把 `alignment` transient state 接入 `CanvasEditorSession`，补齐 reading mode 下的 presentation gate。
  2. 把 `alignment` overlay 接入 `CanvasRenderer`，让 `world guide -> screen guideSegments -> CanvasRenderSnapshot.interactionOverlay` 这条共享链路真正打通。
  3. 新增 `CanvasEditorSessionAlignmentOverlayTests.swift`，验证 snapshot 层会正确生成/屏蔽 `.alignment` overlay，并保证 `rotation` 优先级不被破坏。
- 涉及文件：
  - `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
  - `MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
  - `MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
- 当前 changes 依据：
  - `git status --short` 当前显示：
    - `M MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift`
    - `M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
    - `?? MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift`
  - `git diff --stat` 当前显示：
    - `CanvasRenderer.swift` 与 `CanvasEditorSession.swift` 共 `67 insertions(+), 5 deletions(-)`
  - `git diff` 当前能直接看到的是 `CanvasRenderer.swift` 与 `CanvasEditorSession.swift` 的已跟踪修改。
  - `CanvasEditorSessionAlignmentOverlayTests.swift` 当前是新增未跟踪文件，因此普通 `git diff` 不会展示它；本记录对该文件的说明直接依据当前工作区文件内容。
- 验证依据：
  - `ReadLints`：本次修改文件无新增诊断问题。
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS"`
- 本记录不包含：
  - `Phase 3` 的 iOS 拖拽链路接入
  - `Phase 4` 的 macOS 拖拽链路接入
  - `Phase 5` 的 viewport 真正绘制辅助线
  - git commit / push

## 修改一：`CanvasEditorSession` 增加 alignment transient state 与 presentation gate

### 修改前

- `CanvasEditorSession` 只持有 `rotationPreviewState` 和 `rotationInteractionState`，没有 `alignmentInteractionState`。
- `makeCanvasSnapshot()` 也只会把 rotation 相关 transient state 传给 renderer。
- 这意味着即便 `Phase 1` 的 solver 已经能产出 `CanvasAlignmentInteractionState`，当前 session 层仍然没有地方持有和透传它。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession / presentationRotationInteractionState / makeCanvasSnapshot()
// 功能说明: 修改前 session 只有 rotation transient state；snapshot 生成时不会把 alignment state 传给 renderer，因此后续 renderSnapshot.interactionOverlay 不可能得到 `.alignment`。
final class CanvasEditorSession {
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?

    var presentationRotationInteractionState: CanvasRotationInteractionState? {
        isReadingModeActive ? nil : rotationInteractionState
    }

    func makeCanvasSnapshot() -> CanvasRenderSnapshot {
        let snapshot = renderer.makeSnapshot(
            scene: scene,
            boardState: boardState,
            camera: camera,
            interactionState: presentationInteractionState,
            inlineEditState: presentationInlineEditState,
            rotationPreviewState: presentationRotationPreviewState,
            rotationInteractionState: presentationRotationInteractionState
        )
        lastRenderSnapshot = snapshot
        return snapshot
    }
}
```

### 修改后

- `CanvasEditorSession` 新增了 `alignmentInteractionState`。
- 新增 `presentationAlignmentInteractionState`，保持与 `presentationRotationInteractionState` 同样的 gating 语义：阅读模式下自动屏蔽。
- `makeCanvasSnapshot()` 现在会把 `presentationAlignmentInteractionState` 继续传给 `CanvasRenderer.makeSnapshot(...)`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: CanvasEditorSession / presentationAlignmentInteractionState / makeCanvasSnapshot()
// 功能说明: 修改后 session 可以持有 alignment 拖拽瞬时状态，并在非 reading mode 下把它透传给 renderer，打通 session -> renderer -> snapshot 的共享渲染链路。
final class CanvasEditorSession {
    var inlineEditState: CanvasInlineEditState?
    var rotationPreviewState: CanvasRotationPreviewState?
    var rotationInteractionState: CanvasRotationInteractionState?
    var alignmentInteractionState: CanvasAlignmentInteractionState?

    var presentationRotationInteractionState: CanvasRotationInteractionState? {
        isReadingModeActive ? nil : rotationInteractionState
    }

    var presentationAlignmentInteractionState: CanvasAlignmentInteractionState? {
        isReadingModeActive ? nil : alignmentInteractionState
    }

    func makeCanvasSnapshot() -> CanvasRenderSnapshot {
        let snapshot = renderer.makeSnapshot(
            scene: scene,
            boardState: boardState,
            camera: camera,
            interactionState: presentationInteractionState,
            inlineEditState: presentationInlineEditState,
            rotationPreviewState: presentationRotationPreviewState,
            rotationInteractionState: presentationRotationInteractionState,
            alignmentInteractionState: presentationAlignmentInteractionState
        )
        lastRenderSnapshot = snapshot
        return snapshot
    }
}
```

## 修改二：runtime / history restore 时同步清空 alignment transient state

### 修改前

- `applyBoardRuntimeState(...)` 和 `applyBoardHistorySnapshot(...)` 只会清空 `inlineEditState`、`rotationPreviewState`、`rotationInteractionState`。
- 如果后续平台层开始写入 `alignmentInteractionState`，这些 restore 路径就会留下潜在的 transient state 残留点。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: applyBoardRuntimeState(_:) / applyBoardHistorySnapshot(_:)
// 功能说明: 修改前 runtime restore 与 history restore 不知道 alignment transient state 的存在，因此不会主动清理它。
func applyBoardRuntimeState(
    _ runtimeState: BoardRuntimeState,
    preserveTransientImageAssetPayloads: Bool = false
) {
    // ...
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
    // ...
}

func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    // ...
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
    // ...
}
```

### 修改后

- 两条 restore 路径都增加了 `alignmentInteractionState = nil`。
- 这保证了 alignment overlay 依然是纯 transient 数据，不会借 runtime restore / undo / redo 的路径残留到下一帧。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名: applyBoardRuntimeState(_:) / applyBoardHistorySnapshot(_:)
// 功能说明: 修改后所有 runtime/history restore 都会统一清空 alignment transient state，确保辅助线不会穿过 restore、undo、redo 生命周期残留。
func applyBoardRuntimeState(
    _ runtimeState: BoardRuntimeState,
    preserveTransientImageAssetPayloads: Bool = false
) {
    // ...
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
    alignmentInteractionState = nil
    // ...
}

func applyBoardHistorySnapshot(_ snapshot: BoardHistorySnapshot) {
    // ...
    inlineEditState = nil
    rotationPreviewState = nil
    rotationInteractionState = nil
    alignmentInteractionState = nil
    // ...
}
```

## 修改三：`CanvasRenderer.makeSnapshot(...)` 接入 alignment 参数

### 修改前

- `CanvasRenderer.makeSnapshot(...)` 只接收 `rotationInteractionState`，没有 `alignmentInteractionState` 参数。
- `makeInteractionOverlay(...)` 也只知道 rotation，因此 snapshot 层只能产出 `.rotation`，不会产出 `.alignment`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeInteractionOverlay(...)
// 功能说明: 修改前 renderer 只接 rotation interaction state；即使 session 以后持有 alignment state，也没有参数入口传入 overlay 生成流程。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil
) -> CanvasRenderSnapshot {
    let interactionOverlay = makeInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
    // ...
}
```

### 修改后

- `makeSnapshot(...)` 增加了 `alignmentInteractionState` 参数。
- `makeInteractionOverlay(...)` 也同步接入这个参数，确保 alignment 状态能进入 renderer 的 overlay 决策逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeSnapshot(...) / makeInteractionOverlay(...)
// 功能说明: 修改后 renderer 能同时接收 rotation 与 alignment 两类 interaction state，为后续 `.alignment` overlay 的生成提供正式入口。
func makeSnapshot(
    scene: CanvasScene,
    boardState: CanvasBoardState? = nil,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState = CanvasInteractionState(),
    inlineEditState: CanvasInlineEditState? = nil,
    rotationPreviewState: CanvasRotationPreviewState? = nil,
    rotationInteractionState: CanvasRotationInteractionState? = nil,
    alignmentInteractionState: CanvasAlignmentInteractionState? = nil
) -> CanvasRenderSnapshot {
    let interactionOverlay = makeInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState,
        alignmentInteractionState: alignmentInteractionState
    )
    // ...
}
```

## 修改四：`CanvasRenderer` 增加 alignment overlay 分支，并保持 rotation 优先级

### 修改前

- `makeInteractionOverlay(...)` 直接返回 `makeRotationInteractionOverlay(...)` 的结果。
- 这意味着 interaction overlay 的唯一实现仍是 rotation HUD。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeInteractionOverlay(...)
// 功能说明: 修改前 interactionOverlay 只有 rotation 分支；renderer 不会把对齐 guide 从 world 坐标映射到 screen segment。
private func makeInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?,
    rotationInteractionState: CanvasRotationInteractionState?
) -> CanvasInteractionRenderOverlay? {
    makeRotationInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    )
}
```

### 修改后

- `makeInteractionOverlay(...)` 现在先尝试 `rotation`，命中时立即返回；只有未命中 rotation 时，才继续尝试 `alignment`。
- 这与计划里“单一 `interactionOverlay` 槽位、rotation 与 alignment 不叠加”的约束一致。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeInteractionOverlay(...)
// 功能说明: 修改后 renderer 明确保持 `rotation > alignment` 的 overlay 优先级，继续沿用单一 interactionOverlay 槽位，不把两类 HUD 叠加到同一帧。
private func makeInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    rotationPreviewState: CanvasRotationPreviewState?,
    rotationInteractionState: CanvasRotationInteractionState?,
    alignmentInteractionState: CanvasAlignmentInteractionState?
) -> CanvasInteractionRenderOverlay? {
    if let rotationOverlay = makeRotationInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        rotationPreviewState: rotationPreviewState,
        rotationInteractionState: rotationInteractionState
    ) {
        return rotationOverlay
    }

    return makeAlignmentInteractionOverlay(
        scene: scene,
        camera: camera,
        interactionState: interactionState,
        inlineEditState: inlineEditState,
        alignmentInteractionState: alignmentInteractionState
    )
}
```

## 修改五：新增 `makeAlignmentInteractionOverlay(...)`，完成 world guide 到 screen guide 的映射

### 修改前

- `CanvasRenderer.swift` 中没有 `makeAlignmentInteractionOverlay(...)`。
- 即使 `CanvasAlignmentInteractionState` 内部已经有 `guides`、`xMatch`、`yMatch`，renderer 也不会把它们转成 `CanvasAlignmentInteractionOverlayPayload`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeAlignmentInteractionOverlay(...)
// 功能说明: 修改前该函数不存在；alignment solver 输出的 world guide 还没有接入 renderSnapshot.interactionOverlay。
```

### 修改后

- 新增 `makeAlignmentInteractionOverlay(...)`：
  - 先在 `inlineEditState != nil` 时直接屏蔽
  - 要求 `alignmentInteractionState.isActive == true`
  - 要求 `selectedItemID` 与 `alignmentInteractionState.itemID` 一致
  - 要求 scene 中还能找到对应 item
  - 最后把每条 `CanvasAlignmentGuide` 的 `worldStart/worldEnd` 映射成屏幕 `guideSegments`
- 这一步把 solver 结果正式折叠成 `CanvasInteractionRenderOverlay(payload: .alignment(...))`。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasRenderer.swift
// 函数名: makeAlignmentInteractionOverlay(...)
// 功能说明: 修改后 renderer 负责把 solver/state 里的世界坐标 guide 映射成屏幕线段，并封装成 `.alignment` payload；平台视图后续只需要消费 snapshot，不再自己算几何。
private func makeAlignmentInteractionOverlay(
    scene: CanvasScene,
    camera: CanvasCamera,
    interactionState: CanvasInteractionState,
    inlineEditState: CanvasInlineEditState?,
    alignmentInteractionState: CanvasAlignmentInteractionState?
) -> CanvasInteractionRenderOverlay? {
    guard inlineEditState == nil else {
        return nil
    }

    guard
        let alignmentInteractionState,
        alignmentInteractionState.isActive,
        interactionState.selectedItemID == alignmentInteractionState.itemID,
        scene.boardItem(withID: alignmentInteractionState.itemID) != nil
    else {
        return nil
    }

    let guideSegments = alignmentInteractionState.guides.map { guide in
        CanvasInteractionLineSegment(
            start: camera.worldToViewport(guide.worldStart),
            end: camera.worldToViewport(guide.worldEnd)
        )
    }

    return CanvasInteractionRenderOverlay(
        itemID: alignmentInteractionState.itemID,
        kind: .alignment,
        payload: .alignment(
            CanvasAlignmentInteractionOverlayPayload(
                guideSegments: guideSegments,
                xMatch: alignmentInteractionState.xMatch,
                yMatch: alignmentInteractionState.yMatch,
                isActive: alignmentInteractionState.isActive
            )
        )
    )
}
```

## 修改六：新增 snapshot 级测试，验证 alignment overlay 的生成与屏蔽规则

### 修改前

- 当前项目里还没有针对 `CanvasEditorSession.makeCanvasSnapshot()` 的 alignment overlay 测试。
- 也就是说，在本次修改前，没有自动化验证去证明：
  - `alignmentInteractionState` 会生成 `.alignment`
  - reading mode 会屏蔽 alignment overlay
  - `rotation` 会压过 `alignment`
  - `inline edit` 会屏蔽 alignment overlay

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: 无（修改前该文件不存在）
// 功能说明: 修改前项目里没有 snapshot 级 alignment overlay 测试，Phase 2 的 session/renderer 接线缺少自动化保护。
```

### 修改后

- 新增 `CanvasEditorSessionAlignmentOverlayTests.swift`，当前包含 4 个测试：
  - `testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState`
  - `testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode`
  - `testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay`
  - `testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit`
- 这些测试直接盯 `snapshot.interactionOverlay` 的最终行为，而不是只测 renderer 内部 helper。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() / testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode() / testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() / testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit()
// 功能说明: 修改后新增 snapshot 级自动化验证，直接保护 Phase 2 接线的可观察结果：生成 `.alignment`、reading mode 屏蔽、rotation 优先级和 inline edit 屏蔽。
@MainActor
final class CanvasEditorSessionAlignmentOverlayTests: XCTestCase {
    func testMakeCanvasSnapshotProducesAlignmentOverlayFromTransientState() throws {
        let item = makeAlignmentOverlayTestItem()
        let session = makeAlignmentOverlayTestSession(with: item)
        session.camera = CanvasCamera(
            center: .zero,
            zoomScale: 2,
            viewportSize: CGSize(width: 600, height: 400)
        )
        session.alignmentInteractionState = CanvasAlignmentInteractionState(
            itemID: item.id,
            guides: [
                CanvasAlignmentGuide(
                    orientation: .vertical,
                    worldStart: CGPoint(x: 50, y: -20),
                    worldEnd: CGPoint(x: 50, y: 80),
                    movingAnchor: .centerX,
                    referenceAnchor: .centerX,
                    referenceSource: .board
                )
            ],
            xMatch: CanvasAlignmentMatch(
                movingAnchor: .centerX,
                referenceAnchor: .centerX,
                referenceSource: .board,
                referenceCoordinate: 50,
                distanceInWorld: 0
            ),
            yMatch: nil
        )

        let snapshot = session.makeCanvasSnapshot()
        let interactionOverlay = try XCTUnwrap(snapshot.interactionOverlay)
        guard case let .alignment(payload) = interactionOverlay.payload else {
            XCTFail("Expected alignment interaction overlay payload.")
            return
        }

        XCTAssertTrue(payload.isActive)
        XCTAssertEqual(payload.xMatch?.referenceSource, .board)
        XCTAssertEqual(payload.guideSegments.count, 1)
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayInReadingMode() {
        // ... 同文件内继续验证 reading mode 自动屏蔽 alignment overlay ...
    }

    func testMakeCanvasSnapshotPrefersRotationOverlayOverAlignmentOverlay() throws {
        // ... 同文件内继续验证 rotation overlay 优先于 alignment overlay ...
    }

    func testMakeCanvasSnapshotHidesAlignmentOverlayDuringInlineEdit() {
        // ... 同文件内继续验证 inline edit 期间 alignment overlay 被屏蔽 ...
    }
}
```

## 修改七：测试层补上静态 retainer，修复 XCTest teardown 时的运行时崩溃

### 修改前

- 在本次 `Phase 2` 实施过程中，新测试第一次运行时发生了 `abort()`。
- 崩溃不是断言失败，而是 `CanvasEditorSession` 这类默认 `MainActor` 隔离对象在 XCTest teardown 阶段的释放时机问题。
- 修改前测试 helper 里只会创建 session，不会保留它。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: makeAlignmentOverlayTestSession(with:)
// 功能说明: 修改前测试 helper 只创建 session，不做静态保留；在当前工程默认 MainActor 隔离配置下，XCTest teardown 阶段会触发运行时 abort。
private func makeAlignmentOverlayTestSession(
    with item: CanvasTextItem
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionAlignmentOverlayTests.save",
        logPrefix: "[CanvasEditorSessionAlignmentOverlayTests]"
    )
    session.scene.setItems([.text(item)])
    session.interactionState.selectedItemID = item.id
    return session
}
```

### 修改后

- 测试文件新增 `CanvasEditorSessionAlignmentOverlayTestRetainer.sessions`。
- `makeAlignmentOverlayTestSession(with:)` 创建的 session 现在会追加到静态数组里，避免 teardown 期间提前释放。
- 这一步不改变产品逻辑，只是让 snapshot 级测试稳定可跑。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
// 函数名: CanvasEditorSessionAlignmentOverlayTestRetainer / makeAlignmentOverlayTestSession(with:)
// 功能说明: 修改后通过静态 retainer 保留测试用 session，消除 XCTest teardown 时的 actor-isolated 对象释放崩溃。
private enum CanvasEditorSessionAlignmentOverlayTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeAlignmentOverlayTestSession(
    with item: CanvasTextItem
) -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasEditorSessionAlignmentOverlayTests.save",
        logPrefix: "[CanvasEditorSessionAlignmentOverlayTests]"
    )
    session.scene.setItems([.text(item)])
    session.camera = CanvasCamera(
        center: .zero,
        zoomScale: 1,
        viewportSize: CGSize(width: 600, height: 400)
    )
    session.interactionState.selectedItemID = item.id
    CanvasEditorSessionAlignmentOverlayTestRetainer.sessions.append(session)
    return session
}
```

## 本次修改后的实际状态

- 已经落下来的能力：
  - `CanvasEditorSession` 可以持有 alignment transient state
  - reading mode 下会自动屏蔽 alignment transient state
  - `CanvasRenderer` 可以把 world guide 映射成 screen guideSegments
  - `CanvasRenderSnapshot.interactionOverlay` 可以产出 `.alignment`
  - `rotation > alignment` 的 overlay 优先级已经固定
  - snapshot 级测试已经覆盖命中与屏蔽语义
- 还没有落下来的能力：
  - iOS/macOS 控制器在真实拖拽时写入 `alignmentInteractionState`
  - pointer up / cancel 生命周期清理 alignment state
  - viewport 真实绘制 alignment guide 线条

## 验证结果

- `ReadLints`：未发现本次修改文件新增问题。
- 定向测试已通过：
  - `xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS" -only-testing:MyCanvas_Ver_0Tests/CanvasAlignmentGuideSolverTests -only-testing:MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests`
- 主目标构建已通过：
  - `xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination "platform=macOS"`
