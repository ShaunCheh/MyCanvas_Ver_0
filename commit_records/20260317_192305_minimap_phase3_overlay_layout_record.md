# 20260317_192305_minimap_phase3_overlay_layout_record

## 记录范围

- 记录内容：
  1. 新增 `CanvasMiniMapLayout.swift`，提供 minimap 位置/大小配置与避让求解逻辑。
  2. 新增 iOS/macOS 的 `chrome overlay` 基础视图，保证空白区域事件透传。
  3. 改造 iOS/macOS controller，把右下角散落按钮收进统一 `controlsStackView`，并增加 `miniMapMountView` 作为后续 minimap 的挂载位。
  4. 在两个平台的 `viewDidLayout` 链路中接入 minimap 预留 frame 的动态计算。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
  - `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`
- 本记录不包含：
  - minimap 的实际绘制视图
  - minimap snapshot / renderer 的数据接线
  - 原始 gif diff
  - git commit / push

## 修改一：新增共享 minimap 布局求解器

### 修改前

- 工程里还没有 minimap 的位置/大小配置模型。
- 也没有统一的“避让已有 chrome”的布局求解器。
- 如果直接在 controller 里手写常量约束，后续无法统一处理：
  - `bottomLeading / bottomTrailing / topLeading / topTrailing`
  - 首选大小与最小尺寸
  - 和按钮栈的动态避让

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift
// 函数名/类型名: 无
// 功能说明: 修改前工程中不存在 minimap 布局配置与共享避让求解器文件。
// 无对应实现
```

### 修改后

- 新增 `CanvasMiniMapAnchor`、`CanvasMiniMapConfiguration`、`CanvasOverlayLayoutSolver`。
- `CanvasMiniMapConfiguration` 先提供代码层配置入口：
  - `preferredAnchor`
  - `preferredSize`
  - `edgeInset`
  - `chromeClearance`
  - `minimumAllowedSize`
- `CanvasOverlayLayoutSolver.resolveMiniMapFrame(...)` 负责：
  - 基于 `safeBounds` 和 `occupiedRects` 求解 minimap frame
  - 先尝试首选角，再按镜像角 fallback
  - 优先移动，必要时缩小尺寸
  - 保证结果落在安全区域内且不与 blocker rect 相交

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Core/CanvasMiniMapLayout.swift
// 函数名: CanvasMiniMapAnchor / CanvasMiniMapConfiguration / resolveMiniMapFrame(safeBounds:occupiedRects:configuration:)
// 功能说明: 新增 minimap 共享布局求解器，统一处理首选角、大小缩放、安全边距以及对现有按钮区域的避让。
enum CanvasMiniMapAnchor {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
}

struct CanvasMiniMapConfiguration {
    var preferredAnchor: CanvasMiniMapAnchor = .bottomLeading
    var preferredSize: CGSize = CGSize(width: 180, height: 132)
    var edgeInset: CGFloat = 16
    var chromeClearance: CGFloat = 12
    var minimumAllowedSize: CGSize = CGSize(width: 120, height: 88)
}

struct CanvasOverlayLayoutSolver {
    func resolveMiniMapFrame(
        safeBounds: CGRect,
        occupiedRects: [CGRect],
        configuration: CanvasMiniMapConfiguration
    ) -> CGRect? {
        // 先算安全布局区域，再尝试不同 anchor 和 size 组合，
        // 最终返回一个既不越界也不与 blocker 相交的 minimap frame。
    }
}
```

## 修改二：新增 iOS/macOS 的 chrome overlay 基础视图

### 修改前

- 两个平台都没有“只负责承载 chrome 且空白区域可透传”的 overlay view。
- 如果后续 minimap 直接挂在普通容器上，空白区域很容易截走主画板手势。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名/类型名: 无
// 功能说明: 修改前 iOS 平台没有 minimap/chrome 专用 overlay view。
// 无对应实现
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 函数名/类型名: 无
// 功能说明: 修改前 macOS 平台没有 minimap/chrome 专用 overlay view。
// 无对应实现
```

### 修改后

- 新增 `iOSCanvasChromeOverlayView` / `macOSCanvasChromeOverlayView`。
- 这两个视图都在 `hitTest(...)` 里把“命中自己本体”的情况转成 `nil`，让空白区域继续透传到底下的主画板。
- 同时新增 `iOSCanvasChromeStackView` / `macOSCanvasChromeStackView`，让按钮 stack 本身也能做到“只让真实子控件吃事件”。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名: hitTest(_:with:)
// 功能说明: iOS overlay 空白区域直接返回 nil，避免 chrome 容器本身拦截主画板触摸。
final class iOSCanvasChromeOverlayView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}

final class iOSCanvasChromeStackView: UIStackView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        return hitView === self ? nil : hitView
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasChromeOverlayView.swift
// 函数名: hitTest(_:)
// 功能说明: macOS overlay 空白区域同样透传，只让真实子视图接收鼠标事件。
final class macOSCanvasChromeOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

final class macOSCanvasChromeStackView: NSStackView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}
```

