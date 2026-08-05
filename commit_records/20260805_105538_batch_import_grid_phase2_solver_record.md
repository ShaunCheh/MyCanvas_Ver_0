# 20260805_105538_batch_import_grid_phase2_solver_record

## 记录范围

本记录如实对应 `batch import grid` 计划的阶段 2：新增纯 `CanvasImportLayoutSolver`，集中解析 automatic、stacked、diagonal、grid 四种导入布局，并一次性产出有效布局、全部 item offsets 和布局内容尺寸。

本记录参考了创建记录前的：

- `git status --short`
- 已跟踪文件的 `git diff`
- 对新增文件执行的 `git diff --no-index`
- 新增文件的实际源码
- 定向测试与编译输出
- IDE lint 结果

下文不粘贴原始 diff，而是根据当前 changes 和新增源码整理修改前后的数据结构、函数与行为。

阶段 2 只创建纯 solver，尚未接入 `CanvasEditorSession.appendImportedMedia(...)`。因此当前用户实际执行批量导入时，仍走 session 内原有对角线逻辑；automatic 网格在阶段 3 接入后才会生效。

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
20260805_105538
```

记录文件名：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0/commit_records
# 功能注释：使用“年月日_时分秒_其他部分”格式命名阶段 2 修改记录。
20260805_105538_batch_import_grid_phase2_solver_record.md
```

## 创建记录前的当前 changes

`git status --short` 的实际结果：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# git status --short 的实际输出
?? MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
```

由于阶段 2 只新增了一个尚未跟踪的文件，普通 `git diff` 和 `git diff --stat` 没有输出。为如实检查新增内容，使用 `git diff --no-index /dev/null <新增文件>`；其统计结果为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 新增文件相对 /dev/null 的实际统计
 .../Canvas/Import/CanvasImportLayoutSolver.swift   | 223 +++++++++++++++++++++
 1 file changed, 223 insertions(+)
```

## 修改前：布局策略和几何计算只存在于 Session

### 没有统一的布局求解结果

修改前不存在 `CanvasResolvedImportLayout`。调用方无法一次获得：

- automatic 最终解析成的有效布局。
- 与全部导入项一一对应的 offsets。
- 整个布局占用的 content size。

`CanvasEditorSession` 先按 item count 解析模式，再在导入循环中按单个 index 查询 offset。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.resolvedImportLayout(_:itemCount:)
// 功能注释：修改前由有副作用的 session 自行决定 automatic 最终布局。
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

### 对角与网格 offset 按单个 index 计算

修改前 `importOffset(...)` 每次只计算一个 item 的位置：

- diagonal 使用 `index × stepInWorld`。
- grid 以第一格为 `(0, 0)`。
- grid 没有计算整体 content size，也没有围绕导入中心对称。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.importOffset(forItemAt:layout:gridCellSize:)
// 功能注释：修改前按单个 index 求 offset；grid 从第一格零点开始向右下扩展。
private func importOffset(
    forItemAt index: Int,
    layout: CanvasImportLayout,
    gridCellSize: CGSize? = nil
) -> CGPoint {
    switch layout {
    case .automatic, .stacked:
        return .zero
    case let .diagonal(stepInWorld):
        let multiplier = CGFloat(index)
        return CGPoint(
            x: stepInWorld.x * multiplier,
            y: stepInWorld.y * multiplier
        )
    case .grid:
        guard
            let gridConfiguration = layout.gridConfiguration,
            let gridCellSize
        else {
            return .zero
        }

        let columnIndex = index % gridConfiguration.columns
        let rowIndex = index / gridConfiguration.columns
        return CGPoint(
            x: CGFloat(columnIndex) * (
                gridCellSize.width + gridConfiguration.horizontalSpacing
            ),
            y: CGFloat(rowIndex) * (
                gridCellSize.height + gridConfiguration.verticalSpacing
            )
        )
    }
}
```

### 网格只提供最大 cell size

修改前 `gridCellSize(...)` 只求最大宽高，没有表达实际列数、行数、pitch 或整体边界。

```swift
// MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数名：CanvasEditorSession.gridCellSize(for:layout:)
// 功能注释：修改前只提供统一 cell 尺寸，不能独立完成整体居中。
private func gridCellSize(
    for preparedItems: [CanvasPreparedImportItem],
    layout: CanvasImportLayout
) -> CGSize? {
    guard layout.gridConfiguration != nil else {
        return nil
    }

    let maxWidth = preparedItems.map(\.size.width).max() ?? 1
    let maxHeight = preparedItems.map(\.size.height).max() ?? 1
    return CGSize(
        width: max(maxWidth, 1),
        height: max(maxHeight, 1)
    )
}
```

## 修改后：新增纯布局结果数据结构

新增 `CanvasResolvedImportLayout`，统一承载一次求解的三个输出：

- `effectiveLayout`：清洗和 automatic 解析后的实际布局。
- `itemOffsets`：严格按输入顺序生成、与输入数量一致的全部偏移。
- `contentSize`：布局占用的整体尺寸。

该结构只存在于导入运行期，不进入 board document、history 或 autosave。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 类型名：CanvasResolvedImportLayout
// 功能注释：保存一次纯布局求解的有效模式、全部 item offsets 和整体 content size。
struct CanvasResolvedImportLayout: Equatable {
    let effectiveLayout: CanvasImportLayout
    let itemOffsets: [CGPoint]
    let contentSize: CGSize
}
```

