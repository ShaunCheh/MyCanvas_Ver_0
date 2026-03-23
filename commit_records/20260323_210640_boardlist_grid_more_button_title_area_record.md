# 20260323_210640_boardlist_grid_more_button_title_area_record

## 记录范围

- 记录内容：
  1. 将 `BoardList` 的 `Grid` 视图三点“更多操作”按钮从缩略图区域右上角挪到标题区。
  2. 同步调整 `Grid` 模式标题对齐方式，为按钮预留标题尾部空间。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
  - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
- 本记录不包含：
  - `List` 模式布局变更
  - rename 提交流程变更
  - git commit / push

## 修改一：iOS Grid 卡片把三点按钮从缩略图右上角移到标题区

### 修改前

- `Grid` 模式里，`moreButton` 直接锚到 `contentView` 的右上角。
- 同一组约束里，`previewView` 也锚到 `contentView` 顶部并占据卡片上半部分，所以按钮视觉上落在缩略图区域里。
- `titleLabel` / `titleTextField` 在 `Grid` 模式里是居中对齐，标题尾部没有给按钮预留空间。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: setupConstraints()
// 功能说明: 修改前 iOS Grid 卡片把三点按钮钉在卡片右上角；由于缩略图同样占据顶部区域，按钮会覆盖在 preview 区域上。
gridConstraints = [
    previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
    previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    previewView.heightAnchor.constraint(equalToConstant: 120),
    moreButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
    moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    moreButton.widthAnchor.constraint(equalToConstant: 32),
    moreButton.heightAnchor.constraint(equalToConstant: 32),
    titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
    titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
    titleTextField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
    titleTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    titleTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleTextField.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
]
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: applyPresentationStyle(_:)
// 功能说明: 修改前 iOS Grid 标题保持居中显示，底部标题区没有为三点按钮预留 trailing 空间。
switch presentationStyle {
case .boardGrid:
    titleLabel.textAlignment = .center
    titleTextField.textAlignment = .center
    moreButton.isHidden = false
    NSLayoutConstraint.activate(gridConstraints)
case .boardList:
    titleLabel.textAlignment = .left
    titleTextField.textAlignment = .left
    moreButton.isHidden = false
    NSLayoutConstraint.activate(listConstraints)
// ...
}
```

### 修改后

- 移除 `moreButton.topAnchor == contentView.topAnchor` 的 Grid 锚点，改为让按钮和 `titleLabel` 处于同一标题行。
- `titleLabel.trailingAnchor` 改为连接到 `moreButton.leadingAnchor`，标题尾部会自动给按钮让位。
- `moreButton.centerYAnchor` 改为跟随 `titleLabel.centerYAnchor`，按钮位置落在缩略图下方的标题区。
- `Grid` 模式标题和内联编辑输入框都改为左对齐，与按钮同排后更稳定。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: setupConstraints()
// 功能说明: 修改后 iOS Grid 卡片把三点按钮移到标题区；按钮与标题同行，缩略图顶部区域不再被按钮覆盖。
gridConstraints = [
    previewView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
    previewView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    previewView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    previewView.heightAnchor.constraint(equalToConstant: 120),
    titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
    titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
    titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12),
    moreButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    moreButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    moreButton.widthAnchor.constraint(equalToConstant: 32),
    moreButton.heightAnchor.constraint(equalToConstant: 32),
    titleTextField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
    titleTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
    titleTextField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
    titleTextField.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -12)
]
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift
// 函数名: applyPresentationStyle(_:)
// 功能说明: 修改后 iOS Grid 标题改为左对齐，和三点按钮共享底部标题区。
switch presentationStyle {
case .boardGrid:
    titleLabel.textAlignment = .left
    titleTextField.textAlignment = .left
    moreButton.isHidden = false
    NSLayoutConstraint.activate(gridConstraints)
case .boardList:
    titleLabel.textAlignment = .left
    titleTextField.textAlignment = .left
    moreButton.isHidden = false
    NSLayoutConstraint.activate(listConstraints)
// ...
}
```