## 修改三：iOS controller 从“散落按钮”改为 “canvasHost + chromeOverlay + controlsStack”

### 修改前

- iOS 的按钮全部直接加到 controller 根 view。
- 约束也是一组从右下角往上串联的静态约束。
- 这种结构会导致 minimap 没有一个正式的挂载层，也无法统一做按钮避让。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前按钮直接挂在根 view，并通过一组静态 trailing/bottom 约束堆叠到右下角。
private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(cropButton)
    view.addSubview(undoButton)
    view.addSubview(redoButton)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        cropButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        cropButton.bottomAnchor.constraint(equalTo: undoButton.topAnchor, constant: -12),
        undoButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        undoButton.bottomAnchor.constraint(equalTo: redoButton.topAnchor, constant: -12),
        redoButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        redoButton.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
        saveButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
        importButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        importButton.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
    ])
}
```

### 修改后

- iOS controller 新增：
  - `miniMapLayoutSolver`
  - `miniMapConfiguration`
  - `chromeOverlayView`
  - `controlsStackView`
  - `miniMapMountView`
- 视图层级改成：
  - `canvasHostView`
  - `chromeOverlayView`
  - `controlsStackView`
  - `miniMapMountView`
- 按钮统一进入 `controlsStackView`，后续 minimap 就可以把这个 stack 的 frame 当成 blocker rect。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: 属性区 / setupViewHierarchy()
// 功能说明: 修改后 iOS controller 引入 chrome overlay 和按钮 stack，并预留 miniMapMountView 作为 minimap 挂载位。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let chromeOverlayView: iOSCanvasChromeOverlayView = {
    let view = iOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()
private let controlsStackView: iOSCanvasChromeStackView = {
    let stackView = iOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.axis = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()
private let miniMapMountView: iOSCanvasChromeOverlayView = {
    let view = iOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()

private func setupViewHierarchy() {
    view.backgroundColor = .systemBackground
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(undoButton)
    controlsStackView.addArrangedSubview(redoButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}
```

## 修改四：macOS controller 做同构重构

### 修改前

- macOS controller 也是同样的问题：按钮直接挂在根 view，并用 trailing/bottom 常量约束固定在右下角。
- minimap 后续没有正式 chrome 宿主层，也不能把按钮区域抽象成统一 blocker。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: setupViewHierarchy() / setupConstraints()
// 功能说明: 修改前 macOS 平台同样采用散落按钮布局，右下角按钮链直接压在根 view 上。
private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(cropButton)
    view.addSubview(saveButton)
    view.addSubview(importButton)
}

private func setupConstraints() {
    NSLayoutConstraint.activate([
        cropButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        cropButton.bottomAnchor.constraint(equalTo: saveButton.topAnchor, constant: -12),
        saveButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        saveButton.bottomAnchor.constraint(equalTo: importButton.topAnchor, constant: -12),
        importButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        importButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
    ])
}
```

### 修改后

- macOS 也与 iOS 保持同构：
  - `chromeOverlayView`
  - `controlsStackView`
  - `miniMapMountView`
  - `miniMapLayoutSolver`
  - `miniMapConfiguration`
- 后续 minimap 平台视图接入时，两个平台可以直接复用同一套布局与避让规则。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: 属性区 / setupViewHierarchy()
// 功能说明: 修改后 macOS controller 也切到 chrome overlay 架构，按钮统一收进 stack，预留 minimap 挂载视图。
private let miniMapLayoutSolver = CanvasOverlayLayoutSolver()
var miniMapConfiguration = CanvasMiniMapConfiguration()
private let chromeOverlayView: macOSCanvasChromeOverlayView = {
    let view = macOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
}()
private let controlsStackView: macOSCanvasChromeStackView = {
    let stackView = macOSCanvasChromeStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.alignment = .trailing
    stackView.distribution = .fill
    stackView.spacing = 12
    return stackView
}()
private let miniMapMountView: macOSCanvasChromeOverlayView = {
    let view = macOSCanvasChromeOverlayView()
    view.translatesAutoresizingMaskIntoConstraints = true
    view.isHidden = true
    return view
}()

private func setupViewHierarchy() {
    view.addSubview(canvasHostView)
    view.addSubview(chromeOverlayView)
    chromeOverlayView.addSubview(miniMapMountView)
    chromeOverlayView.addSubview(controlsStackView)
    controlsStackView.addArrangedSubview(cropButton)
    controlsStackView.addArrangedSubview(saveButton)
    controlsStackView.addArrangedSubview(importButton)
}
```

