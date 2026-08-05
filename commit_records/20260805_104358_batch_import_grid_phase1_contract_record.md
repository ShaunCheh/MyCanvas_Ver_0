# 20260805_104358_batch_import_grid_phase1_contract_record

## 记录范围

本记录如实对应 `batch import grid` 计划的阶段 1：冻结导入布局契约，将现有对角错位模式从 `staggered` 正名为 `diagonal`，并建立普通批量媒体导入使用的 4 列网格代码配置。

本记录参考了创建记录前的：

- `git status --short`
- `git diff --stat`
- 三个变更文件的当前 `git diff`
- 定向测试输出
- IDE lint 结果

下文不粘贴原始 `git diff`，而是根据实际删除行、增加行和当前源码整理修改前后的情况。

阶段 1 只建立名称与配置契约，没有把 `.automatic` 切换成网格。当前多项 `.automatic` 导入仍会解析为对角线；纯布局 solver 和自动网格切换属于后续阶段。

## 时间戳来源

文件名前缀和本文标题中的时间戳由系统 `date` 命令生成。

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：生成“年月日_时分秒”格式的记录时间戳。
date '+%Y%m%d_%H%M%S'
```

命令实际输出：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# date 命令实际输出
20260805_104358
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名本次修改记录。
20260805_104358_batch_import_grid_phase1_contract_record.md
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git status --short 的实际输出
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
 M MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift
```

`git diff --stat` 的实际统计为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git diff --stat 的实际输出
 .../Canvas/Editing/CanvasEditorSession.swift       |  8 ++++----
 .../Canvas/Import/CanvasImportTypes.swift          | 14 +++++++++++++-
 .../CanvasImportRequestModelTests.swift            | 22 ++++++++++++++++++++++
 3 files changed, 39 insertions(+), 5 deletions(-)
```

## 修改一：建立普通批量导入网格配置

### 修改前

修改前只有通用的 `CanvasImportGridConfiguration` 数据结构。普通批量媒体导入没有独立的默认配置来源，4 列、横向间距和纵向间距也没有被集中定义。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名：CanvasImportGridConfiguration
// 功能注释：修改前只负责清洗调用方显式传入的列数和 world-space 间距。
struct CanvasImportGridConfiguration: Equatable {
    let columns: Int
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    init(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) {
        self.columns = max(columns, 1)
        self.horizontalSpacing = max(horizontalSpacing, 0)
        self.verticalSpacing = max(verticalSpacing, 0)
    }
}
```

### 修改后

新增 `CanvasBatchImportLayoutConfiguration`，以 `current` 作为普通批量导入布局的单一代码配置入口：

- 固定列数为 `4`。
- 横向间距为 `24` world units。
- 纵向间距为 `24` world units。
- 继续复用 `CanvasImportGridConfiguration` 的参数清洗能力。
- 没有复用 GIF 专用配置，普通导入和 GIF 帧选择/落板配置仍相互独立。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名：CanvasBatchImportLayoutConfiguration
// 功能注释：集中保存普通批量媒体自动网格所需的代码配置；阶段 1 仅建立契约，后续 solver 才会消费它。
struct CanvasBatchImportLayoutConfiguration: Equatable {
    static let current = CanvasBatchImportLayoutConfiguration(
        grid: CanvasImportGridConfiguration(
            columns: 4,
            horizontalSpacing: 24,
            verticalSpacing: 24
        )
    )

    let grid: CanvasImportGridConfiguration
}
```

## 修改二：将对角模式从 staggered 正名为 diagonal

### 修改前

现有对角错位布局使用 `.staggered(stepInWorld:)`。关联值保存世界坐标步长，但枚举名称没有直接表达产品语义中的“对角线模式”。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名：CanvasImportLayout
// 功能注释：修改前的对角错位模式名为 staggered。
enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
    case grid(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    )
}
```

### 修改后

`.staggered(stepInWorld:)` 被直接重命名为 `.diagonal(stepInWorld:)`：

