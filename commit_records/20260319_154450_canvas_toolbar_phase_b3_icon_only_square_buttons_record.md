# 20260319_154450_canvas_toolbar_phase_b3_icon_only_square_buttons_record

## 记录范围

- 记录目标：归档 `Canvas` 工具栏演进 `阶段B-阶段3` 的实际代码变更。
- 本次实际产物：
- 主工具栏宿主开始统一约束 `Crop / Save / +` 三按钮为 `44x44` 正方形。
- `iOS` 侧新增统一的主工具栏 icon-only 样式入口，`Crop / Save / +` 不再显示可见文字。
- `macOS` 侧新增统一的主工具栏 icon-only 样式入口，`Crop / Save / +` 不再显示可见文字。
- `Save` 与 `Crop` 仍保留状态语义，但改由图标、颜色、`accessibility` / `toolTip` 表达。
- 本次未执行：
- 未实现 `B4` 的四边停靠约束切换。
- 未把 `history` 组宿主化。
- 未执行 git commit。

## 本次变更文件

- 修改：`MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift`
- 修改：`MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift`
- 修改：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

## 修改前（B2完成后）

- `ToolbarHostView` 已经存在，但它只负责背景、内边距、阴影和横竖排布切换，还没有统一主工具栏按钮的方形尺寸。
- `Crop / Save / +` 的尺寸仍部分依赖控制器里的旧高度约束。
- `iOS` 的 `Save` 和 `Crop` 仍通过 `configuration.title` 显示文字。
- `macOS` 的 `Save` 和 `Crop` 仍通过 `button.title` 显示文字。
- 也就是说，`B2` 完成后已经有宿主外壳，但还没有真正完成“主工具栏按钮统一成 icon-only 正方形”的目标。

### iOS 宿主修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: iOSCanvasToolbarHostView.installButtons(_:) / updateDockEdgeLayout()
// 功能说明: B3 修改前，iOS 宿主只负责容器外壳和横竖排布，不负责把主工具栏按钮统一成固定正方形尺寸。
final class iOSCanvasToolbarHostView: UIView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    func installButtons(_ buttons: [UIButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
        }
    }

    private func updateDockEdgeLayout() {
        buttonsStackView.axis = dockEdge.prefersHorizontalButtonLayout
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
            ? .center
            : .trailing
    }
}
```

### macOS 宿主修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: macOSCanvasToolbarHostView.installButtons(_:) / updateDockEdgeLayout()
// 功能说明: B3 修改前，macOS 宿主同样只承接外壳与排布，不会主动统一主工具栏按钮的宽高。
final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    func installButtons(_ buttons: [NSButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
        }
    }

    private func updateDockEdgeLayout() {
        buttonsStackView.orientation = dockEdge.prefersHorizontalButtonLayout
            ? .horizontal
            : .vertical
        buttonsStackView.alignment = dockEdge.prefersHorizontalButtonLayout
            ? .centerY
            : .trailing
    }
}
```