## 修改二：macOS Grid 卡片同步把三点按钮移到标题区

### 修改前

- `macOS` 侧的 `Grid` 约束和 `iOS` 对称，`moreButton` 直接锚在 `view` 的右上角。
- `previewView` 同样从 `view.topAnchor` 开始布局并占据上半区，因此按钮视觉上也压在缩略图内。
- `Grid` 模式标题使用居中对齐。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: setupConstraints()
// 功能说明: 修改前 macOS Grid 卡片同样把三点按钮放在卡片顶部右侧，因此按钮落在缩略图区域之内。
gridConstraints = [
    previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
    previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    previewView.heightAnchor.constraint(equalToConstant: 120),
    moreButton.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
    moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    moreButton.widthAnchor.constraint(equalToConstant: 32),
    moreButton.heightAnchor.constraint(equalToConstant: 32),
    titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
    titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
    titleTextField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
    titleTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    titleTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    titleTextField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
]
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: applyPresentationStyle(_:)
// 功能说明: 修改前 macOS Grid 标题居中展示，按钮没有被收纳到标题行中。
switch presentationStyle {
case .boardGrid:
    titleLabel.alignment = .center
    titleTextField.alignment = .center
    moreButton.isHidden = false
    NSLayoutConstraint.activate(gridConstraints)
case .boardList:
    titleLabel.alignment = .left
    titleTextField.alignment = .left
    moreButton.isHidden = false
    NSLayoutConstraint.activate(listConstraints)
// ...
}
```

### 修改后

- `Grid` 模式的三点按钮改为贴着标题行右侧布局。
- `titleLabel.trailingAnchor` 改接 `moreButton.leadingAnchor`，让标题内容和按钮共存于底部标题区。
- 按钮垂直位置跟随 `titleLabel.centerYAnchor`，不再覆盖缩略图。
- `Grid` 模式标题和标题输入框一并改成左对齐。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: setupConstraints()
// 功能说明: 修改后 macOS Grid 卡片把三点按钮移到了标题区右侧，缩略图顶部区域不再承载操作按钮。
gridConstraints = [
    previewView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
    previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    previewView.heightAnchor.constraint(equalToConstant: 120),
    titleLabel.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 10),
    titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    titleLabel.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
    titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
    moreButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    moreButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
    moreButton.widthAnchor.constraint(equalToConstant: 32),
    moreButton.heightAnchor.constraint(equalToConstant: 32),
    titleTextField.topAnchor.constraint(equalTo: previewView.bottomAnchor, constant: 8),
    titleTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
    titleTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
    titleTextField.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12)
]
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift
// 函数名: applyPresentationStyle(_:)
// 功能说明: 修改后 macOS Grid 标题改为左对齐，与三点按钮共享标题区。
switch presentationStyle {
case .boardGrid:
    titleLabel.alignment = .left
    titleTextField.alignment = .left
    moreButton.isHidden = false
    NSLayoutConstraint.activate(gridConstraints)
case .boardList:
    titleLabel.alignment = .left
    titleTextField.alignment = .left
    moreButton.isHidden = false
    NSLayoutConstraint.activate(listConstraints)
// ...
}
```

## 布局影响说明

- 这次只改了 `Grid` 模式三点按钮的约束和标题对齐方式。
- `List` 模式原有布局不变。
- `titleTextField` 仍保持全宽 trailing 到容器右侧；这是为了进入 rename 编辑态时，隐藏按钮后输入框能继续使用完整标题区域。

## 验证结果

- `ReadLints`
  - 检查文件：
    - `MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift`
    - `MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift`
  - 结果：无 linter 错误。
- `swiftc` typecheck
  - 命令：

```bash
xcrun --sdk macosx swiftc -typecheck -parse-as-library MyCanvas_Ver_0/**/*.swift
```

  - 结果：通过。

## 当前状态

- `Grid` 模式下，三点按钮已经不再位于缩略图区域右上角。
- `iOS` / `macOS` 两端的 `Grid` 卡片都改为：缩略图在上，标题与三点按钮在下方标题区同行排列。