## 修改后：新增统一求解入口

`CanvasImportLayoutSolver.resolve(...)` 是新增的统一入口：

1. 先清洗每个 item 的 axis-aligned bounding size。
2. 将 `.automatic` 解析成有效布局。
3. 再按 stacked、diagonal 或 grid 生成完整结果。
4. 不读取或修改 scene、camera、history、storage 和 UI 状态。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.resolve(requestedLayout:itemBoundingSizes:automaticConfiguration:)
// 功能注释：纯函数式地解析请求布局，并一次返回全部 offsets 与 content size。
func resolve(
    requestedLayout: CanvasImportLayout,
    itemBoundingSizes: [CGSize],
    automaticConfiguration: CanvasBatchImportLayoutConfiguration = .current
) -> CanvasResolvedImportLayout {
    let sanitizedItemBoundingSizes = itemBoundingSizes.map(
        sanitizedBoundingSize
    )
    let effectiveLayout = resolvedLayout(
        requestedLayout,
        itemCount: sanitizedItemBoundingSizes.count,
        automaticConfiguration: automaticConfiguration
    )

    switch effectiveLayout {
    case .automatic, .stacked:
        return stackedLayout(
            effectiveLayout: .stacked,
            itemBoundingSizes: sanitizedItemBoundingSizes
        )
    case let .diagonal(stepInWorld):
        return diagonalLayout(
            stepInWorld: stepInWorld,
            itemBoundingSizes: sanitizedItemBoundingSizes
        )
    case .grid:
        guard let gridConfiguration = effectiveLayout.gridConfiguration else {
            return stackedLayout(
                effectiveLayout: .stacked,
                itemBoundingSizes: sanitizedItemBoundingSizes
            )
        }

        return gridLayout(
            configuration: gridConfiguration,
            itemBoundingSizes: sanitizedItemBoundingSizes
        )
    }
}
```

计划草案中的示意签名曾包含 `defaultDiagonalStepInWorld` 参数；实际实现没有加入这个冗余参数，因为 `.diagonal(stepInWorld:)` 本身已经完整携带步长。后续 session 如需当前 24 屏幕点效果，应在构造 `.diagonal` 时继续使用 `duplicateOffsetInWorld()`，solver 不应同时接收第二份可能冲突的 step。

## 修改后：automatic 策略固定为单项堆叠、多项网格

`resolvedLayout(...)` 的新规则：

- 空输入和 1 项 `.automatic` 都解析为 `.stacked`。
- 2 项及以上 `.automatic` 使用 `CanvasBatchImportLayoutConfiguration.current.grid`。
- 当前默认配置为 4 列、横纵间距各 24 world units。
- 显式 `.grid` 仍通过 `CanvasImportGridConfiguration` 清洗。
- 显式 `.diagonal` 完整保留请求中的 step。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.resolvedLayout(_:itemCount:automaticConfiguration:)
// 功能注释：把 automatic 解析成稳定的 stacked 或 4 列 grid，并清洗显式 grid 配置。
private func resolvedLayout(
    _ requestedLayout: CanvasImportLayout,
    itemCount: Int,
    automaticConfiguration: CanvasBatchImportLayoutConfiguration
) -> CanvasImportLayout {
    switch requestedLayout {
    case .automatic:
        guard itemCount > 1 else {
            return .stacked
        }

        let gridConfiguration = automaticConfiguration.grid
        return .grid(
            columns: gridConfiguration.columns,
            horizontalSpacing: gridConfiguration.horizontalSpacing,
            verticalSpacing: gridConfiguration.verticalSpacing
        )
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

## 修改后：保留 diagonal 的原始公式

diagonal 继续以输入顺序为准，第 `index` 项使用 `stepInWorld × index`。除了同时生成全部 offsets 和 content size，几何公式没有改变。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.diagonalLayout(stepInWorld:itemBoundingSizes:)
// 功能注释：保留原有对角线公式，并计算所有 item 外包矩形的联合尺寸。
private func diagonalLayout(
    stepInWorld: CGPoint,
    itemBoundingSizes: [CGSize]
) -> CanvasResolvedImportLayout {
    let itemOffsets = itemBoundingSizes.indices.map { index in
        let multiplier = CGFloat(index)
        return CGPoint(
            x: stepInWorld.x * multiplier,
            y: stepInWorld.y * multiplier
        )
    }
    return CanvasResolvedImportLayout(
        effectiveLayout: .diagonal(stepInWorld: stepInWorld),
        itemOffsets: itemOffsets,
        contentSize: contentSize(
            itemBoundingSizes: itemBoundingSizes,
            itemOffsets: itemOffsets
        )
    )
}
```

