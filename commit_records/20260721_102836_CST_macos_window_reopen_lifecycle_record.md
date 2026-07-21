# 20260721_102836_CST_macos_window_reopen_lifecycle_record

## 记录范围

- 本次修改目标：
  - `Command-W` 关闭主窗口后，macOS App 进程继续运行。
  - App 没有窗口时，再次点击 Dock 图标能够创建新的主窗口。
  - App 仍有主窗口但窗口被最小化时，统一恢复并前置现有窗口。
- 业务代码涉及文件：
  - `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
- 本记录文件：
  - `commit_records/20260721_102836_CST_macos_window_reopen_lifecycle_record.md`
- 本次没有修改其他业务代码，没有新增测试，没有执行提交操作。
- 本记录依据修改前后的代码、当前 `git diff` 和工作区 changes 整理，不粘贴原始 `git diff`。

## 时间戳与 changes 证据

```sh
# 文件路径: 无（终端命令）
# 函数名: date "+%Y%m%d_%H%M%S_%Z"
# 功能说明: 使用系统自带的 date 命令生成本记录文件开头和文件名中的时间戳。
20260721_102836_CST
```

生成本记录文件之前，工作区只有本次修改的 macOS App Delegate：

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 记录 Markdown 文件创建前的当前 changes，确认业务代码修改范围。
 M MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
```

```sh
# 文件路径: 无（终端命令）
# 函数名: git diff --stat -- "MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift"
# 功能说明: 汇总本次业务代码改动规模，不粘贴原始 git diff。
 .../Platform/macOS/macOSAppDelegate.swift          | 57 ++++++++++++++++++++--
 1 file changed, 54 insertions(+), 3 deletions(-)
```

## 修改前的情况

### 1. 窗口只在 App 首次启动时创建

- `macOSAppDelegate` 只遵循 `NSApplicationDelegate`。
- 窗口创建代码直接写在 `applicationDidFinishLaunching(_:)` 中。
- `applicationDidFinishLaunching(_:)` 只在进程完成启动时执行；运行中的 App 被再次点击 Dock 图标时，不会重新执行该方法。
- 因此窗口一旦关闭，原实现没有处理 macOS 的 Reopen Apple Event，也没有重新创建窗口的入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改前）
// 函数名: macOSAppDelegate / applicationDidFinishLaunching(_:)
// 功能说明: 修改前仅在 App 首次启动时内联创建并显示唯一主窗口。
@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderBookmarkStore.mirrorStoredBookmarkToSharedStoreIfNeeded()
        FolderBookmarkStore.logStoredBookmarkPresence()

        let viewController = macOSAppRootViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.center()
        window.title = "MyCanvas_Ver_0"
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.mainMenu = makeMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
```

### 2. 没有显式管理关闭后的窗口引用

- 修改前没有遵循 `NSWindowDelegate`，也没有实现 `windowWillClose(_:)`。
- `window` 属性会继续持有已经关闭的 `NSWindow`。
- 即使后续增加简单的 Dock 重开回调，也无法仅根据 `window != nil` 区分“当前有可复用窗口”和“属性仍指向已关闭窗口”。

### 3. 自定义主菜单没有 `Command-W` 对应项

- 原主菜单只加入 App 菜单和 Edit 菜单。
- 没有以 `performClose(_:)` 为 action 的 `Close Window` 菜单项，也没有在当前自定义菜单中显式建立 `Command-W` 快捷键。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改前）
// 函数名: makeMainMenu()
// 功能说明: 修改前的主菜单不包含承载 Close Window 命令的 File 菜单。
private func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    mainMenu.addItem(makeApplicationMenuItem())
    mainMenu.addItem(makeEditMenuItem())
    return mainMenu
}
```

### 4. 最后一个窗口关闭后的进程策略依赖 AppKit 默认行为

- 修改前没有实现 `applicationShouldTerminateAfterLastWindowClosed(_:)`。
- 普通 AppKit App 默认不会因为最后一个窗口关闭而退出，所以进程可以继续存在，但该产品行为没有在代码中显式表达。

## 修改后的情况

### 1. 显式拆分 App 生命周期和窗口生命周期

- `macOSAppDelegate` 新增 `NSWindowDelegate` 遵循关系。
- `applicationShouldTerminateAfterLastWindowClosed(_:)` 明确返回 `false`，规定关闭最后一个窗口不等于退出 App。
- `windowWillClose(_:)` 只在关闭对象确实是当前主窗口时清空引用。
- 主窗口关闭并清空引用后，根视图控制器不再由 `window` 属性继续持有；下一次 Reopen 会进入新建窗口分支。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改后）
// 函数名: macOSAppDelegate / applicationShouldTerminateAfterLastWindowClosed(_:) / windowWillClose(_:)
// 功能说明: 显式保持 App 进程，并在主窗口关闭时清除窗口所有权引用。
@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }
        window = nil
    }
}
```

### 2. Dock Reopen 事件统一进入主窗口入口

- 新增 `applicationShouldHandleReopen(_:hasVisibleWindows:)`。
- 用户点击已经运行中的 App Dock 图标时，AppKit 调用该代理方法。
- 回调不重复实现窗口逻辑，而是统一调用 `openMainWindow()`。
- 返回 `true`，表示 App 响应该 Reopen 事件。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改后）
// 函数名: applicationShouldHandleReopen(_:hasVisibleWindows:)
// 功能说明: 响应运行中 App 的 Dock Reopen 事件并进入统一主窗口入口。
func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows _: Bool
) -> Bool {
    openMainWindow()
    return true
}
```