### iOS 控制器修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.setupImportButton() / setupSaveButton() / applySaveButtonAppearance(...) / applyCropButtonAppearance(...)
// 功能说明: B3 修改前，iOS 主工具栏按钮还没有统一 icon-only 入口，Save/Crop 继续依赖 title 和旧高度约束表达状态。
private func setupImportButton() {
    importButton.addTarget(self, action: #selector(handleImportButtonTap), for: .touchUpInside)
}

private func setupSaveButton() {
    saveButton.addTarget(self, action: #selector(handleSaveButtonTap), for: .touchUpInside)
}

private func applySaveButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor
) {
    var configuration = saveButton.configuration ?? UIButton.Configuration.filled()
    configuration.title = title
    configuration.image = UIImage(systemName: systemImageName)
    configuration.baseBackgroundColor = backgroundColor
    saveButton.configuration = configuration
}

private func applyCropButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor,
    isEnabled: Bool
) {
    cropButton.isEnabled = isEnabled
    var configuration = cropButton.configuration ?? UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
    configuration.imagePlacement = .leading
    configuration.imagePadding = 6
    configuration.cornerStyle = .capsule
    configuration.baseForegroundColor = .white
    configuration.title = title
    configuration.image = UIImage(systemName: systemImageName)
    configuration.baseBackgroundColor = isEnabled ? backgroundColor : .systemGray3
    cropButton.configuration = configuration
}
```

### macOS 控制器修改前代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.setupImportButton() / setupSaveButton() / applySaveButtonAppearance(...) / applyCropButtonAppearance(...)
// 功能说明: B3 修改前，macOS 主工具栏按钮也还没有统一的 icon-only 外观入口，Save/Crop 仍通过 button.title 呈现文字语义。
private func setupImportButton() {
    importButton.target = self
    importButton.action = #selector(handleImportButtonClick)
}

private func setupSaveButton() {
    saveButton.target = self
    saveButton.action = #selector(handleSaveButtonClick)
}

private func applySaveButtonAppearance(
    title: String,
    systemImageName: String,
    tintColor: NSColor
) {
    saveButton.title = title
    saveButton.image = NSImage(
        systemSymbolName: systemImageName,
        accessibilityDescription: title
    )
    saveButton.contentTintColor = tintColor
}

private func applyCropButtonAppearance(
    title: String,
    systemImageName: String,
    tintColor: NSColor,
    isEnabled: Bool
) {
    cropButton.title = title
    cropButton.image = NSImage(
        systemSymbolName: systemImageName,
        accessibilityDescription: title
    )
    cropButton.contentTintColor = isEnabled ? tintColor : .secondaryLabelColor
    cropButton.isEnabled = isEnabled
}
```

## 修改后（B3完成后）

- `ToolbarHostView` 现在会在安装主工具栏按钮时统一补上 `44x44` 尺寸约束，尺寸责任从控制器下沉到宿主。
- `iOS` 新增 `applyToolbarIconButtonAppearance(...)`，统一主工具栏 icon-only 外观，`Crop / Save / +` 都走同一套入口。
- `macOS` 新增 `applyToolbarIconButtonAppearance(...)`，统一主工具栏 icon-only 外观，`Crop / Save / +` 都走同一套入口。
- `Save` 的临时状态文案不再显示为可见标题，而是改成：
- `iOS` 用 `accessibilityValue`
- `macOS` 用 `toolTip` / `accessibilityDescription`
- 控制器里的旧主工具栏按钮高度约束被移除，`history` 组尺寸约束保持原样。

### iOS 宿主修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasToolbarHostView.swift
// 函数名/类型名: iOSCanvasToolbarHostView.installButtons(_:) / ensureSquareSize(for:)
// 功能说明: B3 之后，iOS 宿主在安装主工具栏按钮时主动补充 44x44 正方形约束，把尺寸责任从控制器迁到宿主。
final class iOSCanvasToolbarHostView: UIView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let buttonEdge: CGFloat = 44
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    func installButtons(_ buttons: [UIButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
            ensureSquareSize(for: button)
        }
    }

    private func ensureSquareSize(for button: UIButton) {
        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: Layout.buttonEdge)
            widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
            widthConstraint.isActive = true
        }

        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
            let heightConstraint = button.heightAnchor.constraint(equalToConstant: Layout.buttonEdge)
            heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
            heightConstraint.isActive = true
        }
    }
}
```

### macOS 宿主修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasToolbarHostView.swift
// 函数名/类型名: macOSCanvasToolbarHostView.installButtons(_:) / ensureSquareSize(for:)
// 功能说明: B3 之后，macOS 宿主同样会为主工具栏按钮统一补充 44x44 正方形约束，避免按钮尺寸继续散落在控制器中维护。
final class macOSCanvasToolbarHostView: NSView {
    private enum Layout {
        static let spacing: CGFloat = 12
        static let horizontalInset: CGFloat = 12
        static let verticalInset: CGFloat = 12
        static let buttonEdge: CGFloat = 44
        static let cornerRadius: CGFloat = 18
        static let shadowOpacity: Float = 0.12
        static let shadowRadius: CGFloat = 10
        static let shadowOffset = CGSize(width: 0, height: 4)
    }

    func installButtons(_ buttons: [NSButton]) {
        buttons.forEach { button in
            guard button.superview !== buttonsStackView else {
                return
            }

            button.removeFromSuperview()
            buttonsStackView.addArrangedSubview(button)
            ensureSquareSize(for: button)
        }
    }

    private func ensureSquareSize(for button: NSButton) {
        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonWidth" }) == false {
            let widthConstraint = button.widthAnchor.constraint(equalToConstant: Layout.buttonEdge)
            widthConstraint.identifier = "canvasToolbarHost.buttonWidth"
            widthConstraint.isActive = true
        }

        if button.constraints.contains(where: { $0.identifier == "canvasToolbarHost.buttonHeight" }) == false {
            let heightConstraint = button.heightAnchor.constraint(equalToConstant: Layout.buttonEdge)
            heightConstraint.identifier = "canvasToolbarHost.buttonHeight"
            heightConstraint.isActive = true
        }
    }
}
```

