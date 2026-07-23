# 20260723_111146_macos_group_title_edit_focus_fix_record

## 记录范围

本记录如实对应刚刚完成的 macOS group 名称编辑态修复与诊断日志补充。问题现象是：在 macOS 上点击 group 列表行右侧的编辑按钮后，标题输入框只闪一下，随后又恢复为普通文本，无法保持可编辑状态。

本次实际修改的代码文件：

- `MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift`

当前 `git status` 显示的运行时代码改动只有上述 Swift 文件。本记录基于当前 `git diff` 与工作区 changes 整理，不直接粘贴原始 diff。

## 定位结论

从运行日志确认，点击编辑按钮后，controller 已正确设置 `editingGroupTitleID`，group list 也已经 render 出目标 `NSTextField`。异常发生在程序化聚焦阶段：`makeFirstResponder(...)` / `selectText(...)` 过程中，AppKit 同步触发了 `controlTextDidEndEditing`，而修改前的 delegate 会把该事件当成真实用户提交，立刻调用 `commitGroupTitleEditing(...)`，清空 `editingGroupTitleID` 并重新 render，最终表现为输入框闪一下后消失。

## 修改前

### 程序化聚焦没有区分 AppKit responder 抖动

修改前，`render(...)` 创建编辑态 `NSTextField` 后，会在下一轮 main queue 中直接调用 `makeFirstResponder(...)` 和 `selectText(...)`。这段流程没有记录“当前正在程序化聚焦”，因此无法识别聚焦过程中由 AppKit 触发的临时 `controlTextDidEndEditing`。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前只负责把新建的 group title text field 聚焦并全选，没有标记程序化聚焦状态。
// 函数名：macOSCanvasGroupListView.render(groups:editingGroupTitleID:)
updateDocumentLayout()
if let focusedTitleTextField {
    DispatchQueue.main.async { [weak self, weak focusedTitleTextField] in
        guard let self, let focusedTitleTextField else {
            return
        }

        self.window?.makeFirstResponder(focusedTitleTextField)
        focusedTitleTextField.selectText(nil)
    }
}
```

### 任何结束编辑通知都会提交 group title

修改前，`controlTextDidEndEditing(...)` 对所有 `NSTextField` 结束编辑事件都直接调用 `submitGroupTitle(...)`。当 AppKit 在程序化聚焦阶段同步发出结束编辑通知时，也会走入提交链路。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前没有区分用户主动结束编辑和程序化聚焦期间的结束编辑通知。
// 函数名：macOSCanvasGroupListView.controlTextDidEndEditing(_:)
func controlTextDidEndEditing(_ obj: Notification) {
    guard let textField = obj.object as? NSTextField else {
        return
    }

    submitGroupTitle(from: textField)
}
```

### 提交时没有校验当前 rendered editing id

修改前，`submitGroupTitle(from:)` 只校验 control 是否为 group title text field，然后直接回调 controller。旧 text field 的迟到事件也可能进入提交路径。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：修改前只判断 control 类型，没有确认该 text field 仍是当前正在编辑的 group。
// 函数名：macOSCanvasGroupListView.submitGroupTitle(from:)
private func submitGroupTitle(from control: NSControl) {
    guard let titleTextField = control as? macOSCanvasGroupTitleTextField else {
        return
    }

    onGroupTitleSubmitted?(
        titleTextField.groupID,
        titleTextField.stringValue
    )
}
```

## 修改后

### 增加 macOS group title edit 诊断日志

修改后新增 `macOSGroupTitleEditTrace(...)`，用于记录 edit button click、controller begin/commit、list render/focus、delegate end editing、submit 等阶段的 group id、当前 editing id、title、first responder 和额外细节。该日志用于复测确认问题链路。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：记录 macOS group title 编辑链路的关键状态，帮助确认 responder 事件顺序。
// 函数名：macOSGroupTitleEditTrace(_:groupID:editingGroupTitleID:title:firstResponder:detail:)
private func macOSGroupTitleEditTrace(
    _ phase: String,
    groupID: CanvasItemGroupID? = nil,
    editingGroupTitleID: CanvasItemGroupID? = nil,
    title: String? = nil,
    firstResponder: NSResponder? = nil,
    detail: String? = nil
) {
    let groupIDDescription = groupID?.uuidString ?? "nil"
    let editingGroupIDDescription = editingGroupTitleID?.uuidString ?? "nil"
    let titleDescription = title.map { "\"\($0)\"" } ?? "nil"
    let responderDescription = firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
    let detailDescription = detail ?? "nil"
    print(
        "[Canvas macOS][GroupTitleEdit] " +
        "phase=\(phase) " +
        "groupID=\(groupIDDescription) " +
        "editingGroupTitleID=\(editingGroupIDDescription) " +
        "title=\(titleDescription) " +
        "firstResponder=\(responderDescription) " +
        "detail=\(detailDescription)"
    )
}
```

### 记录程序化聚焦中的 group title id

