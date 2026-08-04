# 20260804_122221_handle_active_feedback_phase5_record

## 时间戳与记录范围

- 时间戳来源：在项目根目录执行系统命令 `date +"%Y%m%d_%H%M%S"`。
- 命令输出：`20260804_122221`。
- 对应任务：`Canvas Handle Active Feedback` 分阶段计划的阶段 5——共享视觉样式与双端 viewport 渲染。
- 参考依据：记录创建前的 `git status --short`、`git diff --stat`、当前 changes、相关文件内容及测试/构建输出。
- 本次没有提交代码，也没有修改现有 `.md` 文件；本文件是按要求新增的阶段记录。

记录创建前，当前 changes 为：

- 修改 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`。
- 修改 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`。
- 新增 `MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift`。
- 新增 `MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift`。

## 修改目标

阶段 1～4 已经完成 handle identity、pressed/dragging 状态机、snapshot `visualState` 投影和双端 pointer 生命周期接入，但 viewport 尚未消费 `CanvasEditHandleGeometry.visualState`。

本阶段完成以下闭环：

- selection resize、multi-selection resize、rotate、arrow endpoint 和 group frame resize 使用蓝色 accent。
- crop resize 使用橙色 accent。
- normal：白色 fill + accent stroke。
- active：accent fill + 白色 stroke。
- iOS/macOS 每次刷新可见 handle 时都重新应用样式，避免复用 `CAShapeLayer` 残留上一个 handle 的 active 颜色。
- handle 大小、形状、line width、path、contents scale 和隐藏逻辑保持不变。

## 修改前：viewport 只在 layer 创建时设置固定颜色

修改前，iOS/macOS 都在 configure 阶段直接设置固定颜色：

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | configureSelectionHandleLayers()（修改前）
private func configureSelectionHandleLayers() {
    for role in CanvasSelectionHandleRole.allCases {
        let handleLayer = CAShapeLayer()
        handleLayer.fillColor = Self.selectionHandleFillColor
        handleLayer.strokeColor = Self.selectionStrokeColor
        handleLayer.lineWidth = Self.selectionHandleLineWidth
        handleLayer.isHidden = true
        overlayLayer.addSublayer(handleLayer)
        selectionHandleLayers[role] = handleLayer
    }
}
```

crop handle 也使用独立的固定颜色：

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift | configureCropHandleLayers()（修改前）
private func configureCropHandleLayers() {
    for role in CanvasCropHandleRole.allCases {
        let handleLayer = CAShapeLayer()
        handleLayer.fillColor = Self.cropHandleFillColor
        handleLayer.strokeColor = Self.cropOutlineStrokeColor
        handleLayer.lineWidth = Self.cropHandleLineWidth
        handleLayer.isHidden = true
        overlayLayer.addSublayer(handleLayer)
        cropHandleLayers[role] = handleLayer
    }
}
```

刷新时只使用 handle 几何，没有读取 `visualState`：

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | refreshSelectionChrome(from:)（修改前）
handleLayer.frame = bounds
handleLayer.path = Self.selectionHandlePath(
    for: role,
    centeredAt: handle.screenCenter,
    rotationRadians: handle.screenRotationRadians
)
handleLayer.isHidden = false
handleLayer.contentsScale = currentContentsScale
```

这导致阶段 4 虽然能够让 snapshot 中的目标 handle 进入 `.active`，但 layer 仍始终显示固定的 normal 颜色。

此外，selection 和 group frame 共用 `selectionHandleLayers`。如果只在 pointer 事件发生时修改 layer 颜色，而不在每次 refresh 中重设，就会在 selection/group overlay 切换时残留上一次 active 颜色。

## 修改后 1：新增 CoreGraphics-only 共享样式解析器

新增共享文件，不依赖 UIKit 或 AppKit。accent 由 `CanvasEditHandleKind` 决定，平台调用点不需要手工指定 selection/crop family：

```swift
// MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift | CanvasEditHandleVisualStyleResolver.resolve(kind:visualState:)
import CoreGraphics

struct CanvasEditHandleVisualStyle {
    let fillColor: CGColor
    let strokeColor: CGColor
}

