---
name: BoardList占位项计划
overview: 在不污染 `BoardCatalogItem`、缩略图缓存和预览渲染链的前提下，为双端 `BoardList` 增加固定首位的 `New Board` 占位项，移除 `Open Board` 按钮，并采用平台原生打开交互：iOS 单击打开已有画板，macOS 单击选中 / 双击打开已有画板。计划优先先拆出 UI entry 层和 controller 状态机，再落样式和交互，避免后续返工。
todos:
  - id: phase1-entry-model
    content: 新增 shared 的 BoardListEntry / BoardListEntryID，建立 placeholder 与真实 board 的 UI 语义分层
    status: pending
  - id: phase2-controller-state
    content: 改造双端 BoardList controller：移除 Open Board 按钮，切换到 entry 驱动的选择、可见性和主动作逻辑
    status: pending
  - id: phase3-cell-style
    content: 改造双端 collection item/cell，落地 Grid 空卡片与 List 空行的 New Board 样式
    status: pending
  - id: phase4-interaction-preview
    content: 接入占位项点击创建与真实 board 打开交互，并隔离 placeholder 与 thumbnail pipeline
    status: pending
  - id: phase5-verify-copy
    content: 统一文案、空状态和回归验证场景
    status: pending
isProject: false
---

# BoardList New Board 占位项分阶段计划

## 核心决策

- 占位项固定排在第一个，文案固定为 `New Board`。
- `Grid` 模式下显示为空心矩形卡片，只保留图标和标题。
- `List` 模式下显示为空行，只保留图标和标题。
- 去掉页头里的 `Open Board` 按钮。
- 交互采用平台原生方式：iOS 单击已有画板即打开；macOS 单击选中、双击已有画板打开；占位项单击即创建。
- 占位项不能伪装成真实 `BoardCatalogItem`，必须新增 UI entry 层，否则会污染 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift)、[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailCache.swift)、[MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardThumbnailRenderer.swift) 的真实 board 假设。

## 当前关键落点

- 双端 controller 当前都以真实 board 数组驱动：`availableBoards`、`selectedBoardID`、`selectedBoard`、`reloadBoardList()`，对应文件是 [MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift) 和 [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift)。
- `updateCollectionVisibility()` 目前直接依赖 `!availableBoards.isEmpty`，这会在“0 个真实画板 + 1 个占位项”场景下把 collection 错误隐藏掉。
- `actionStackView` 当前仍然包含 `openCanvasButton`，按钮状态由 `updateOpenCanvasButtonState()` 控制；这一整条链需要拆掉。
- 双端 cell/item 当前都假设自己展示的是一个真实 board，并在 [MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift) 与 [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift) 里直接绑定 title、preview、thumbnail request token。
- iOS 当前 `collectionView(_:didSelectItemAt:)` 只同步 `selectedBoardID`，不负责打开；去掉按钮后必须补齐直接打开已有画板的路径。

## 阶段 1：新增 UI Entry 层，隔离 placeholder 与真实 board

目标：在 shared 层增加只面向 BoardList UI 的 entry 模型，把“真实 board 数据”和“占位项语义”彻底分开。

- 新增 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListEntry.swift)
  - 建议包含：`BoardListEntryID` 和 `BoardListEntry`
  - `BoardListEntryID`：`.newBoard`、`.board(UUID)`
  - `BoardListEntry`：`.newBoardPlaceholder`、`.board(BoardCatalogItem)`
- 保持 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardCatalogLoader.swift) 不变，继续只输出真实 `[BoardCatalogItem]`。
- 在 controller 侧新增 `entries = [.newBoardPlaceholder] + availableBoards.map { .board($0) }` 的组装逻辑，而不是改 storage / catalog 层排序。
- 如需减少双端样式分支判断，可在同文件里附带轻量派生属性：`title`、`isPlaceholder`、`boardID`、`canRequestPreview`。

交付标准：可以在不触碰 `BoardPreviewProvider` / `BoardThumbnailRenderer` 的前提下，把 collection 数据源切到 `BoardListEntry`。

## 阶段 2：重构双端 controller 状态机，移除 Open Board 按钮

目标：把当前围绕 `selectedBoardID` 和 `Open Board` 按钮展开的状态机，重构成“entry 驱动 + item 直接触发主动作”的状态机。

- 改造 [MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift)
  - `selectedBoardID` -> `selectedEntryID`
  - `selectedBoard` -> `selectedEntry`
  - 新增 `entry(at:)` / `performPrimaryAction(for:)`
  - `numberOfItemsInSection` / `itemForRepresentedObjectAt` 改为基于 `entries.count`
  - `ensureValidSelection()`、`reloadBoardList()`、`syncCollectionSelection()` 改为 placeholder-aware
  - 删除 `openCanvasButton`、`updateOpenCanvasButtonState()`、`handleOpenCanvasButtonClick()`
  - `actionStackView` 只保留 `Select Folder` + `Grid/List`
- 同步改造 [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift)
  - 同样切到 `selectedEntryID`
  - 删除 `openCanvasButton` 相关状态与点击处理
  - 为 iOS 增加“单击真实 board 即打开”的主动作路径
- `updateCollectionVisibility()` 改成：
  - 未选 folder：隐藏 collection，显示选择目录提示
  - storage error：隐藏 collection，显示错误提示
  - 已选 folder 且 storage 正常：始终显示 collection，因为至少有 `New Board` 占位项
