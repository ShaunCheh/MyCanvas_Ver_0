# 20260407_135205_gif_phase5_menu_wiring_record

## 记录范围

- 记录内容：给共享上下文菜单新增 GIF 专用 UI action，并让它只在命中 `animatedGIF` item 时出现。
- 记录内容：在 `CanvasContextMenuActionResolver` 中补齐 GIF 目标识别和菜单候选注入逻辑，覆盖 `selectedItemBody` 与 `unselectedItemBody` 两条路径。
- 记录内容：在 iOS / macOS 控制器中补齐 GIF 菜单动作路由，打通 `gifFrameImportRequest(...) -> .importMedia(request)` 的执行入口。
- 记录内容：新增 iOS / macOS 两端的 GIF 帧导入页面壳子，作为后续阶段 6 / 7 的平台承载点。
- 记录内容：新增 resolver 定向测试，验证 GIF 菜单只对 GIF 出现，且不会误污染静态图或视频菜单。
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift`
- 本记录不包含：阶段 6 的 iOS 多选网格与 GIF 缩略图加载。
- 本记录不包含：阶段 7 的 macOS 多选网格与 GIF 缩略图加载。
- 本记录不包含：`.cursor/plans/*.md` 的计划文件状态变化。
- 本记录不包含：git commit / push。

## 修改一：共享菜单动作枚举增加 GIF 专用 UI action

### 修改前

- 共享层只有视频菜单动作 `editVideoDisplayFrame`。
- GIF 虽然已经在共享层具备 request builder 和导入执行链路，但菜单状态模型没有对应的 UI action ID，平台层也就没有稳定路由点。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 类型/函数: CanvasContextMenuUIActionID
// 功能说明: 修改前共享菜单动作枚举只包含视频展示画面入口，没有 GIF 帧导入入口。
enum CanvasContextMenuUIActionID: String {
    case editVideoDisplayFrame

    var rawValueDescription: String {
        rawValue
    }
}
```

### 修改后

- 新增 `CanvasContextMenuUIActionID.importGIFFrames`。
- GIF 菜单动作和视频菜单动作保持同一层级，仍然走“共享 resolver 决策，平台控制器消费”的结构，不额外开 GIF 特例通道。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuState.swift
// 类型/函数: CanvasContextMenuUIActionID
// 功能说明: 修改后共享菜单动作枚举新增 GIF 帧导入入口，给后续 resolver 和平台路由提供稳定 action ID。
enum CanvasContextMenuUIActionID: String {
    case editVideoDisplayFrame
    case importGIFFrames

    var rawValueDescription: String {
        rawValue
    }
}
```

## 修改二：Resolver 只在命中 `animatedGIF` 时注入 GIF 菜单，并覆盖已选 / 未选 item 两条路径

### 修改前

- `CanvasContextMenuActionResolver` 只识别视频 item，对视频插入 `.editVideoDisplayFrame`。
- `selectedItemActionIDs(...)` 和 `unselectedItemActionIDs(...)` 都没有 GIF 分支。
- 这意味着 GIF item 即使已经具备共享导入能力，也无法从长按菜单进入这条链路。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 类型/函数: uiActionDescriptor(for:context:session:) / candidateActionIDs(for:session:)
// 功能说明: 修改前 resolver 只会为视频生成 UI action，GIF 不会在菜单中出现独立入口。
private func uiActionDescriptor(
    for uiActionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> CanvasContextMenuActionDescriptor {
    switch uiActionID {
    case .editVideoDisplayFrame:
        return CanvasContextMenuActionDescriptor(
            title: "Set Display Frame",
            systemImageName: "movieclapper",
            isEnabled: targetVideoItemID(
                in: context,
                session: session
            ) != nil,
            isActive: false
        )
    }
}

let includeVideoDisplayFrameAction =
    targetVideoItemID(in: context, session: session) != nil
```

### 修改后

- 新增 `targetGIFItemID(in:session:)`，明确判定条件是：
  - `context.targetItemID` 存在
  - item 不是视频
  - `item.assetKind == .animatedGIF`
- 新增 `includeGIFFrameImportAction`，并在 `selectedItemBody` / `unselectedItemBody` 两条路径里注入 `.uiAction(.importGIFFrames)`。
- `uiActionDescriptor(...)` 为 GIF 菜单提供独立标题与图标。
- `cropHandle` / `cropOutline` 路径仍然不显示 GIF 菜单，保持现有编辑句柄菜单语义不被污染。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 类型/函数: uiActionDescriptor(for:context:session:)
// 功能说明: 修改后 resolver 会为 GIF 目标生成独立的菜单描述符，不和视频动作混用。
private func uiActionDescriptor(
    for uiActionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> CanvasContextMenuActionDescriptor {
    switch uiActionID {
    case .editVideoDisplayFrame:
        return CanvasContextMenuActionDescriptor(
            title: "Set Display Frame",
            systemImageName: "movieclapper",
            isEnabled: targetVideoItemID(
                in: context,
                session: session
            ) != nil,
            isActive: false
        )
    case .importGIFFrames:
        return CanvasContextMenuActionDescriptor(
            title: "Import GIF Frames",
            systemImageName: "square.grid.3x3",
            isEnabled: targetGIFItemID(
                in: context,
                session: session
            ) != nil,
            isActive: false
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 类型/函数: candidateActionIDs(for:session:) / selectedItemActionIDs(...) / unselectedItemActionIDs(...)
// 功能说明: 修改后 GIF 动作会在已选和未选 item body 两条菜单路径中按条件注入。
let includeVideoDisplayFrameAction =
    targetVideoItemID(in: context, session: session) != nil
let includeGIFFrameImportAction =
    targetGIFItemID(in: context, session: session) != nil

switch context.targetKind {
case .selectedItemBody, .selectionHandle, .rotateHandle:
    return selectedItemActionIDs(
        includeCropCommand: targetTextItem == nil,
        includeBeginTextEditCommand: targetTextItem != nil,
        includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
        includeGIFFrameImportAction: includeGIFFrameImportAction
    )
case .unselectedItemBody:
    return unselectedItemActionIDs(
        includeBeginTextEditCommand: targetTextItem != nil,
        includeVideoDisplayFrameAction: includeVideoDisplayFrameAction,
        includeGIFFrameImportAction: includeGIFFrameImportAction
    )
case .cropHandle, .cropOutline:
    return selectedItemActionIDs(
        includeCropCommand: true,
        includeBeginTextEditCommand: false,
        includeVideoDisplayFrameAction: false,
        includeGIFFrameImportAction: false
    )
default:
    return [.command(.clearSelection), .command(.undo), .command(.redo)]
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/ContextMenu/CanvasContextMenuCommandResolver.swift
// 类型/函数: targetGIFItemID(in:session:)
// 功能说明: 修改后 resolver 在共享层集中识别“合法 GIF 菜单目标”，避免平台层各自复制判断逻辑。
private func targetGIFItemID(
    in context: CanvasContextMenuContext,
    session: CanvasEditorSession
) -> CanvasItemID? {
    guard
        let itemID = context.targetItemID,
        let item = session.scene.item(withID: itemID),
        item.isVideo == false,
        item.assetKind == .animatedGIF
    else {
        return nil
    }

    return itemID
}
```

## 修改三：iOS / macOS 控制器新增 GIF 菜单分支，并打通 `gifFrameImportRequest -> importMedia`

### 修改前

- 两端控制器只消费视频 UI action。
- `performContextMenuUIAction(...)` 没有 GIF 分支。
- 平台层也没有 `presentGIFFrameImportEditor(for:)` 或 `performGIFFrameImport(...)` 这种承接共享 builder 的入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: performContextMenuUIAction(_:context:)
// 功能说明: 修改前 iOS 端只响应视频菜单动作，没有 GIF 帧导入路由。
private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }

        presentVideoDisplayFrameEditor(for: itemID)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: performContextMenuUIAction(_:context:)
// 功能说明: 修改前 macOS 端也只消费视频展示画面动作，没有 GIF 的菜单分支和导入执行入口。
private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }

        presentVideoDisplayFrameEditor(for: itemID)
    }
}
```

### 修改后

- iOS / macOS 都新增：
  - `targetGIFItemID(for:)`
  - `presentGIFFrameImportEditor(for:)`
  - `performGIFFrameImport(for:frameIndices:)`
- 平台层不自己拼装导入 request，而是继续复用共享层 `editorSession.gifFrameImportRequest(...)`。
- request 构造完成后，仍然通过统一的 `performCommand(.importMedia(request))` 落板，保持阶段 2-4 扩出来的通用导入链路不分叉。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 类型/函数: performContextMenuUIAction(_:context:) / targetGIFItemID(for:) / presentGIFFrameImportEditor(for:) / performGIFFrameImport(for:frameIndices:)
// 功能说明: 修改后 iOS 端会把 GIF 菜单动作路由到专用页面，并在导入时继续复用共享 request builder 与 importMedia 命令链。
private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }

        presentVideoDisplayFrameEditor(for: itemID)
    case .importGIFFrames:
        guard let itemID = targetGIFItemID(for: context) else {
            return
        }

        presentGIFFrameImportEditor(for: itemID)
    }
}

private func targetGIFItemID(
    for context: CanvasContextMenuContext
) -> CanvasItemID? {
    guard
        let itemID = context.targetItemID,
        let item = scene.item(withID: itemID),
        item.isVideo == false,
        item.assetKind == .animatedGIF
    else {
        return nil
    }

    return itemID
}

private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewController == nil else {
        return
    }

    let editorViewController = iOSGIFFrameImportViewController(
        itemID: itemID,
        configuration: .current
    ) { [weak self] frameIndices in
        guard let self else {
            throw iOSGIFFrameImportFlowError.presenterUnavailable
        }

        try self.performGIFFrameImport(
            for: itemID,
            frameIndices: frameIndices
        )
    }
    present(editorViewController, animated: true)
}

private func performGIFFrameImport(
    for itemID: CanvasItemID,
    frameIndices: [Int]
) throws {
    let request = try editorSession.gifFrameImportRequest(
        for: itemID,
        frameIndices: frameIndices
    )
    performCommand(.importMedia(request))
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 类型/函数: performContextMenuUIAction(_:context:) / targetGIFItemID(for:) / presentGIFFrameImportEditor(for:) / performGIFFrameImport(for:frameIndices:)
// 功能说明: 修改后 macOS 端会把 GIF 菜单动作路由到 sheet 容器，并沿用同一条共享 request builder 与 importMedia 执行链。
private func performContextMenuUIAction(
    _ actionID: CanvasContextMenuUIActionID,
    context: CanvasContextMenuContext
) {
    switch actionID {
    case .editVideoDisplayFrame:
        guard let itemID = targetVideoItemID(for: context) else {
            return
        }

        presentVideoDisplayFrameEditor(for: itemID)
    case .importGIFFrames:
        guard let itemID = targetGIFItemID(for: context) else {
            return
        }

        presentGIFFrameImportEditor(for: itemID)
    }
}

private func targetGIFItemID(
    for context: CanvasContextMenuContext
) -> CanvasItemID? {
    guard
        let itemID = context.targetItemID,
        let item = scene.item(withID: itemID),
        item.isVideo == false,
        item.assetKind == .animatedGIF
    else {
        return nil
    }

    return itemID
}

private func presentGIFFrameImportEditor(for itemID: CanvasItemID) {
    guard presentedViewControllers?.isEmpty != false else {
        return
    }

    let editorViewController = macOSGIFFrameImportViewController(
        itemID: itemID,
        configuration: .current
    ) { [weak self] frameIndices in
        guard let self else {
            throw macOSGIFFrameImportFlowError.presenterUnavailable
        }

        try self.performGIFFrameImport(
            for: itemID,
            frameIndices: frameIndices
        )
    }
    presentAsSheet(editorViewController)
}

private func performGIFFrameImport(
    for itemID: CanvasItemID,
    frameIndices: [Int]
) throws {
    let request = try editorSession.gifFrameImportRequest(
        for: itemID,
        frameIndices: frameIndices
    )
    performCommand(.importMedia(request))
}
```

## 修改四：新增 iOS / macOS GIF 帧导入页面壳子，为后续多选网格 UI 提供平台容器

### 修改前

- 阶段 5 之前不存在 GIF 导入页面文件。
- 就算菜单已经能识别 GIF，也没有一个平台原生容器可被打开，更谈不上在阶段 6 / 7 往里填缩略图网格、多选状态和导入按钮逻辑。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: 文件级新增
// 功能说明: 修改前无此文件，iOS 端没有 GIF 帧导入页面壳子。
// 无
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: 文件级新增
// 功能说明: 修改前无此文件，macOS 端没有 GIF 帧导入页面壳子。
// 无
```

### 修改后

- 新增 `iOSGIFFrameImportViewController`，使用 `fullScreen + coverVertical` 作为阶段 5 承接容器。
- 新增 `macOSGIFFrameImportViewController`，使用 sheet 承接后续多选 UI。
- 当前两个页面都只保留：
  - 标题
  - `Cancel`
  - `Import`
  - 基于 `CanvasGIFFrameImportConfiguration.selectionGrid.columns` 的占位说明
  - 导入回调与错误提示
- 真正的 `UICollectionView` / `NSCollectionView` 多选网格仍明确留在后续阶段，不在这里提前混入。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSGIFFrameImportViewController.swift
// 类型/函数: iOSGIFFrameImportViewController.init(...) / viewDidLoad() / handleImportButtonTap()
// 功能说明: 修改后 iOS 端已经有可被 GIF 菜单打开的全屏容器，后续阶段可以直接在这里填入 4 列多选网格和缩略图加载。
final class iOSGIFFrameImportViewController: UIViewController {
    private let itemID: CanvasItemID
    private let configuration: CanvasGIFFrameImportConfiguration
    private let onImportSelectedFrames: ([Int]) throws -> Void

    init(
        itemID: CanvasItemID,
        configuration: CanvasGIFFrameImportConfiguration = .current,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.itemID = itemID
        self.configuration = configuration
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
        modalTransitionStyle = .coverVertical
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
    }

    @objc
    private func handleImportButtonTap() {
        guard
            isImporting == false,
            selectedFrameIndices.isEmpty == false
        else {
            return
        }

        isImporting = true
        do {
            try onImportSelectedFrames(selectedFrameIndices)
            dismiss(animated: true)
        } catch {
            isImporting = false
            presentError(
                title: "Unable to Import GIF Frames",
                message: error.localizedDescription
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSGIFFrameImportViewController.swift
// 类型/函数: macOSGIFFrameImportViewController.init(...) / viewDidLoad() / handleImportButtonClick()
// 功能说明: 修改后 macOS 端已经有可被 GIF 菜单打开的 sheet 容器，后续阶段可以继续在这里填入 4 列 NSCollectionView 多选网格。
final class macOSGIFFrameImportViewController: NSViewController {
    private let itemID: CanvasItemID
    private let configuration: CanvasGIFFrameImportConfiguration
    private let onImportSelectedFrames: ([Int]) throws -> Void

    init(
        itemID: CanvasItemID,
        configuration: CanvasGIFFrameImportConfiguration = .current,
        onImportSelectedFrames: @escaping ([Int]) throws -> Void
    ) {
        self.itemID = itemID
        self.configuration = configuration
        self.onImportSelectedFrames = onImportSelectedFrames
        super.init(nibName: nil, bundle: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 640, height: 320)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupViewHierarchy()
        setupConstraints()
        configureButtons()
        applyInitialState()
    }

    @objc
    private func handleImportButtonClick() {
        guard
            isImporting == false,
            selectedFrameIndices.isEmpty == false
        else {
            return
        }

        isImporting = true
        do {
            try onImportSelectedFrames(selectedFrameIndices)
            dismiss(self)
        } catch {
            isImporting = false
            presentError(
                title: "Unable to Import GIF Frames",
                message: error.localizedDescription
            )
        }
    }
}
```

## 修改五：新增 resolver 定向测试，确保 GIF 菜单只对 GIF 暴露

### 修改前

- 工程里还没有上下文菜单 resolver 的 GIF 专用测试。
- 没有自动验证以下关键边界：
  - GIF 是否会在 `selectedItemBody` 出现 `importGIFFrames`
  - GIF 是否会在 `unselectedItemBody` 也出现 `importGIFFrames`
  - 静态图是否不会误带上 GIF 动作
  - 视频是否仍保持 `editVideoDisplayFrame`，同时不出现 GIF 动作

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 类型/函数: 文件级新增
// 功能说明: 修改前没有这组定向测试，无法自动验证 GIF / 静态图 / 视频三类 item 的菜单边界。
// 无
```

### 修改后

- 新增 `CanvasContextMenuActionResolverTests`。
- 测试集中验证了：
  - GIF 已选时出现 `importGIFFrames`
  - GIF 未选时也出现 `importGIFFrames`
  - 静态图不出现 `importGIFFrames`
  - 视频保持 `editVideoDisplayFrame`，同时排除 `importGIFFrames`
- 测试夹具沿用前面几阶段的保活思路，使用 `CanvasContextMenuActionResolverTestRetainer` 持有 session，避免测试期对象析构不稳定。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 类型/函数: CanvasContextMenuActionResolverTests
// 功能说明: 修改后测试会直接验证 GIF 菜单动作的出现边界，防止 resolver 把 GIF、静态图、视频三类 item 的 UI action 混淆。
@MainActor
final class CanvasContextMenuActionResolverTests: XCTestCase {
    func testSelectedAnimatedGIFIncludesGIFFrameImportAction() throws {
        let session = makeContextMenuActionResolverTestSession()
        let gifItem = CanvasImageItem(
            asset: CanvasImageAsset.transientAnimatedGIF(
                posterCGImage: try makeContextMenuActionResolverTestImage(
                    red: 1,
                    green: 0,
                    blue: 0
                )
            ),
            center: CGPoint(x: 40, y: 60),
            size: CGSize(width: 120, height: 80),
            zIndex: 0
        )
        session.scene.append(gifItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: gifItem.id,
                selectedItemID: gifItem.id
            ),
            session: session
        )

        XCTAssertTrue(actionStates.contains(where: isGIFFrameImportAction))
        XCTAssertFalse(actionStates.contains(where: isVideoDisplayFrameAction))
    }

    func testVideoItemKeepsVideoActionAndExcludesGIFAction() throws {
        let session = makeContextMenuActionResolverTestSession()
        let videoItem = CanvasImageItem(
            asset: CanvasImageAsset.transientStaticImage(
                cgImage: try makeContextMenuActionResolverTestImage(
                    red: 1,
                    green: 1,
                    blue: 0
                )
            ),
            videoSource: CanvasVideoSource(
                assetReference: .persisted(filename: "sample.mov")
            ),
            posterTimeSeconds: 0.5,
            center: CGPoint(x: 80, y: 110),
            size: CGSize(width: 160, height: 90),
            zIndex: 0
        )
        session.scene.append(videoItem)

        let actionStates = CanvasContextMenuActionResolver().actionStates(
            for: makeContextMenuContext(
                targetKind: .selectedItemBody,
                targetItemID: videoItem.id,
                selectedItemID: videoItem.id
            ),
            session: session
        )

        XCTAssertTrue(actionStates.contains(where: isVideoDisplayFrameAction))
        XCTAssertFalse(actionStates.contains(where: isGIFFrameImportAction))
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests.swift
// 类型/函数: makeContextMenuActionResolverTestSession() / makeContextMenuContext(...) / isGIFFrameImportAction(_:)
// 功能说明: 修改后测试夹具提供最小 session、context 和 action 判定辅助函数，让 resolver 测试只关注菜单边界本身。
private enum CanvasContextMenuActionResolverTestRetainer {
    static var sessions: [CanvasEditorSession] = []
}

private func makeContextMenuActionResolverTestSession() -> CanvasEditorSession {
    let session = CanvasEditorSession(
        saveQueueLabel: "CanvasContextMenuActionResolverTests",
        logPrefix: "[CanvasContextMenuActionResolverTests]"
    )
    CanvasContextMenuActionResolverTestRetainer.sessions.append(session)
    return session
}

private func makeContextMenuContext(
    targetKind: CanvasContextMenuTargetKind,
    targetItemID: CanvasItemID,
    selectedItemID: CanvasItemID?
) -> CanvasContextMenuContext {
    CanvasContextMenuContext(
        invocationViewportPoint: CGPoint(x: 12, y: 18),
        invocationWorldPoint: CGPoint(x: 12, y: 18),
        targetKind: targetKind,
        editOverlayHitTargetKind: nil,
        targetItemID: targetItemID,
        anchorRect: nil,
        selectedItemID: selectedItemID,
        isInlineEditModeActive: false,
        isInlineCropModeActive: false
    )
}

private func isGIFFrameImportAction(
    _ actionState: CanvasContextMenuActionState
) -> Bool {
    if case .uiAction(.importGIFFrames) = actionState.actionID {
        return true
    }

    return false
}
```

## 验证结果

- 已执行：`xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasContextMenuActionResolverTests"`
- 结果：`CanvasContextMenuActionResolverTests` 通过。
- 已执行：`xcodebuild build -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "generic/platform=iOS"`
- 结果：iOS 构建通过，说明 iOS 平台接线与新增页面壳子已可编译。
- 已检查：`CanvasContextMenuState.swift`、`CanvasContextMenuCommandResolver.swift`、`iOSViewController.swift`、`macOSViewController.swift`、`iOSGIFFrameImportViewController.swift`、`macOSGIFFrameImportViewController.swift`、`CanvasContextMenuActionResolverTests.swift` 无新增 linter 问题。