### iOS 控制器修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数名/类型名: iOSViewController.setupImportButton() / setupSaveButton() / applyImportButtonAppearance() / applyToolbarIconButtonAppearance(...) / applySaveButtonAppearance(...) / applyCropButtonAppearance(...)
// 功能说明: B3 之后，iOS 主工具栏三按钮统一走 icon-only 样式入口，Save/Crop 的语义通过图标、颜色和 accessibilityValue 表达。
private func setupImportButton() {
    importButton.addTarget(self, action: #selector(handleImportButtonTap), for: .touchUpInside)
    applyImportButtonAppearance()
}

private func setupSaveButton() {
    saveButton.addTarget(self, action: #selector(handleSaveButtonTap), for: .touchUpInside)
    applyDefaultSaveButtonAppearance()
}

private func applyImportButtonAppearance() {
    applyToolbarIconButtonAppearance(
        to: importButton,
        systemImageName: "plus",
        backgroundColor: .systemBlue,
        accessibilityLabel: "Import image",
        symbolPointSize: 20,
        symbolWeight: .bold
    )
}

private func applyToolbarIconButtonAppearance(
    to button: UIButton,
    systemImageName: String,
    backgroundColor: UIColor,
    accessibilityLabel: String,
    accessibilityValue: String? = nil,
    symbolPointSize: CGFloat = 17,
    symbolWeight: UIImage.SymbolWeight = .semibold,
    isEnabled: Bool = true
) {
    button.isEnabled = isEnabled
    var configuration = button.configuration ?? UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: symbolPointSize,
        weight: symbolWeight
    )
    configuration.image = UIImage(systemName: systemImageName)
    configuration.title = nil
    configuration.imagePadding = 0
    configuration.baseBackgroundColor = backgroundColor
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    button.configuration = configuration
    button.accessibilityLabel = accessibilityLabel
    button.accessibilityValue = accessibilityValue
}

private func applySaveButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor
) {
    applyToolbarIconButtonAppearance(
        to: saveButton,
        systemImageName: systemImageName,
        backgroundColor: backgroundColor,
        accessibilityLabel: "Save board",
        accessibilityValue: title == "Save" ? nil : title,
        isEnabled: saveButton.isEnabled
    )
}