## 修改后：实现固定列数、自动行数的居中网格

### 网格数量和尺寸

`gridLayout(...)` 的数量规则：

- `usedColumnCount = min(configuredColumns, itemCount)`。
- `rowCount = ((itemCount - 1) / configuredColumns) + 1`。
- item 少于 4 个时，只使用实际列数。
- item 超过 4 个时固定 4 列，自动增加行。
- 最后一行从 column 0 开始，不单独居中。

cell 使用所有 `itemBoundingSizes` 的最大宽度和最大高度，确保不同宽高比或旋转后外包尺寸可以放进同一个 cell。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.gridLayout(configuration:itemBoundingSizes:)
// 功能注释：根据固定列数推导实际列数、自动行数、统一 cell 与完整网格尺寸。
let cellSize = maximumBoundingSize(in: itemBoundingSizes)
let itemCount = itemBoundingSizes.count
let usedColumnCount = min(configuration.columns, itemCount)
let rowCount = ((itemCount - 1) / configuration.columns) + 1
let horizontalPitch =
    cellSize.width + configuration.horizontalSpacing
let verticalPitch =
    cellSize.height + configuration.verticalSpacing
let contentSize = CGSize(
    width: CGFloat(usedColumnCount) * cellSize.width
        + CGFloat(usedColumnCount - 1)
        * configuration.horizontalSpacing,
    height: CGFloat(rowCount) * cellSize.height
        + CGFloat(rowCount - 1)
        * configuration.verticalSpacing
)
```

### 整体居中与行列顺序

第一格中心从完整 `contentSize` 的左上 cell 中心推导。完整网格外框围绕 `(0, 0)` 居中；调用方后续只需把导入中心加到每个 offset 上。

最后一行不足 4 项时仍从左到右填充，不改变输入顺序。由于末行明确左对齐，实际存在的 item offsets 在末行不满时不会关于原点完全对称；居中的是按完整列宽计算的网格外框。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.gridLayout(configuration:itemBoundingSizes:)
// 功能注释：以完整网格中心为原点，按 row-major 顺序生成与输入一一对应的 offsets。
let firstCellCenter = CGPoint(
    x: (-contentSize.width + cellSize.width) / 2,
    y: (-contentSize.height + cellSize.height) / 2
)
let itemOffsets = itemBoundingSizes.indices.map { index in
    let columnIndex = index % configuration.columns
    let rowIndex = index / configuration.columns
    return CGPoint(
        x: firstCellCenter.x
            + CGFloat(columnIndex) * horizontalPitch,
        y: firstCellCenter.y
            + CGFloat(rowIndex) * verticalPitch
    )
}
```

### 空显式 grid

显式 grid 接收到空数组时，不执行 `itemCount - 1` 计算，直接返回：

- 已清洗的有效 grid。
- 空 offsets。
- `.zero` content size。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.gridLayout(configuration:itemBoundingSizes:)
// 功能注释：为空输入提供确定结果，并避免行数公式出现负数。
guard itemBoundingSizes.isEmpty == false else {
    return CanvasResolvedImportLayout(
        effectiveLayout: .grid(
            columns: configuration.columns,
            horizontalSpacing: configuration.horizontalSpacing,
            verticalSpacing: configuration.verticalSpacing
        ),
        itemOffsets: [],
        contentSize: .zero
    )
}
```

## 修改后：集中清洗尺寸并计算内容边界

传入 solver 的尺寸语义为“已经考虑 rotation 的 axis-aligned bounding size”。阶段 2 负责数值清洗：

- 有限且大于等于 1 的维度原样保留。
- 0、负数、NaN 和 infinity 回退为 1。
- 空数组的最大尺寸为 `.zero`。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.sanitizedBoundingSize(_:) / sanitizedDimension(_:)
// 功能注释：阻止非法或退化尺寸进入 pitch、content size 和 CGRect 联合运算。
private func sanitizedBoundingSize(_ size: CGSize) -> CGSize {
    CGSize(
        width: sanitizedDimension(size.width),
        height: sanitizedDimension(size.height)
    )
}

private func sanitizedDimension(_ dimension: CGFloat) -> CGFloat {
    dimension.isFinite ? max(dimension, 1) : 1
}
```

