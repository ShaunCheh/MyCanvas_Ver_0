# 20260319_113822_boardlist_placeholder_grid_outer_shell_center_record

## 记录范围

- 记录目标：修正 `BoardList` 中 `New Board` 占位项在 `Grid` 模式下的视觉结构，不再显示内部 `previewView` 空壳。
- 本次目的 1：去掉 `Grid` 占位项中间那块浅色 `previewView` 区域。
- 本次目的 2：把 `+` 图标改为相对外层灰色卡片居中，而不是相对 `previewView` 居中。
- 本次目的 3：保留 `New Board` 标题在卡片底部，不影响 `List` 模式样式。
- 涉及文件：`MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 涉及文件：`MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 本记录不包含：阶段 3 原始 placeholder 样式设计。
- 本记录不包含：git commit。

## 修改一：macOS Grid 占位项不再复用 `previewView`

### 修改前

- macOS 的 `placeholderGrid` 仍然沿用 `previewView` 作为内部壳层。
- `+` 图标锚定在 `previewView.centerX / centerY`。
- `placeholderGrid` 展示时继续激活 `gridConstraints + placeholderGridIconConstraints`，所以视觉上会看到外层灰色卡片里还有一块浅色矩形。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.setupConstraints() / applyPresentationStyle(_:)
// 功能说明: 修改前 macOS 的 Grid 占位项仍以 previewView 为核心容器，+ 图标只是叠加在 previewView 中心，因此会保留中间浅色矩形壳层。
private var placeholderGridIconConstraints: [NSLayoutConstraint] = []

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
    ]

    placeholderGridIconConstraints = [
        placeholderIconView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
        placeholderIconView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
        placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
        placeholderIconView.heightAnchor.constraint(equalToConstant: 22)
    ]
}

private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
    NSLayoutConstraint.deactivate(
        gridConstraints +
            listConstraints +
            placeholderGridIconConstraints +
            placeholderListConstraints
    )

    previewView.isHidden = false
    placeholderIconView.isHidden = true

    switch presentationStyle {
    case .placeholderGrid:
        titleLabel.alignment = .center
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(gridConstraints + placeholderGridIconConstraints)
    default:
        break
    }
}
```

### 修改后

- macOS 把 `placeholderGridIconConstraints` 升级为 `placeholderGridConstraints`。
- `+` 图标改成锚定到整个 `view` 的中心。
- `titleLabel` 直接锚到底部。
- `placeholderGrid` 展示时显式 `previewView.isHidden = true`，因此 Grid 占位项只剩外层灰色卡片本体。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名/类型名: macOSBoardCollectionItem.setupConstraints() / applyPresentationStyle(_:)
// 功能说明: 修改后 macOS 的 Grid 占位项不再显示 previewView，+ 图标改为在外层卡片中心，标题单独挂在卡片底部。
private var placeholderGridConstraints: [NSLayoutConstraint] = []

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
    ]

    placeholderGridConstraints = [
        placeholderIconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        placeholderIconView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
        placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
        titleLabel.topAnchor.constraint(greaterThanOrEqualTo: placeholderIconView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
    ]
}

private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
    NSLayoutConstraint.deactivate(
        gridConstraints +
            listConstraints +
            placeholderGridConstraints +
            placeholderListConstraints
    )

    previewView.isHidden = false
    placeholderIconView.isHidden = true

    switch presentationStyle {
    case .placeholderGrid:
        titleLabel.alignment = .center
        previewView.isHidden = true
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(placeholderGridConstraints)
    default:
        break
    }
}
```

## 修改二：iOS Grid 占位项同步切到“外层卡片居中”语义

### 修改前

- iOS 与 macOS 对称，`placeholderGrid` 也是把 `+` 图标挂在 `previewView` 中间。
- 由于 `previewView` 没有隐藏，所以 `Grid` 模式下仍会保留中间浅色矩形区域。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.setupConstraints() / applyPresentationStyle(_:)
// 功能说明: 修改前 iOS 的 Grid 占位项同样以 previewView 为中心容器，视觉上仍会出现内部浅色预览壳。
private var placeholderGridIconConstraints: [NSLayoutConstraint] = []

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
    ]

    placeholderGridIconConstraints = [
        placeholderIconView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
        placeholderIconView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
        placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
        placeholderIconView.heightAnchor.constraint(equalToConstant: 22)
    ]
}

private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
    NSLayoutConstraint.deactivate(
        gridConstraints +
            listConstraints +
            placeholderGridIconConstraints +
            placeholderListConstraints
    )

    previewView.isHidden = false
    placeholderIconView.isHidden = true

    switch presentationStyle {
    case .placeholderGrid:
        titleLabel.textAlignment = .center
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(gridConstraints + placeholderGridIconConstraints)
    default:
        break
    }
}
```

### 修改后

- iOS 侧同步改成 `placeholderGridConstraints`。
- `+` 图标相对整个 `contentView` 居中。
- `titleLabel` 直接约束在卡片底部。
- `placeholderGrid` 展示时隐藏 `previewView`，与 macOS 保持同一语义。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名/类型名: iOSBoardCollectionViewCell.setupConstraints() / applyPresentationStyle(_:)
// 功能说明: 修改后 iOS 的 Grid 占位项也不再显示 previewView，+ 图标改为在外层灰色卡片中心，双端视觉结构保持一致。
private var placeholderGridConstraints: [NSLayoutConstraint] = []

private func setupConstraints() {
    gridConstraints = [
        previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
        previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        previewView.heightAnchor.constraint(equalToConstant: 120),
        titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
    ]

    placeholderGridConstraints = [
        placeholderIconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
        placeholderIconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        placeholderIconView.widthAnchor.constraint(equalToConstant: 22),
        placeholderIconView.heightAnchor.constraint(equalToConstant: 22),
        titleLabel.topAnchor.constraint(greaterThanOrEqualTo: placeholderIconView.bottomAnchor, constant: 10),
        titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
    ]
}

private func applyPresentationStyle(_ presentationStyle: PresentationStyle) {
    NSLayoutConstraint.deactivate(
        gridConstraints +
            listConstraints +
            placeholderGridConstraints +
            placeholderListConstraints
    )

    previewView.isHidden = false
    placeholderIconView.isHidden = true

    switch presentationStyle {
    case .placeholderGrid:
        titleLabel.textAlignment = .center
        previewView.isHidden = true
        placeholderIconView.isHidden = false
        NSLayoutConstraint.activate(placeholderGridConstraints)
    default:
        break
    }
}
```

## 验证结果

- 已检查文件：
- `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
- 已对照本次 `git diff`，确认记录内容覆盖：
- `placeholderGridIconConstraints` -> `placeholderGridConstraints`
- `+` 图标从 `previewView` 中心改为外层卡片中心
- `previewView.isHidden = true` 接入 `placeholderGrid`
- `titleLabel` 改为独立约束到卡片底部
- 本次相关文件的 lint 检查结果：无新增错误。
- 本次未执行项目级编译；因此这里的验证范围以 diff 对照和 lint 为主。