## 修改五：在 layout 生命周期里接入 minimap 预留 frame 计算

### 修改前

- 两个平台的 layout 生命周期只负责同步 viewport size。
- 没有任何 minimap 预留 frame 的计算函数。
- 因此即使后面把 minimap view 建出来，也没有“在哪里显示”的统一入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: viewDidLayoutSubviews()
// 功能说明: 修改前 iOS layout 链路只做 viewport size 同步，不参与 minimap chrome 布局。
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncCameraViewportSizeIfNeeded(
        canvasViewportView.bounds.size,
        source: "controller layout fallback"
    )
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: viewDidLayout()
// 功能说明: 修改前 macOS layout 链路同样只更新相机 viewport 尺寸。
override func viewDidLayout() {
    super.viewDidLayout()
    updateCameraViewportSizeIfNeeded()
}
```

### 修改后

- iOS/macOS 都新增：
  - `updateChromeOverlayLayout()`
  - `chromeSafeBounds()`
  - `chromeOccupiedRects()`
- 在 `viewDidLayoutSubviews()` / `viewDidLayout()` 中调用 `updateChromeOverlayLayout()`。
- 当前这一步虽然还没有真正显示 minimap，但已经能稳定算出一个和按钮 stack 不重叠的 `miniMapMountView.frame`。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名: viewDidLayoutSubviews() / updateChromeOverlayLayout() / chromeSafeBounds() / chromeOccupiedRects()
// 功能说明: iOS 平台在 layout 阶段实时计算 minimap 预留 frame，并把 controlsStackView 当成 blocker rect 参与避让。
override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    syncCameraViewportSizeIfNeeded(
        canvasViewportView.bounds.size,
        source: "controller layout fallback"
    )
    updateChromeOverlayLayout()
}

private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名: viewDidLayout() / updateChromeOverlayLayout() / chromeSafeBounds() / chromeOccupiedRects()
// 功能说明: macOS 平台采用同构逻辑，在窗口布局变化时同步更新 minimap 预留 frame。
override func viewDidLayout() {
    super.viewDidLayout()
    updateCameraViewportSizeIfNeeded()
    updateChromeOverlayLayout()
}

private func updateChromeOverlayLayout() {
    let safeBounds = chromeSafeBounds()
    let occupiedRects = chromeOccupiedRects()
    let miniMapFrame = miniMapLayoutSolver.resolveMiniMapFrame(
        safeBounds: safeBounds,
        occupiedRects: occupiedRects,
        configuration: miniMapConfiguration
    )?.integral ?? .zero
    if miniMapMountView.frame != miniMapFrame {
        miniMapMountView.frame = miniMapFrame
    }
}
```

## 结果与影响

- 本次修改完成了 minimap `Phase 3` 的布局基础设施：
  - 已有共享的 minimap 布局求解器
  - 已有跨平台一致的 chrome overlay 架构
  - 已有按钮 stack 的 blocker rect 提供者
  - 已有 minimap 的挂载位 `miniMapMountView`
- 这意味着后续 `Phase 4` 只需要把 minimap 视图本体挂进 `miniMapMountView`，就能直接享受现成的避让布局和事件透传能力。
- 当前仍然不会显示 minimap，这是预期行为；因为本阶段只处理布局层和 chrome 宿主，不处理 minimap 绘制。

## 校验情况

- `ReadLints` 已检查 `CanvasMiniMapLayout.swift`、两个 chrome overlay 文件、以及 iOS/macOS controller，未发现新增诊断。
- 本次改动范围集中在 Core 布局求解器和平台 controller / chrome 容器，没有动 minimap 绘制与交互逻辑。
