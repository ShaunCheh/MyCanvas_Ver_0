# 20260721_103923_CST_macos_window_arc_release_crash_fix_record

## 记录范围

- 本次修改目标：
  - 修复 `Command-W` 关闭程序化创建的 macOS 主窗口时，App 在窗口关闭阶段异常退出的问题。
  - 保留既有的窗口生命周期设计：窗口关闭后清空引用，App 进程继续运行，点击 Dock 图标时创建新窗口。
- 业务代码涉及文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
- 本记录文件：
  - `commit_records/20260721_103923_CST_macos_window_arc_release_crash_fix_record.md`
- 本次没有修改其他业务代码，没有新增自动化测试，没有执行提交操作。
- 本记录依据当前 `git diff`、工作区 changes 和实际构建结果整理，不粘贴原始 `git diff`。

## 时间戳与 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统自带的 date 命令生成本记录开头和文件名中的时间戳。
20260721_103923_CST
```

生成本记录文件前，工作区只有 `macOSAppDelegate.swift` 的本次修复：

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录 Markdown 创建前的当前 changes，确认业务代码修改范围。
 M MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- "MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift"
# 功能说明: 汇总本次修复的改动规模，不粘贴原始 git diff。
 MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift | 2 ++
 1 file changed, 2 insertions(+)
```

## 问题表现与定位

- 主窗口由 `macOSAppDelegate.openMainWindow()` 直接创建，没有交给 `NSWindowController` 管理。
- 窗口关闭时，既有 `windowWillClose(_:)` 会把 App Delegate 持有的 `window` 强引用设为 `nil`。
- `NSWindow.isReleasedWhenClosed` 的默认值为 `true`。
- 对于 Swift/ARC 下直接创建、且不由 `NSWindowController` 持有的窗口，如果继续使用默认自动释放行为，窗口关闭时会同时涉及：
  - App Delegate 清空强引用产生的 ARC release。
  - AppKit 根据 `isReleasedWhenClosed == true` 执行的自动 release。
- 该所有权冲突可能在 `performClose(_:)` 的关闭流程中造成窗口过度释放，表现为 `EXC_BAD_ACCESS` 或进程在 `window ... finishing close` 后异常结束。

本次定位同时区分了下列启动期日志；它们不是这次 `Command-W` 关闭崩溃的直接原因：

- Secure Restorable State 警告。
- `restoreWindowWithIdentifier` 的 `className=(null)` 警告。
- App Group CFPrefs 警告。
- `/private/var/db/DetachedSignatures` 的系统 SQLite 日志。

## 修改前

### 程序化窗口沿用 `NSWindow` 默认关闭释放策略

- `openMainWindow()` 创建 `NSWindow` 后直接继续配置窗口。
- 没有覆盖 `isReleasedWhenClosed`，因此该属性保持默认值 `true`。
- 这与 `windowWillClose(_:)` 中由 ARC 清空强引用的生命周期方案不一致。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改前）
// 函数名: openMainWindow()
// 功能说明: 修改前直接创建 NSWindow，但没有声明由 ARC 管理关闭后的最终释放。
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
// 需要设置最小尺寸，否则不会显示
window.contentMinSize = NSSize(width: 640, height: 420)
```

既有的关闭回调会清除 App Delegate 的强引用：

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改前，保持不变）
// 函数名: windowWillClose(_:)
// 功能说明: 主窗口关闭时清空引用，使 Dock Reopen 后能够进入新建窗口分支。
func windowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
          closingWindow === window else {
        return
    }
    window = nil
}
```

### 修改前的所有权链路

1. App Delegate 的 `window` 属性强引用当前窗口。
2. `Command-W` 通过 `performClose(_:)` 启动关闭流程。
3. `windowWillClose(_:)` 将 `window` 设为 `nil`，ARC 释放该强引用。
4. `NSWindow` 仍按默认 `isReleasedWhenClosed == true` 执行自动释放。
5. 两套释放责任重叠，存在过度释放风险。

## 修改后

### 明确关闭后的窗口只由 ARC 所有权链管理

- 在 `NSWindow` 创建完成后立即设置 `window.isReleasedWhenClosed = false`。
- 注释明确说明窗口由 App Delegate 持有，并在 `windowWillClose(_:)` 中解除持有。
- 窗口的显示、关闭、清空引用和 Dock Reopen 仍沿用原来的统一生命周期入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改后）
// 函数名: openMainWindow()
// 功能说明: 禁止 NSWindow 在 close 时额外自动释放，最终释放统一交给 ARC 强引用生命周期。
let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
// 由 AppDelegate 在 windowWillClose 中释放，避免 NSWindow 在 ARC 下重复释放
window.isReleasedWhenClosed = false
// 需要设置最小尺寸，否则不会显示
window.contentMinSize = NSSize(width: 640, height: 420)
```

### 修改后的所有权链路

1. `openMainWindow()` 创建窗口，并立即关闭 `NSWindow` 的自动 release 行为。
2. App Delegate 通过 `self.window` 持有当前窗口。
3. `Command-W` 仍然调用 `performClose(_:)` 关闭窗口。
4. `windowWillClose(_:)` 把 `self.window` 设为 `nil`。
5. ARC 根据强引用生命周期释放窗口，不再与 `NSWindow` 的历史自动 release 语义叠加。
6. App 进程继续运行；再次点击 Dock 图标时，`openMainWindow()` 看到 `window == nil`，创建新窗口。

## 为什么保留 `windowWillClose(_:)`

- 不能通过删除 `windowWillClose(_:)` 来规避崩溃。
- 如果关闭后仍保留旧 `window` 引用，Dock Reopen 会尝试复用已经关闭的窗口，而不是按当前设计新建窗口。
- 本次修复调整的是 `NSWindow` 的释放策略，使其与现有 ARC 所有权设计一致，而不是绕开窗口引用清理。

## 未包含的修改

- 没有修改 `applicationShouldHandleReopen(_:hasVisibleWindows:)`。
- 没有修改 `applicationShouldTerminateAfterLastWindowClosed(_:)`。
- 没有改动 `Command-W` 菜单 action。
- 没有处理 Secure Restorable State 和窗口恢复警告；它们属于独立的状态恢复策略问题。
- 没有处理 App Group CFPrefs 或系统 `DetachedSignatures` 日志。

## 验证情况

已执行 macOS Debug 构建：

```sh
# 文件路径: MyCanvas_Ver_0.xcodeproj
# 函数名: xcodebuild
# 功能说明: 编译 MyCanvas_Ver_0 的 macOS Debug 目标，验证 NSWindow 所有权修复能够通过编译。
xcodebuild \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "platform=macOS" \
  build

** BUILD SUCCEEDED **
```

- `macOSAppDelegate.swift` 的编辑器诊断结果：没有 lint error。
- `git diff --check`：通过，没有空白错误。
- 本次没有新增或运行自动化测试。
- 本次没有在工具流程中执行 GUI 端到端操作，因此仍需人工确认：
  - `Command-W` 后 App 进程保持运行。
  - 点击 Dock 图标后重新创建主窗口。
  - 多次重复关闭和重开不会异常退出。

## 当前 changes

记录文件落盘后，实际工作区状态如下：

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 如实记录 NSWindow 所有权修复及本次新增 Markdown 记录文件。
 M MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
?? commit_records/20260721_103923_CST_macos_window_arc_release_crash_fix_record.md
```

- 当前 tracked 业务代码修改只有 `macOSAppDelegate.swift`。
- 当前新增未跟踪文件只有本次 Markdown 记录。
- 没有暂存或提交任何文件。