- 关联值类型仍为 `CGPoint`。
- `stepInWorld` 标签与 world-space 语义保持不变。
- 没有保留 `staggered` 同义 case。
- 该请求枚举不参与 Codable 文档存储，因此不涉及数据迁移。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型名：CanvasImportLayout
// 功能注释：使用 diagonal 明确表示每个导入项沿 x/y 同步偏移的对角线布局。
enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case diagonal(stepInWorld: CGPoint)
    case grid(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    )
}
```

## 修改三：同步自动布局解析分支

### 修改前

`resolvedImportLayout(_:itemCount:)` 在多项 `.automatic` 导入时返回 `.staggered`。显式 `.staggered` 请求则原样返回。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.resolvedImportLayout(_:itemCount:)
// 功能注释：修改前，多项 automatic 和显式对角布局都使用 staggered 命名。
private func resolvedImportLayout(
    _ layout: CanvasImportLayout,
    itemCount: Int
) -> CanvasImportLayout {
    switch layout {
    case .automatic:
        if itemCount <= 1 {
            return .stacked
        }

        return .staggered(stepInWorld: duplicateOffsetInWorld())
    case .stacked:
        return .stacked
    case let .staggered(stepInWorld):
        return .staggered(stepInWorld: stepInWorld)
    case let .grid(columns, horizontalSpacing, verticalSpacing):
        let gridConfiguration = CanvasImportGridConfiguration(
            columns: columns,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        return .grid(
            columns: gridConfiguration.columns,
            horizontalSpacing: gridConfiguration.horizontalSpacing,
            verticalSpacing: gridConfiguration.verticalSpacing
        )
    }
}
```

### 修改后

该函数只同步名称，不改变阶段 1 的运行行为：

