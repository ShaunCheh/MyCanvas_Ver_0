# 20260804_141957_handle_active_fill_only_border_stable_record

## 记录范围

本记录如实描述刚刚对 handle active 视觉反馈的修正：点击或拖动 handle 时只改变填充色，不再改变 handle 自身的描边颜色。

本次修改集中在共享样式解析器，因此 iOS 和 macOS 使用同一规则：

- selection resize、rotate、arrow endpoint、group frame resize 的描边始终保持蓝色。
- crop resize 的描边始终保持橙色。
- active 状态只把填充从白色改为对应 family 的强调色。

本次没有修改 handle identity、交互状态机、pointer lifecycle、几何计算、history、autosave 或持久化逻辑，也没有执行 Git commit。

## 时间戳与 changes 依据

文件名时间戳来自系统自带 `date` 命令：

```shell
# 文件路径: 无（终端命令）
# 函数/命令: date '+%Y%m%d_%H%M%S'
20260804_141957
```

创建本记录前的工作区状态：

```shell
# 文件路径: 无（终端命令）
# 函数/命令: git status --short
 M MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift
 M MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift
```

当前 diff 统计：

```shell
# 文件路径: 无（终端命令）
# 函数/命令: git diff --stat
.../Shared/Rendering/CanvasEditHandleVisualStyle.swift |  4 +++-
.../CanvasEditHandleVisualStyleTests.swift             | 16 ++++++++--------
2 files changed, 11 insertions(+), 9 deletions(-)
```

`git diff --check` 没有输出，说明当前 changes 不包含空白错误。

## 修改 1：active 状态不再反转描边颜色

### 修改前

共享样式解析器在 normal 状态使用“白色填充 + family 强调色描边”，进入 active 状态后同时反转填充和描边：

- 填充变为蓝色或橙色。
- 描边从蓝色或橙色变为白色。

因此用户点击或拖动 handle 时，handle 的边框颜色也发生了变化。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift
// 函数名: CanvasEditHandleVisualStyleResolver.resolve(kind:visualState:)
// 修改前说明: active 同时改变填充和描边，描边被切换为 neutralColor 白色。
case .active:
    return CanvasEditHandleVisualStyle(
        fillColor: accentColor,
        strokeColor: neutralColor
    )
```

### 修改后

active 状态仍使用强调色填充，但描边继续使用该 handle family 原本的 `accentColor`。这样 active 反馈只体现在内部填充，边框颜色在 pointer down、drag 和恢复期间保持稳定。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/Rendering/CanvasEditHandleVisualStyle.swift
// 函数名: CanvasEditHandleVisualStyleResolver.resolve(kind:visualState:)
// 功能说明: active 只改变填充；描边始终保持 selection 蓝色或 crop 橙色。
case .active:
    return CanvasEditHandleVisualStyle(
        fillColor: accentColor,
        // Active feedback changes the fill only; the family border
        // color remains stable throughout the interaction.
        strokeColor: accentColor
    )
```

最终视觉语义：

- selection/rotate/arrow/group handle：
  - normal：白色填充、蓝色描边。
  - active：蓝色填充、蓝色描边。
- crop handle：
  - normal：白色填充、橙色描边。
  - active：橙色填充、橙色描边。

外层 selection outline、crop outline 和 group frame outline 不在本次修改范围内。

## 修改 2：更新 selection family 样式测试

### 修改前

测试把 active selection family 的白色描边视为预期行为：

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift
// 函数名: testSelectionFamiliesUseWhiteAndBlueForNormalAndActiveStates()
// 修改前说明: active stroke 被断言为白色。
try assertColor(
    activeStyle.strokeColor,
    red: 1,
    green: 1,
    blue: 1,
    alpha: 1
)
```

### 修改后

测试名称改为明确表达稳定描边语义，并将 selection resize、rotate、arrow endpoint、group frame resize 的 active 描边统一断言为 selection blue。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift
// 函数名: testSelectionFamiliesKeepBlueStrokeWhenActive()
// 功能说明: 所有 selection family 在 active 时继续使用蓝色描边。
try assertColor(
    activeStyle.strokeColor,
    red: 0,
    green: 122.0 / 255.0,
    blue: 1,
    alpha: 1
)
```

## 修改 3：更新 crop family 与 geometry resolver 测试

### 修改前

crop active 和通过 geometry identity 解析出的 active crop style 都预期使用白色描边。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift
// 函数名: testCropUsesOrangeAccentWithoutLeakingSelectionBlue()
// 修改前说明: active crop stroke 被断言为白色。
try assertColor(
    activeStyle.strokeColor,
    red: 1,
    green: 1,
    blue: 1,
    alpha: 1
)
```

### 修改后

crop 测试名称改为 `testCropKeepsOrangeStrokeWhenActive()`，直接 resolver 与 geometry resolver 两条路径都断言 active crop 保持橙色描边。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift
// 函数名: testCropKeepsOrangeStrokeWhenActive()
// 功能说明: active crop 只把填充改为橙色，描边也继续保持原有橙色。
try assertColor(
    activeStyle.strokeColor,
    red: 1,
    green: 149.0 / 255.0,
    blue: 0,
    alpha: 1
)
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests.swift
// 函数名: testGeometryResolverUsesIdentityKindAndVisualState()
// 功能说明: 从 handle geometry identity 解析 active crop style 时，同样保持橙色描边。
try assertColor(
    style.strokeColor,
    red: 1,
    green: 149.0 / 255.0,
    blue: 0,
    alpha: 1
)
```

## 验证结果

### 样式单元测试

```shell
# 文件路径: 无（终端命令）
# 函数/命令: xcodebuild test；验证 normal/active 填充与稳定描边规则
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasEditHandleVisualStyleTests"
```

结果：退出码为 `0`，`CanvasEditHandleVisualStyleTests` 全部通过。

### iOS Simulator 构建

```shell
# 文件路径: 无（终端命令）
# 函数/命令: xcodebuild build；验证共享样式修改在 iOS target 编译通过
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO
```

结果：退出码为 `0`，iOS Simulator build 成功。

### 静态检查

- `CanvasEditHandleVisualStyle.swift` 和 `CanvasEditHandleVisualStyleTests.swift` 的 IDE diagnostics 均无 linter error。
- `git diff --check` 通过。
- 当前 changes 仅包含共享 handle 样式、对应测试以及本记录文件。