- `updateDisplayModeControlState()` 改成不再依赖 `!availableBoards.isEmpty`，而是依赖“是否已选 folder 且 storage 正常”。
- [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardListHeaderState.swift) 的 `boardCount` 继续只统计真实 boards，不把 placeholder 算进去。

交付标准：去掉 `Open Board` 后，controller 仍能稳定驱动 collection、header、空状态和选择逻辑，不会因为“首项是 placeholder”而误触创建。

## 阶段 3：改造双端 cell/item，落地占位项样式

目标：在保持现有 grid/list 布局骨架的基础上，为 placeholder 提供明确的创建入口样式，并保证和真实 board 明显区分。

- 改造 [MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardCollectionItem.swift)
  - `configure(...)` 从“只接真实 board”升级为“接 entry 或 entry presentation”
  - 为 placeholder 新增图标视图和必要的布局分支
  - `Grid`：复用当前 card 容器和 preview 区尺寸，显示空心壳层 + 居中 `+` 图标 + `New Board`
  - `List`：改成空行样式，不显示真实 board preview 的 72x72 语义，而是行级 icon + 文案
  - `prepareForReuse()` 必须重置 placeholder 的隐藏状态、图标、颜色、约束和 request token
- 同步改造 [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardCollectionViewCell.swift)
  - 保持与 macOS 同一语义
- 当前 preview 壳层仍可复用 [MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardPreviewView.swift) 和 [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardPreviewView.swift) 提供的圆角、边框、背景，但 placeholder 不进入真实 preview 渲染链。
- 不建议把 placeholder 样式塞进 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewContent.swift) 或 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewRenderer.swift)。这两层继续只表达真实 board 的 `.empty` / `.geometry` / `.thumbnail`。

交付标准：双端 `Grid` 和 `List` 模式下，`New Board` 一眼可识别为“创建入口”，且不会和“真实但内容为空的画板”混淆。

## 阶段 4：接入交互动作，并隔离 placeholder 与预览/缓存链

目标：让占位项只承担创建行为，真实 board 继续承担打开与预览行为，避免两个分支互相污染。

- controller 的主动作统一收口成 `performPrimaryAction(for entry:)`
  - `.newBoardPlaceholder` -> `onCreateBoard?()`
  - `.board(item)` -> iOS 直接 `onOpenBoard?(item.boardID)`；macOS 保留双击打开
- macOS 交互建议：
  - 单击真实 board：仅选中
  - 双击真实 board：打开
  - 单击 placeholder：立即创建，不再复用 `selectedBoardID + openSelectedBoardIfNeeded()` 旧路径
- iOS 交互建议：
  - 单击真实 board：直接打开
  - 单击 placeholder：直接创建
- 真实 board 继续走 [MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift](MyCanvas_Ver_0/Platform/Shared/BoardList/BoardPreviewProvider.swift) 的同步几何预览 + 异步缩略图回填。
- placeholder 必须跳过：
  - `targetThumbnailPixelSize(...)`
  - `requestThumbnail(...)`
  - `representedBoardID` / `representedRevisionToken` 校验链
- [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift) 的 `didEndDisplaying` 保持对真实 board cell 的取消逻辑；placeholder 分支应是 no-op。

交付标准：点击占位项只创建，点击/双击真实 board 只打开，thumbnail pipeline 不会对 placeholder 做无效请求。

## 阶段 5：统一文案、空状态与回归验证

目标：消除 `Open Board` 按钮移除后遗留的文案冲突，并覆盖关键场景回归。

- 调整 subtitle 与 empty state 文案
  - 当前 `Select a storage folder, then open the canvas.` 改为更中性的“浏览或创建画板”语义
  - “已选 folder 但 0 boards”时，不再显示 `No boards yet. Create one to get started.`，因为 placeholder 本身已经是 CTA
  - “未选 folder”与 “storage error” 文案保留原有职责
- 检查 [MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/macOS/BoardList/macOSBoardListViewController.swift) 和 [MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift](MyCanvas_Ver_0/Platform/iOS/BoardList/iOSBoardListViewController.swift) 中所有依赖 `availableBoards.isEmpty` 的分支，区分“真实 board 数”为 0 与“可见 entry 数”为 1。
- 手测回归场景：
  - 未选 folder
  - bookmark 失效 / storage error
  - 0 个真实 boards，只显示 `New Board`
  - 有多个真实 boards，placeholder 仍固定第一个
  - `Grid / List` 切换
  - iOS 单击真实 board 打开
  - macOS 单击 placeholder 创建 / 双击真实 board 打开
  - 缩略图滚动复用下不串图
  - header 的 board 数不包含 placeholder

交付标准：去掉按钮后，BoardList 在“无板 / 有板 / 错误态 / 双端不同交互”下都能保持一致体验。

## 实施顺序建议

1. 先做 shared `BoardListEntry`，不要先改 cell 样式。
2. 再改双端 controller，把 `Open Board` 按钮和旧选择链拆掉。
3. 然后做双端 cell/item 的 placeholder 样式与复用重置。
4. 再把平台交互接进去，并隔离 placeholder 与 thumbnail 请求。
5. 最后统一文案和做整体验证。

这样可以把风险最大的部分先收口：数据语义和 controller 状态机，而不是一开始就在 UI 层硬补分支。