private func applyCropButtonAppearance(
    title: String,
    systemImageName: String,
    backgroundColor: UIColor,
    isEnabled: Bool
) {
    applyToolbarIconButtonAppearance(
        to: cropButton,
        systemImageName: systemImageName,
        backgroundColor: isEnabled ? backgroundColor : .systemGray3,
        accessibilityLabel: title == "Done" ? "Done cropping" : "Crop",
        isEnabled: isEnabled
    )
}
```

### macOS 控制器修改后代码快照

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 函数名/类型名: macOSViewController.setupImportButton() / setupSaveButton() / applyImportButtonAppearance() / applyToolbarIconButtonAppearance(...) / applySaveButtonAppearance(...) / applyCropButtonAppearance(...)
// 功能说明: B3 之后，macOS 主工具栏三按钮统一走 icon-only 样式入口，Save/Crop 的语义通过图标、颜色和 toolTip/accessibilityDescription 表达。
private func setupImportButton() {
    importButton.target = self
    importButton.action = #selector(handleImportButtonClick)
    applyImportButtonAppearance()
}

private func setupSaveButton() {
    saveButton.target = self
    saveButton.action = #selector(handleSaveButtonClick)
    applyDefaultSaveButtonAppearance()
}

private func applyImportButtonAppearance() {
    applyToolbarIconButtonAppearance(
        to: importButton,
        systemImageName: "plus",
        backgroundColor: .systemBlue,
        foregroundColor: .white,
        accessibilityDescription: "Import image",
        isEnabled: true
    )
}

private func applyToolbarIconButtonAppearance(
    to button: NSButton,
    systemImageName: String,
    backgroundColor: NSColor,
    foregroundColor: NSColor,
    accessibilityDescription: String,
    isEnabled: Bool
) {
    button.title = ""
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.wantsLayer = true
    button.layer?.cornerRadius = 12
    button.layer?.borderWidth = 1
    button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.24).cgColor
    button.layer?.backgroundColor = backgroundColor.cgColor
    button.contentTintColor = foregroundColor
    button.toolTip = accessibilityDescription
    button.image = NSImage(
        systemSymbolName: systemImageName,
        accessibilityDescription: accessibilityDescription
    )
    button.isEnabled = isEnabled
}

private func applySaveButtonAppearance(
    title: String,
    systemImageName: String,
    tintColor: NSColor
) {
    let accessibilityDescription = title == "Save"
        ? "Save board"
        : "Save board (\(title))"
    applyToolbarIconButtonAppearance(
        to: saveButton,
        systemImageName: systemImageName,
        backgroundColor: tintColor,
        foregroundColor: .white,
        accessibilityDescription: accessibilityDescription,
        isEnabled: saveButton.isEnabled
    )
}

private func applyCropButtonAppearance(
    title: String,
    systemImageName: String,
    tintColor: NSColor,
    isEnabled: Bool
) {
    applyToolbarIconButtonAppearance(
        to: cropButton,
        systemImageName: systemImageName,
        backgroundColor: isEnabled ? tintColor : .quaternaryLabelColor.withAlphaComponent(0.35),
        foregroundColor: isEnabled ? .white : .secondaryLabelColor,
        accessibilityDescription: title == "Done" ? "Done cropping" : "Crop",
        isEnabled: isEnabled
    )
}
```

## 阶段B3完成情况

- 已完成：主工具栏按钮在 `iOS/macOS` 两端统一为 `44x44` 正方形。
- 已完成：`Crop / Save / +` 两端统一收口为 icon-only 主工具栏按钮。
- 已完成：`Save` 与 `Crop` 的状态语义从可见标题转移到图标、颜色和辅助语义。
- 已完成：主工具栏旧尺寸约束从控制器中移除。
- 未完成：四边停靠约束切换。
- 未完成：history 组外壳化和统一视觉收口。

## 验证命令

```bash
# 文件路径: 系统命令（无对应仓库文件）
# 函数名/类型名: date / xcodebuild
# 功能说明: 使用系统时间生成 B3 记录文件名，并对 B3 的主工具栏 icon-only 正方形按钮改动执行双端构建验证。
date +"%Y%m%d_%H%M%S"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS" \
  -derivedDataPath "/tmp/MyCanvas_B3_iOS_DerivedData" \
  build

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer" xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath "/tmp/MyCanvas_B3_macOS_DerivedData" \
  build
```

## 验证结果

- `date` 返回时间戳：`20260319_154450`
- `iOS Debug` 构建通过。
- `macOS Debug` 构建通过。
- 本次修改文件 `ReadLints` 无报错。

## 结论

- `B3` 已经把“主工具栏按钮像按钮组，但还残留旧文本/旧尺寸逻辑”的状态推进到“真正的 icon-only 正方形主工具栏按钮”。
- 到这一阶段为止，`Crop / Save / +` 的承载层、尺寸层、样式层都已经收口到工具栏链路中，下一步 `B4` 就可以专注处理四边停靠和布局切换，而不需要再返工按钮本体。