### 3. 提取幂等的 `openMainWindow()` 窗口入口

- `applicationDidFinishLaunching(_:)` 现在只负责启动期服务、菜单装配和调用统一窗口入口。
- `openMainWindow()` 根据当前窗口状态决定恢复现有窗口还是创建新窗口：
  - `window` 存在：若已最小化则先 `deminiaturize(nil)`，随后前置并激活。
  - `window` 不存在：创建新的 `macOSAppRootViewController` 和 `NSWindow`。
- 新窗口把 delegate 设置为 `self`，从而让 `windowWillClose(_:)` 能够完成关闭后的引用清理。
- 在显示窗口前先写入 `self.window`，确保 App Delegate 从窗口开始使用时就持有它。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改后）
// 函数名: applicationDidFinishLaunching(_:) / openMainWindow()
// 功能说明: 首次启动和 Dock Reopen 共用同一个幂等窗口创建、恢复与前置入口。
func applicationDidFinishLaunching(_ notification: Notification) {
    FolderBookmarkStore.mirrorStoredBookmarkToSharedStoreIfNeeded()
    FolderBookmarkStore.logStoredBookmarkPresence()
    NSApp.mainMenu = makeMainMenu()
    openMainWindow()
}

private func openMainWindow() {
    if let window {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return
    }

    let viewController = macOSAppRootViewController()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled, .closable, .miniaturizable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.contentMinSize = NSSize(width: 640, height: 420)
    window.center()
    window.title = "MyCanvas_Ver_0"
    window.contentViewController = viewController
    window.delegate = self
    self.window = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}
```

### 4. 增加标准 `Command-W` 关闭窗口入口

- `makeMainMenu()` 现在在 App 菜单和 Edit 菜单之间加入 File 菜单。
- `makeFileMenuItem()` 创建 `Close Window` 菜单项。
- 菜单项 action 使用 `NSWindow.performClose(_:)`，target 保持默认的 `nil`，由 AppKit responder chain 把命令交给当前窗口。
- 快捷键为小写 `w`，modifier 为 `.command`，对应 `Command-W`。
- 该动作只关闭窗口；是否终止 App 由 `applicationShouldTerminateAfterLastWindowClosed(_:)` 独立决定。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift（修改后）
// 函数名: makeMainMenu() / makeFileMenuItem()
// 功能说明: 在自定义菜单中注册 Close Window，并将 Command-W 发送给当前窗口。
private func makeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    mainMenu.addItem(makeApplicationMenuItem())
    mainMenu.addItem(makeFileMenuItem())
    mainMenu.addItem(makeEditMenuItem())
    return mainMenu
}

private func makeFileMenuItem() -> NSMenuItem {
    let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
    let fileMenu = NSMenu(title: "File")
    let closeItem = NSMenuItem(
        title: "Close Window",
        action: #selector(NSWindow.performClose(_:)),
        keyEquivalent: "w"
    )
    closeItem.keyEquivalentModifierMask = [.command]
    fileMenu.addItem(closeItem)
    fileMenuItem.submenu = fileMenu
    return fileMenuItem
}
```

## 行为链路

### `Command-W` 关闭

1. File 菜单中的 `Command-W` 触发 `NSWindow.performClose(_:)`。
2. 当前主窗口开始关闭。
3. `windowWillClose(_:)` 验证关闭对象并把 `window` 设为 `nil`。
4. `applicationShouldTerminateAfterLastWindowClosed(_:)` 返回 `false`，App 进程与 Dock 图标继续存在。

### 点击 Dock 图标重开

1. macOS 向正在运行的 App 发送 Reopen Apple Event。
2. AppKit 调用 `applicationShouldHandleReopen(_:hasVisibleWindows:)`。
3. 回调调用 `openMainWindow()`。
4. 因为已关闭主窗口对应的引用是 `nil`，入口创建新的 `NSWindow` 和 `macOSAppRootViewController`。
5. 新窗口成为 key window，并被前置显示。

## 验证情况

已执行 macOS Debug 构建：

```sh
# 文件路径: MyCanvas_Ver_0.xcodeproj
# 函数名: xcodebuild
# 功能说明: 编译 MyCanvas_Ver_0 的 macOS Debug 目标，验证本次 AppKit 生命周期改动能够通过编译。
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
- 本次没有新增自动化测试。
- 本次没有执行实际 GUI 操作测试，因此“按下 `Command-W` 后点击 Dock 图标”的端到端交互仍需在运行中的 App 上人工确认。

## 当前 changes

记录文件落盘后，实际工作区状态如下：

```sh
# 文件路径: 无（终端命令）
# 函数名: git status --short
# 功能说明: 如实记录业务代码修改及本次新增 Markdown 记录文件。
 M MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift
?? commit_records/20260721_102836_CST_macos_window_reopen_lifecycle_record.md
```

- 当前 tracked 业务代码修改仍只有 `macOSAppDelegate.swift`。
- 当前新增未跟踪文件只有本次 Markdown 记录。
- 没有暂存或提交任何文件。