- `itemCount <= 1` 仍返回 `.stacked`。
- 多项 `.automatic` 仍调用 `duplicateOffsetInWorld()`，保持约 24 屏幕点的对角错位。
- 显式 `.diagonal` 仍原样保留调用方传入的 world-space step。
- `.grid` 的配置清洗逻辑没有变化。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.resolvedImportLayout(_:itemCount:)
// 功能注释：阶段 1 将现有对角布局正名为 diagonal，但暂不改变 automatic 的默认策略。
private func resolvedImportLayout(
    _ layout: CanvasImportLayout,
    itemCount: Int
) -> CanvasImportLayout {
    switch layout {
    case .automatic:
        if itemCount <= 1 {
            return .stacked
        }

        return .diagonal(stepInWorld: duplicateOffsetInWorld())
    case .stacked:
        return .stacked
    case let .diagonal(stepInWorld):
        return .diagonal(stepInWorld: stepInWorld)
    case let .grid(columns, horizontalSpacing, verticalSpacing):
        let gridConfiguration = CanvasImportGridConfiguration(
            columns: columns,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
        return .grid(
            columns: gridConfiguration.columns,
            horizontalSpacing: gridConfiguration.horizontalSpacing,
            verticalSpacing: gridConfiguration.verticalSpacing
        )
    }
}
```

## 修改四：同步对角偏移计算分支

### 修改前

`importOffset(forItemAt:layout:gridCellSize:)` 对 `.staggered` 使用 `index × stepInWorld` 计算每项偏移。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.importOffset(forItemAt:layout:gridCellSize:)
// 功能注释：修改前，staggered 分支按导入序号线性累加对角偏移。
case let .staggered(stepInWorld):
    let multiplier = CGFloat(index)
    return CGPoint(
        x: stepInWorld.x * multiplier,
        y: stepInWorld.y * multiplier
    )
```

### 修改后

分支名称变为 `.diagonal`，计算公式完全不变，因此当前对角线排列的几何结果没有变化。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.importOffset(forItemAt:layout:gridCellSize:)
// 功能注释：diagonal 继续按导入序号乘以 world-space step，保持原有对角错位几何。
case let .diagonal(stepInWorld):
    let multiplier = CGFloat(index)
    return CGPoint(
        x: stepInWorld.x * multiplier,
        y: stepInWorld.y * multiplier
    )
```

## 修改五：增加配置与 diagonal 契约测试

### 修改前

`CanvasImportRequestModelTests` 已验证显式 grid 参数清洗，但没有覆盖：

- 普通批量导入的默认列数和间距。
- 对角布局枚举的 step 保存。
- 对角布局不应暴露 grid 配置。

修改前，grid 测试后直接进入 presentation template 测试：

```swift
// MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift
// 测试类：CanvasImportRequestModelTests
// 功能注释：修改前只覆盖显式 grid 清洗，之后直接测试 presentation template。
func testGridLayoutExposesSanitizedGridConfiguration() throws {
    let layout = CanvasImportLayout.grid(
        columns: 0,
        horizontalSpacing: -12,
        verticalSpacing: -24
    )

    let gridConfiguration = try XCTUnwrap(layout.gridConfiguration)
    XCTAssertEqual(gridConfiguration.columns, 1)
    XCTAssertEqual(gridConfiguration.horizontalSpacing, 0)
    XCTAssertEqual(gridConfiguration.verticalSpacing, 0)
}

func testPresentationTemplateSanitizesSizeAndResolvesRotationPolicy() {
    // 原有 presentation template 测试继续存在。
}
```

### 修改后

新增两个测试：

1. `testBatchImportLayoutConfigurationUsesFourColumnGrid()`：锁定 4 列和横纵间距 24。
2. `testDiagonalLayoutPreservesConfiguredWorldStep()`：锁定 `.diagonal` 的关联 step，并确认它不是 grid。

```swift
// MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift
// 函数名：CanvasImportRequestModelTests.testBatchImportLayoutConfigurationUsesFourColumnGrid()
// 功能注释：验证普通批量导入默认配置固定为 4 列、横纵间距均为 24。
func testBatchImportLayoutConfigurationUsesFourColumnGrid() {
    let gridConfiguration = CanvasBatchImportLayoutConfiguration.current.grid

    XCTAssertEqual(gridConfiguration.columns, 4)
    XCTAssertEqual(gridConfiguration.horizontalSpacing, 24)
    XCTAssertEqual(gridConfiguration.verticalSpacing, 24)
}

// 函数名：CanvasImportRequestModelTests.testDiagonalLayoutPreservesConfiguredWorldStep()
// 功能注释：验证 diagonal 完整保留调用方传入的 world-space step，且不会被识别为 grid。
func testDiagonalLayoutPreservesConfiguredWorldStep() {
    let expectedStep = CGPoint(x: 18, y: 26)
    let layout = CanvasImportLayout.diagonal(
        stepInWorld: expectedStep
    )

    guard case let .diagonal(actualStep) = layout else {
        return XCTFail("Expected diagonal import layout.")
    }

    XCTAssertEqual(actualStep, expectedStep)
    XCTAssertNil(layout.gridConfiguration)
}
```

## 实际行为变化

本阶段的行为边界如下：

- 对外代码语义从 `.staggered` 改为 `.diagonal`。
- 现有对角偏移公式、24 屏幕点节奏和 zIndex 顺序没有变化。
- `.automatic` 的多项导入当前仍解析为 `.diagonal`。
- 新增的 4 列配置当前尚未接入运行链路，因此本阶段不会让批量导入立即显示为网格。
- `.stacked`、显式 `.grid`、GIF 帧 grid、媒体解码、历史记录、autosave 和持久化均未修改。

## 自动验证

### 定向模型测试

执行命令：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：编译完整 macOS 测试目标，并只运行阶段 1 涉及的导入请求模型测试类。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests"
```

实际结果：命令退出码为 `0`，`TEST SUCCEEDED`。以下 5 个测试全部通过：

- `testBatchImportLayoutConfigurationUsesFourColumnGrid`
- `testDiagonalLayoutPreservesConfiguredWorldStep`
- `testGridLayoutExposesSanitizedGridConfiguration`
- `testImportRequestStoresPresentationTemplateAndGridLayout`
- `testPresentationTemplateSanitizesSizeAndResolvesRotationPolicy`

### 旧命名扫描

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：确认所有 Swift 源码和测试均已移除 staggered 旧命名。
rg 'staggered' --glob '*.swift'
```

实际结果：没有匹配项。

### 差异格式与 IDE 诊断

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：检查当前代码差异是否包含空白错误。
git diff --check
```

实际结果：命令退出码为 `0`，没有输出。

IDE lint 检查范围：

- `MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift`

实际结果：`No linter errors found.`。

## 明确未修改的范围

- 未实现 `CanvasImportLayoutSolver`。
- 未将 `.automatic` 切换为 4 列 grid。
- 未改变现有 grid 的首格锚点语义。
- 未改变 GIF 帧导入位置。
- 未改变 iOS、macOS、分享扩展的导入入口。
- 未改变拖放 placement。
- 未改变媒体尺寸归一化、crop、rotation 或 zIndex。
- 未改变 history、autosave、storage 或文档格式。
- 未修改 `.cursor/plans/batch_import_grid_fc6b804f.plan.md`。

## 当前状态

创建本记录后，预期 `git status --short` 为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 创建记录后的预期工作区状态
 M MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
 M MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
 M MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift
?? commit_records/20260805_104358_batch_import_grid_phase1_contract_record.md
```

本次没有创建 Git commit，也没有修改或暂存其他文件。