stacked 的 content size 使用最大 item bounding size；diagonal 的 content size 使用全部 item rect 的 union；grid 的 content size 使用完整 cell 网格尺寸。

```swift
// MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
// 函数名：CanvasImportLayoutSolver.contentSize(itemBoundingSizes:itemOffsets:)
// 功能注释：根据 item 中心偏移和外包尺寸计算 diagonal 的联合边界尺寸。
private func contentSize(
    itemBoundingSizes: [CGSize],
    itemOffsets: [CGPoint]
) -> CGSize {
    let contentBounds = zip(
        itemBoundingSizes,
        itemOffsets
    ).reduce(into: CGRect.null) { partialResult, item in
        let (size, offset) = item
        partialResult = partialResult.union(
            CGRect(
                x: offset.x - size.width / 2,
                y: offset.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        )
    }
    return contentBounds.isNull
        ? .zero
        : contentBounds.standardized.size
}
```

## 实际行为边界

阶段 2 新增的是纯计算能力：

- solver 本身已经将多项 `.automatic` 解析为 4 列 grid。
- solver 本身已经生成居中的 row-major 网格 offsets。
- solver 支持无限行数，不保存独立的 row 配置。
- solver 支持 explicit stacked、diagonal 和自定义 grid。
- solver 不依赖 UIKit、AppKit、CanvasScene、CanvasCamera 或存储层。

但当前运行链路尚未调用 solver：

- `CanvasEditorSession.appendImportedMedia(...)` 仍调用旧 `resolvedImportLayout(...)`、`gridCellSize(...)` 和 `importOffset(...)`。
- 当前 UI 中的多项 `.automatic` 仍表现为 diagonal。
- 当前显式 GIF grid 的首格锚点尚未改变。
- session 接入和旧 helper 删除属于阶段 3。

## 自动验证

### 定向编译与模型测试

执行命令：

```shell
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：编译包含新增 solver 的完整 macOS 测试目标，并运行现有导入模型测试。
xcodebuild test -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests"
```

实际结果：

- 命令退出码为 `0`。
- 输出包含 `SwiftCompile ... CanvasImportLayoutSolver.swift`，确认新增文件已加入 `MyCanvas_Ver_0` target。
- `TEST SUCCEEDED`。
- `CanvasImportRequestModelTests` 的 5 个测试全部通过。

构建日志仍包含项目既有的 Swift 6 actor-isolation、最低 macOS 版本和 AppIntents metadata warnings；没有 warning 或 error 指向新增 `CanvasImportLayoutSolver.swift`。

### IDE 诊断

检查文件：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 功能注释：阶段 2 IDE lint 检查范围。
MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
```

实际结果：`No linter errors found.`。

阶段 2 没有提前新增 `CanvasImportLayoutSolverTests.swift`；完整 automatic、grid、diagonal、边界尺寸测试矩阵仍按计划留在阶段 5。

## 明确未修改的范围

- 未修改 `CanvasEditorSession.swift`。
- 未接入 `appendImportedMedia(...)`。
- 未删除 session 内旧布局 helper。
- 未修改 `CanvasImportTypes.swift` 或阶段 1 配置。
- 未修改 GIF 帧 builder。
- 未修改 iOS、macOS、分享扩展入口。
- 未修改 history、autosave、storage 或文档格式。
- 未修改 `.cursor/plans/batch_import_grid_fc6b804f.plan.md`。

## 当前状态

创建本记录后，预期 `git status --short` 为：

```text
# /Users/shaun/cloudDev/MyCanvas_Ver_0
# 创建记录后的预期工作区状态
?? MyCanvas_Ver_0/Canvas/Import/CanvasImportLayoutSolver.swift
?? commit_records/20260805_105538_batch_import_grid_phase2_solver_record.md
```

本次没有创建 Git commit，也没有修改或暂存其他文件。
