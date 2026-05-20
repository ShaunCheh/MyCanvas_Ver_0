# 20260520_144259_ios_markdown_keyboard_avoidance_record

## 记录范围

- 记录内容：
  - 修复 iOS 端 markdown 编辑器在键盘弹出时，编辑区底部被键盘遮挡的问题。
  - 本次修复不改 markdown 内容提交流程，也不改渲染逻辑，只收口 `iOSCanvasMarkdownEditorViewController` 的布局约束。
  - 由于项目当前 iOS deployment target 为 `15.6`，本次直接使用 `view.keyboardLayoutGuide` 处理键盘避让，没有引入额外的键盘通知兼容分支。
- 涉及文件：
  - `MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift`
- 参考现状：
  - `git status --short` 显示当前工作区只有 `1` 个已跟踪代码文件处于修改状态。
  - `git diff --stat -- <本次修复文件>` 显示当前这次修复为：`1 file changed, 3 insertions(+), 1 deletion(-)`。
- 本记录不包含：
  - 任何 git 提交行为。
  - 任何 `.md` 计划文件内容改动。

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: date +"%Y%m%d_%H%M%S_ios_markdown_keyboard_avoidance"
# 功能说明: 使用系统 date 命令生成本记录文件的时间戳前缀。
20260520_144259_ios_markdown_keyboard_avoidance
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git status --short
# 功能说明: 如实记录当前工作区状态；本次键盘避让修复只涉及一个 iOS markdown 编辑器文件。
 M MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift
```

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: git diff --stat -- "MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift"
# 功能说明: 统计本次 iOS markdown 键盘避让修复的真实改动量。
.../Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift | 4 +++-
1 file changed, 3 insertions(+), 1 deletion(-)
```

## 当前 changes 摘要

- 修改前，markdown 编辑器的 `textContainerView.bottomAnchor` 固定绑定到 `safeAreaLayoutGuide.bottomAnchor`，因此键盘弹出后，编辑区不会跟随键盘上移，底部文本会被盖住。
- 修改后，编辑器底部约束改为绑定 `view.keyboardLayoutGuide.topAnchor`，并开启 `followsUndockedKeyboard`，让编辑区底部跟随键盘顶部移动。
- 这次修复是**布局根因修复**，不是靠 `contentInset` 或滚动补丁去“掩盖”遮挡现象。

## 修改一：让 markdown 编辑器底部跟随键盘顶部

### 1.1 修改前

- `setupConstraints()` 里只拿了 `safeAreaLayoutGuide`。
- `textContainerView.bottomAnchor` 固定约束在 safe area 底边之上 `20pt`。
- 这意味着 sheet 出现后，即使键盘弹出，容器底部也不会重新避开键盘。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift（修改前）
// 函数名: setupConstraints()
// 功能说明: 修改前编辑器底部只跟 safe area 对齐；键盘出现时，textContainerView 不会随键盘顶部一起上移。
private func setupConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
        cancelButton.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: 20
        ),
        cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        doneButton.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -20
        ),
        doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        titleLabel.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor,
            constant: 20
        ),
        titleLabel.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
        titleLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: cancelButton.trailingAnchor,
            constant: 12
        ),
        titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: doneButton.leadingAnchor,
            constant: -12
        ),
        textContainerView.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor,
            constant: 20
        ),
        textContainerView.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: 20
        ),
        textContainerView.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -20
        ),
        textContainerView.bottomAnchor.constraint(
            equalTo: safeAreaLayoutGuide.bottomAnchor,
            constant: -20
        ),
        textView.topAnchor.constraint(equalTo: textContainerView.topAnchor),
        textView.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor),
        textView.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor),
        textView.bottomAnchor.constraint(equalTo: textContainerView.bottomAnchor)
    ])
}
```

### 1.2 修改后

- `setupConstraints()` 里新增 `keyboardLayoutGuide`。
- 打开 `keyboardLayoutGuide.followsUndockedKeyboard = true`，让 iPad 浮动键盘也能被正确跟随。
- `textContainerView.bottomAnchor` 改为绑定 `keyboardLayoutGuide.topAnchor`，底部仍保留 `20pt` 间距。
- 这样键盘弹出时，编辑区会跟着压缩到键盘上方，底部文本区不再被键盘遮挡。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Markdown/iOSCanvasMarkdownEditorViewController.swift
// 函数名: setupConstraints()
// 功能说明: 修改后编辑器底部约束绑定到 keyboardLayoutGuide.topAnchor，键盘出现时 textContainerView 会跟着键盘顶部一起抬升。
private func setupConstraints() {
    let safeAreaLayoutGuide = view.safeAreaLayoutGuide
    let keyboardLayoutGuide = view.keyboardLayoutGuide
    keyboardLayoutGuide.followsUndockedKeyboard = true
    NSLayoutConstraint.activate([
        cancelButton.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: 20
        ),
        cancelButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        doneButton.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -20
        ),
        doneButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
        titleLabel.topAnchor.constraint(
            equalTo: safeAreaLayoutGuide.topAnchor,
            constant: 20
        ),
        titleLabel.centerXAnchor.constraint(equalTo: safeAreaLayoutGuide.centerXAnchor),
        titleLabel.leadingAnchor.constraint(
            greaterThanOrEqualTo: cancelButton.trailingAnchor,
            constant: 12
        ),
        titleLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: doneButton.leadingAnchor,
            constant: -12
        ),
        textContainerView.topAnchor.constraint(
            equalTo: titleLabel.bottomAnchor,
            constant: 20
        ),
        textContainerView.leadingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.leadingAnchor,
            constant: 20
        ),
        textContainerView.trailingAnchor.constraint(
            equalTo: safeAreaLayoutGuide.trailingAnchor,
            constant: -20
        ),
        textContainerView.bottomAnchor.constraint(
            equalTo: keyboardLayoutGuide.topAnchor,
            constant: -20
        ),
        textView.topAnchor.constraint(equalTo: textContainerView.topAnchor),
        textView.leadingAnchor.constraint(equalTo: textContainerView.leadingAnchor),
        textView.trailingAnchor.constraint(equalTo: textContainerView.trailingAnchor),
        textView.bottomAnchor.constraint(equalTo: textContainerView.bottomAnchor)
    ])
}
```

## 验证

- 已执行 iOS Simulator 构建，结果通过。
- 本次记录新增到 `commit_records/`，没有修改其他现有 `.md` 文件。

```bash
# 工作目录: /Users/shaun/cloudDev/MyCanvas_Ver_0
# 命令: xcodebuild build -scheme MyCanvas_Ver_0 -destination 'generic/platform=iOS Simulator'
# 功能说明: 验证 iOS markdown 编辑器键盘避让改动能够正常通过 iOS Simulator 构建。
结果: 通过
```