enum CanvasEditHandleVisualStyleResolver {
    private static let neutralColor = CGColor(gray: 1, alpha: 1)
    private static let selectionAccentColor = CGColor(
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    private static let cropAccentColor = CGColor(
        red: 1,
        green: 149.0 / 255.0,
        blue: 0,
        alpha: 1
    )

    static func resolve(
        kind: CanvasEditHandleKind,
        visualState: CanvasEditHandleVisualState
    ) -> CanvasEditHandleVisualStyle {
        let accentColor = accentColor(for: kind)
        switch visualState {
        case .normal:
            return CanvasEditHandleVisualStyle(
                fillColor: neutralColor,
                strokeColor: accentColor
            )
        case .active:
            return CanvasEditHandleVisualStyle(
                fillColor: accentColor,
                strokeColor: neutralColor
            )
        }
    }
}
```

family 映射使用穷尽 switch：

```swift
// MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift | CanvasEditHandleVisualStyleResolver.accentColor(for:)
private static func accentColor(
    for kind: CanvasEditHandleKind
) -> CGColor {
    switch kind {
    case .cropResize:
        return cropAccentColor
    case .selectionResize,
         .rotate,
         .arrowEndpoint,
         .groupFrameResize:
        return selectionAccentColor
    }
}
```

因此新增 handle kind 时必须明确选择 accent，避免静默落入错误颜色。

viewport 使用 geometry 入口时，resolver 同时读取 identity kind 和当前 visual state：

```swift
// MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift | CanvasEditHandleVisualStyleResolver.resolve(for:)
static func resolve(
    for handle: CanvasEditHandleGeometry
) -> CanvasEditHandleVisualStyle {
    resolve(
        kind: handle.identity.kind,
        visualState: handle.visualState
    )
}
```

## 修改后 2：双端统一应用共享样式

iOS/macOS viewport 都增加两个本地 layer adapter：

- `kind + visualState` 入口用于 layer 初次创建，明确初始化为 normal。
- `CanvasEditHandleGeometry` 入口用于每次可见刷新。
- line width 仍由各平台现有常量传入，没有移入共享样式。

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | applyEditHandleVisualStyle(to:for:lineWidth:)
private func applyEditHandleVisualStyle(
    to handleLayer: CAShapeLayer,
    for handle: CanvasEditHandleGeometry,
    lineWidth: CGFloat
) {
    let style = CanvasEditHandleVisualStyleResolver.resolve(for: handle)
    handleLayer.fillColor = style.fillColor
    handleLayer.strokeColor = style.strokeColor
    handleLayer.lineWidth = lineWidth
}
```

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift | applyEditHandleVisualStyle(to:kind:visualState:lineWidth:)
private func applyEditHandleVisualStyle(
    to handleLayer: CAShapeLayer,
    kind: CanvasEditHandleKind,
    visualState: CanvasEditHandleVisualState,
    lineWidth: CGFloat
) {
    let style = CanvasEditHandleVisualStyleResolver.resolve(
        kind: kind,
        visualState: visualState
    )
    handleLayer.fillColor = style.fillColor
    handleLayer.strokeColor = style.strokeColor
    handleLayer.lineWidth = lineWidth
}
```

selection handle 创建时不再直接拼装颜色：

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | configureSelectionHandleLayers()
applyEditHandleVisualStyle(
    to: handleLayer,
    kind: .selectionResize(role),
    visualState: .normal,
    lineWidth: Self.selectionHandleLineWidth
)
```

crop、arrow endpoint 和 rotate 的初始 normal 样式也走同一个 resolver：

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift | configureCropHandleLayers() / configureArrowEndpointHandleLayers() / configureRotateHandleLayer()
private func configureCropHandleLayers() {
    for role in CanvasCropHandleRole.allCases {
        let handleLayer = CAShapeLayer()
        applyEditHandleVisualStyle(
            to: handleLayer,
            kind: .cropResize(role),
            visualState: .normal,
            lineWidth: Self.cropHandleLineWidth
        )
        handleLayer.isHidden = true
        overlayLayer.addSublayer(handleLayer)
        cropHandleLayers[role] = handleLayer
    }
}

private func configureArrowEndpointHandleLayers() {
    for role in CanvasArrowEndpointRole.allCases {
        let handleLayer = CAShapeLayer()
        applyEditHandleVisualStyle(
            to: handleLayer,
            kind: .arrowEndpoint(role),
            visualState: .normal,
            lineWidth: Self.selectionHandleLineWidth
        )
        handleLayer.isHidden = true
        overlayLayer.addSublayer(handleLayer)
        arrowEndpointHandleLayers[role] = handleLayer
    }
}

private func configureRotateHandleLayer() {
    applyEditHandleVisualStyle(
        to: rotateHandleLayer,
        kind: .rotate,
        visualState: .normal,
        lineWidth: Self.rotateHandleLineWidth
    )
    rotateHandleLayer.isHidden = true
}
```

## 修改后 3：每次可见 refresh 都重写 fill/stroke

双端以下五条可见路径均在设置 frame/path 前应用 geometry 当前样式：

1. `refreshGroupEditOverlay(from:)`：group frame resize handles。
2. `refreshCropChrome(from:)`：crop handles。
3. `refreshSelectionChrome(from:)`：selection/multi-selection resize handles。
4. `refreshSelectionChrome(from:)`：arrow endpoint handles。
5. `refreshRotateAffordance(_:)`：single/multi-selection rotate handle。

group frame 和 selection resize 使用当前 geometry 的样式，并保持原有 selection line width 与路径：

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | refreshGroupEditOverlay(from:) / refreshSelectionChrome(from:)
applyEditHandleVisualStyle(
    to: handleLayer,
    for: handle,
    lineWidth: Self.selectionHandleLineWidth
)

handleLayer.frame = bounds
handleLayer.path = Self.selectionHandlePath(
    for: role,
    centeredAt: handle.screenCenter,
    rotationRadians: handle.screenRotationRadians
)
handleLayer.isHidden = false
handleLayer.contentsScale = currentContentsScale
```

crop 可见刷新使用现有 crop line width：

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | refreshCropChrome(from:)
applyEditHandleVisualStyle(
    to: handleLayer,
    for: handle,
    lineWidth: Self.cropHandleLineWidth
)
```

rotate handle 使用 `rotateAffordance.handle`：

```swift
// MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift | refreshRotateAffordance(_:)
applyEditHandleVisualStyle(
    to: rotateHandleLayer,
    for: rotateAffordance.handle,
    lineWidth: Self.rotateHandleLineWidth
)

let handleRect = Self.rotateHandleRect(
    centeredAt: rotateAffordance.handle.screenCenter
)
```

selection/group frame 共用 layer 时，当前 snapshot 中每个可见 handle 的 normal/active 状态都会覆盖旧颜色，因此不依赖 hide 时清色。

## 修改后 4：清理旧 handle 专用颜色常量

旧的 `selectionHandleFillColor` 同时还被 rotation text background 使用。抽取 handle 样式后，它被重命名为只表达真实职责的 `rotationTextBackgroundFillColor`：

```swift
// MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift | configureRotationTextBackgroundLayer()
private static let rotationTextBackgroundFillColor = CGColor(
    gray: 1,
    alpha: 1
)

private func configureRotationTextBackgroundLayer() {
    rotationTextBackgroundLayer.fillColor =
        Self.rotationTextBackgroundFillColor
    rotationTextBackgroundLayer.strokeColor = Self.selectionStrokeColor
    rotationTextBackgroundLayer.lineWidth = Self.selectionHandleLineWidth
    rotationTextBackgroundLayer.isHidden = true
}
```

仅供 crop handle 使用的 `cropHandleFillColor` 已从 iOS/macOS viewport 删除。handle fill/stroke 的来源统一为共享 resolver。

## 测试新增

新增 `CanvasEditHandleVisualStyleTests`，覆盖：

- selection resize、rotate、arrow endpoint、group frame resize 共用蓝色 accent。
- crop 使用橙色 accent，不串用 selection 蓝色。
- normal/active 的 fill/stroke 确实互换。
- `resolve(for:)` 确实使用 geometry 的 identity kind 和 visual state。

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift | testSelectionFamiliesUseWhiteAndBlueForNormalAndActiveStates()
let selectionKinds: [CanvasEditHandleKind] = [
    .selectionResize(.topLeading),
    .rotate,
    .arrowEndpoint(.start),
    .groupFrameResize(.bottomTrailing)
]

for kind in selectionKinds {
    let normalStyle = CanvasEditHandleVisualStyleResolver.resolve(
        kind: kind,
        visualState: .normal
    )
    let activeStyle = CanvasEditHandleVisualStyleResolver.resolve(
        kind: kind,
        visualState: .active
    )

    try assertColor(
        normalStyle.fillColor,
        red: 1,
        green: 1,
        blue: 1,
        alpha: 1
    )
    try assertColor(
        normalStyle.strokeColor,
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    try assertColor(
        activeStyle.fillColor,
        red: 0,
        green: 122.0 / 255.0,
        blue: 1,
        alpha: 1
    )
    try assertColor(
        activeStyle.strokeColor,
        red: 1,
        green: 1,
        blue: 1,
        alpha: 1
    )
}
```

## 首次测试失败与修正

第一次执行相关测试时：

- 实现与测试 target 均成功编译。
- 既有 `CanvasEditHandleInteractionStateTests` 和 `CanvasEditHandleIdentityPipelineTests` 全部通过。
- 新增的 3 个 visual style 测试失败，测试命令退出码为 65。

失败不是 resolver 输出错误，而是测试 helper 先把 `CGColor(red:green:blue:alpha:)` 创建的 Generic RGB 颜色转换为 sRGB，再拿转换后的分量与构造时原始分量比较。色彩空间转换会改变数值：

- selection green：原始 `122 / 255 = 0.478431...`，转换后约为 `0.569464...`。
- crop green：原始 `149 / 255 = 0.584313...`，转换后约为 `0.649796...`。

首次失败的比较方式：

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift | assertColor(_:red:green:blue:alpha:)（首次失败版本）
let colorSpace = try XCTUnwrap(
    CGColorSpace(name: CGColorSpace.sRGB),
    file: file,
    line: line
)
let convertedColor = try XCTUnwrap(
    color.converted(
        to: colorSpace,
        intent: .defaultIntent,
        options: nil
    ),
    file: file,
    line: line
)
let components = try XCTUnwrap(
    convertedColor.components,
    file: file,
    line: line
)

XCTAssertEqual(
    components[1],
    green,
    accuracy: 0.0001,
    file: file,
    line: line
)
```

修正后，测试直接读取颜色自身分量，并把 grayscale-alpha 的两个分量规范化为 RGBA；不再进行会改变数值的色彩空间转换：

```swift
// MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift | assertColor(_:red:green:blue:alpha:)（当前版本）
let components = try XCTUnwrap(
    color.components,
    file: file,
    line: line
)
let rgbaComponents: [CGFloat]
switch components.count {
case 2:
    rgbaComponents = [
        components[0],
        components[0],
        components[0],
        components[1]
    ]
case 4:
    rgbaComponents = components
default:
    XCTFail(
        "Expected grayscale-alpha or RGBA components, got \(components)",
        file: file,
        line: line
    )
    return
}
```

该修正只改变测试断言方式，没有修改共享 resolver 或双端 viewport 的视觉实现。

## 验证命令与最终结果

相关测试顺序执行：

```bash
# 项目根目录 /Users/shaun/cloudDev/MyCanvas_Ver_0 | 阶段 5 相关测试
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS' \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleInteractionStateTests \
  -only-testing:MyCanvas_Ver_0Tests/CanvasEditHandleIdentityPipelineTests
```

双端构建顺序执行，避免 DerivedData 并发锁：

```bash
# 项目根目录 /Users/shaun/cloudDev/MyCanvas_Ver_0 | 阶段 5 双端构建
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'platform=macOS'

xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination 'generic/platform=iOS'
```

最终验证结果：

- `CanvasEditHandleVisualStyleTests`：新增 3 个测试通过。
- `CanvasEditHandleInteractionStateTests`：14 个测试通过。
- `CanvasEditHandleIdentityPipelineTests`：9 个测试通过。
- 合计 26 个相关测试通过，`TEST SUCCEEDED`。
- macOS build：`BUILD SUCCEEDED`。
- iOS build：`BUILD SUCCEEDED`。
- 本阶段 4 个相关文件的 IDE lint：无错误。
- 构建输出中没有本阶段文件产生的 warning/error。
- `git diff --check`：通过。

## 本阶段未改变的行为

- 没有修改 handle identity、pointer pressed/dragging 状态机或 controller adapter。
- 没有修改 hit testing、pointer 4pt activation threshold、resize/crop/rotate/arrow/group 几何。
- 没有修改 history、autosave、文档格式或持久化模型。
- 没有修改 layer 的尺寸、形状、line width、隐藏逻辑和 contents scale。
- 没有增加 hover、disabled 或其他额外视觉状态。
