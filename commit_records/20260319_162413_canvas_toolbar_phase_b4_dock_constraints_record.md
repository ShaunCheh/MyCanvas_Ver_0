# 20260319_162413_canvas_toolbar_phase_b4_dock_constraints_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段B-阶段4` 的实际代码变更。
- 本次实际产物：
- `iOS` 主工具栏从固定右下角约束切换为按 `CanvasToolbarDockEdge` 生成的四边停靠约束组。
- `macOS` 主工具栏从固定右下角约束切换为按 `CanvasToolbarDockEdge` 生成的四边停靠约束组。
- `iOS` 的 `historyButtonsStackView` 不再依附 `toolbarHostView`，改为独立固定在右下角，继续作为单独 blocker 参与 overlay 避让。
- `toolbarDockEdge` 变化时会同步刷新：
- `toolbarHostView` 的横竖排布方向
- 主工具栏停靠约束组
- overlay 占位布局
- 本次未执行：
- 未实现用户拖拽调整停靠位置。
- 未实现停靠位置持久化。
- 未执行 git commit。

## 本次变更文件

- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前（B3完成后）

- `iOS` 与 `macOS` 虽然已经有 `toolbarDockEdge`，但它只影响 `toolbarHostView` 内部按钮的横竖排布方向。
- 主工具栏整体位置仍然由固定的右下角约束决定，并不会随着 `toolbarDockEdge` 的值切换到上、下、左、右边。
- `iOS` 的 `historyButtonsStackView` 仍然通过 `bottomAnchor == toolbarHostView.topAnchor - 12` 依附在主工具栏上方，因此主工具栏一旦需要切边，history 组就会被一并牵连。

### iOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.setupConstraints() / updatePreparedToolbarDockEdge()
// 功能说明: B4 修改前，iOS 主工具栏整体位置仍然固定在右下角，toolbarDockEdge 只切换 host 内部按钮方向，不切换主工具栏停靠边。
private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略与本次 B4 无关的约束
        toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        historyButtonsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        historyButtonsStackView.bottomAnchor.constraint(equalTo: toolbarHostView.topAnchor, constant: -12),
        undoButton.heightAnchor.constraint(equalToConstant: 40),
        redoButton.heightAnchor.constraint(equalToConstant: 40)
    ])
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
}
```

### macOS 修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.setupConstraints() / updatePreparedToolbarDockEdge()
// 功能说明: B4 修改前，macOS 主工具栏同样始终固定在右下角，toolbarDockEdge 只改变 host 内部按钮排布，不改变工具栏在画布边缘的停靠位置。
private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略与本次 B4 无关的约束
        toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20)
    ])
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
}
```

## 修改后（B4完成后）

- `iOS` 与 `macOS` 都新增 `toolbarDockConstraints`，用于持有当前激活的主工具栏停靠约束组。
- `updatePreparedToolbarDockEdge()` 不再只转发 `dockEdge` 给 host，而是进一步：
- 先清理旧停靠约束
- 按当前 edge 生成新约束组
- 激活新约束
- 强制一次布局
- 立即刷新 `updateChromeOverlayLayout()`，让 minimap / context menu 看到新的 blocker frame
- `iOS` 新增 `makeToolbarDockConstraints(in:)`，明确把 `top / bottom / leading / trailing` 映射为四组“边中停靠”约束。
- `macOS` 新增对应的 `makeToolbarDockConstraints(in:)`，逻辑与 `iOS` 对齐。
- `iOS` 的 `historyButtonsStackView` 改为独立固定在右下角，不再依附主工具栏上方，从而避免主工具栏换边时 history 组跟着错误偏移。

### iOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.toolbarDockConstraints / setupConstraints() / updatePreparedToolbarDockEdge() / makeToolbarDockConstraints(in:)
// 功能说明: B4 之后，iOS 主工具栏停靠位置由约束组切换驱动；dock edge 一旦变化，会同步重建约束并刷新 overlay 占位布局。
private var toolbarDockConstraints: [NSLayoutConstraint] = []

private func setupConstraints() {
    let safeAreaLayoutGuide = chromeOverlayView.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        // ... 省略与本次 B4 无关的约束
        historyButtonsStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
        historyButtonsStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
        undoButton.heightAnchor.constraint(equalToConstant: 40),
        redoButton.heightAnchor.constraint(equalToConstant: 40)
    ])
}

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func makeToolbarDockConstraints(
    in safeAreaLayoutGuide: UILayoutGuide
) -> [NSLayoutConstraint] {
    switch toolbarDockEdge {
    case .top:
        [
            toolbarHostView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .bottom:
        [
            toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .leading:
        [
            toolbarHostView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    case .trailing:
        [
            toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    }
}
```

### macOS 修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.toolbarDockConstraints / updatePreparedToolbarDockEdge() / makeToolbarDockConstraints(in:)
// 功能说明: B4 之后，macOS 主工具栏同样通过四边停靠约束组切换位置，并在每次 edge 变化后立即刷新 overlay 占位链路。
private var toolbarDockConstraints: [NSLayoutConstraint] = []

private func updatePreparedToolbarDockEdge() {
    toolbarHostView.dockEdge = toolbarDockEdge
    NSLayoutConstraint.deactivate(toolbarDockConstraints)
    toolbarDockConstraints = makeToolbarDockConstraints(
        in: chromeOverlayView.safeAreaLayoutGuide
    )
    NSLayoutConstraint.activate(toolbarDockConstraints)
    if view.bounds.isEmpty == false {
        view.layoutSubtreeIfNeeded()
        updateChromeOverlayLayout()
    }
}

private func makeToolbarDockConstraints(
    in safeAreaLayoutGuide: NSLayoutGuide
) -> [NSLayoutConstraint] {
    switch toolbarDockEdge {
    case .top:
        [
            toolbarHostView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .bottom:
        [
            toolbarHostView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toolbarHostView.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor)
        ]
    case .leading:
        [
            toolbarHostView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    case .trailing:
        [
            toolbarHostView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -20),
            toolbarHostView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor)
        ]
    }
}
```

## 阶段B4完成情况

- 已完成：`iOS` 主工具栏四边停靠约束组切换。
- 已完成：`macOS` 主工具栏四边停靠约束组切换。
- 已完成：`toolbarDockEdge` 改动后同步刷新 host 朝向、约束组与 overlay 占位布局。
- 已完成：`iOS` history 组从 toolbar 相对约束中解耦，并继续作为独立 blocker 参与避让。
- 未完成：用户手动拖拽停靠。
- 未完成：停靠位置持久化。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 B4 记录文件名，并对 B4 的四边停靠约束切换实现执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_B4_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_B4_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_162413`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- `B4` 把主工具栏从“逻辑上支持 dock edge，但位置实际上仍固定”推进到了“真正按 edge 切换停靠边”的状态。
- 到这一阶段为止，阶段B里关于主工具栏的四个目标已经闭环：
- `B1` 固定结构边界
- `B2` 抽离宿主外壳
- `B3` 统一 icon-only 正方形按钮
- `B4` 接通四边停靠与 overlay 占位刷新链路