修改后，`macOSCanvasGroupListView` 增加 `programmaticFocusGroupTitleID`。当 render 出目标输入框并准备程序化 focus 时，先记录目标 group id；下一轮 runloop 再清空该标记。这样可以覆盖 `makeFirstResponder(...)` / `selectText(...)` 过程中同步触发的 AppKit delegate 事件。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：记录当前正在被程序化聚焦的 group title，用于识别 AppKit 聚焦过程中的临时 end-edit 事件。
// 函数名：macOSCanvasGroupListView.render(groups:editingGroupTitleID:)
private var programmaticFocusGroupTitleID: CanvasItemGroupID?

// ... render 内部
let focusedGroupID = (focusedTitleTextField as? macOSCanvasGroupTitleTextField)?.groupID
self.programmaticFocusGroupTitleID = focusedGroupID
let didFocus = self.window?.makeFirstResponder(focusedTitleTextField) ?? false
focusedTitleTextField.selectText(nil)
macOSGroupTitleEditTrace(
    "list.render.focus.after",
    groupID: focusedGroupID,
    editingGroupTitleID: self.renderedEditingGroupTitleID,
    title: focusedTitleTextField.stringValue,
    firstResponder: self.window?.firstResponder,
    detail: "didFocus=\(didFocus)"
)
DispatchQueue.main.async { [weak self] in
    guard self?.programmaticFocusGroupTitleID == focusedGroupID else {
        return
    }

    self?.programmaticFocusGroupTitleID = nil
}
```

### 忽略程序化聚焦期间的结束编辑通知

修改后，`controlTextDidEndEditing(...)` 在提交前会判断当前 text field 是否正处于程序化聚焦阶段。如果是，则记录 `ignoredProgrammaticFocus` 并返回，不再触发 `submitGroupTitle(...)`。这就是阻止“闪一下后退出编辑态”的关键修复。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：过滤程序化聚焦阶段由 AppKit responder 链触发的非用户提交型结束编辑通知。
// 函数名：macOSCanvasGroupListView.controlTextDidEndEditing(_:)
func controlTextDidEndEditing(_ obj: Notification) {
    guard let textField = obj.object as? NSTextField else {
        return
    }

    if let titleTextField = textField as? macOSCanvasGroupTitleTextField,
       programmaticFocusGroupTitleID == titleTextField.groupID {
        macOSGroupTitleEditTrace(
            "list.controlTextDidEndEditing.ignoredProgrammaticFocus",
            groupID: titleTextField.groupID,
            editingGroupTitleID: renderedEditingGroupTitleID,
            title: titleTextField.stringValue,
            firstResponder: window?.firstResponder
        )
        return
    }

    submitGroupTitle(from: textField)
}
```

### 提交时拒绝旧 text field 的迟到事件

修改后，`submitGroupTitle(from:)` 额外校验 `renderedEditingGroupTitleID == titleTextField.groupID`。如果当前 UI 已经不在编辑该 group，说明这是旧 text field 或重复 delegate 事件，直接忽略。

```swift
// MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift
// 功能注释：只允许当前 rendered editing group 的 text field 提交，避免旧 field 的迟到事件污染状态。
// 函数名：macOSCanvasGroupListView.submitGroupTitle(from:)
private func submitGroupTitle(from control: NSControl) {
    guard let titleTextField = control as? macOSCanvasGroupTitleTextField else {
        return
    }

    guard renderedEditingGroupTitleID == titleTextField.groupID else {
        macOSGroupTitleEditTrace(
            "list.submit.ignoredStaleEditingID",
            groupID: titleTextField.groupID,
            editingGroupTitleID: renderedEditingGroupTitleID,
            title: titleTextField.stringValue,
            firstResponder: window?.firstResponder
        )
        return
    }

    onGroupTitleSubmitted?(
        titleTextField.groupID,
        titleTextField.stringValue
    )
}
```

## 行为变化

- 点击 macOS group 列表行右侧编辑按钮后，目标 group title 应保持为可编辑 `NSTextField`。
- 程序化聚焦期间同步触发的 `controlTextDidEndEditing` 不再清空 `editingGroupTitleID`。
- 用户真实结束编辑时仍会提交：例如按 Return、点击其他可接收 first responder 的区域、切换到另一个 group 编辑。
- Return 后可能产生的重复 end-edit 事件会被 stale editing id 校验挡住，避免重复提交。

## 验证

已执行 lints 检查：

- `ReadLints`：`MyCanvas_Ver_0/Platform/macOS/macOSViewController.swift` 无 linter errors。

已执行 macOS build：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：验证 macOS group title edit 修复后的 Swift 编译结果。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -configuration Debug -destination 'platform=macOS' build
```

结果：build 成功。

复测时，点击 group 编辑按钮后，诊断日志中应出现 `list.controlTextDidEndEditing.ignoredProgrammaticFocus`，并且不应紧跟 `controller.commit.*` 清空编辑态。
