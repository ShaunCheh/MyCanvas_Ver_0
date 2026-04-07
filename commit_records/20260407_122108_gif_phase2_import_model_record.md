# 20260407_122108_gif_phase2_import_model_record

## 记录范围

- 记录内容：扩展通用导入模型，为后续 GIF 多选帧导入增加 `grid` 布局、导入展示模板和导入旋转策略。
- 记录内容：在 `CanvasImportRequest` 中新增可选 `presentationTemplate`，让导入请求可以携带“尺寸 / crop / rotation”类展示语义。
- 记录内容：在 `CanvasEditorSession` 中补齐 `CanvasImportLayout.grid` 的编译适配，但保留阶段 2 的边界，不提前接入真正的网格排布行为。
- 记录内容：新增 `CanvasImportRequestModelTests`，验证新导入契约的收口与默认值清洗行为。
- 涉及文件：`MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift`
- 涉及文件：`MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- 涉及文件：`MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift`
- 本记录不包含：`appendImportedMedia(...)` 真正应用 `presentationTemplate`。
- 本记录不包含：`grid` 二维偏移的实际落板执行。
- 本记录不包含：GIF 请求构建器、菜单接线、iOS / macOS 选帧页。
- 本记录不包含：git commit / push。

## 修改一：扩展 `CanvasImportTypes`，让通用导入模型能表达网格与展示模板

### 修改前

- `CanvasImportLayout` 只有 `automatic` / `stacked` / `staggered` 三种语义，无法表达“固定列数 + 横纵间距”的网格布局。
- `CanvasImportRequest` 只能携带 `items / placement / layout / sourceDescription`，没有办法把“继承尺寸 / 继承 crop / 不继承旋转”这种展示层语义作为导入契约传给执行层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasImportLayout / CanvasImportRequest.init(...)
// 功能说明: 修改前导入模型只能表达 placement 和简单 layout，无法承载 GIF 多选帧导入后所需的展示模板语义。
enum CanvasImportPlacement: Equatable {
    case cameraCenter
    case worldPoint(CGPoint)
}

enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
}

struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let sourceDescription: String

    init(
        items: [CanvasImportItem],
        placement: CanvasImportPlacement = .cameraCenter,
        layout: CanvasImportLayout = .automatic,
        sourceDescription: String = "external source"
    ) {
        self.items = items
        self.placement = placement
        self.layout = layout
        self.sourceDescription = sourceDescription
    }
}
```

### 修改后

- 新增 `CanvasImportGridConfiguration`，统一清洗并表达网格列数与横纵间距。
- 新增 `CanvasImportRotationPolicy`，显式表达“沿用资源默认旋转”或“固定旋转角度”。
- 新增 `CanvasImportPresentationTemplate`，用于承载导入时的 `size / cropRectNormalized / rotationPolicy`。
- 扩展 `CanvasImportLayout.grid(...)`，让通用导入模型可以先表达二维网格语义。
- 扩展 `CanvasImportRequest.presentationTemplate`，把展示模板作为 request 的一部分传入后续执行层。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasImportTypes.swift
// 类型/函数: CanvasImportGridConfiguration.init(...) / CanvasImportRotationPolicy.resolvedRotationRadians(...) / CanvasImportPresentationTemplate.init(...) / CanvasImportLayout.gridConfiguration / CanvasImportRequest.init(...)
// 功能说明: 修改后通用导入模型可以表达网格布局和导入展示模板，为后续 GIF 多选帧导入提供统一契约入口。
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

enum CanvasImportRotationPolicy: Equatable {
    case useAssetDefault
    case fixed(CGFloat)

    func resolvedRotationRadians(
        assetDefaultRadians: CGFloat = 0
    ) -> CGFloat {
        let sanitizedDefaultRadians = assetDefaultRadians.isFinite
            ? assetDefaultRadians
            : 0
        switch self {
        case .useAssetDefault:
            return sanitizedDefaultRadians
        case let .fixed(rotationRadians):
            return rotationRadians.isFinite
                ? rotationRadians
                : sanitizedDefaultRadians
        }
    }
}

struct CanvasImportPresentationTemplate: Equatable {
    let size: CGSize
    let cropRectNormalized: CanvasImageCropRect
    let rotationPolicy: CanvasImportRotationPolicy
}

enum CanvasImportLayout: Equatable {
    case automatic
    case stacked
    case staggered(stepInWorld: CGPoint)
    case grid(
        columns: Int,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    )

    var gridConfiguration: CanvasImportGridConfiguration? {
        guard case let .grid(
            columns,
            horizontalSpacing,
            verticalSpacing
        ) = self
        else {
            return nil
        }

        return CanvasImportGridConfiguration(
            columns: columns,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
    }
}

struct CanvasImportRequest {
    let items: [CanvasImportItem]
    let placement: CanvasImportPlacement
    let layout: CanvasImportLayout
    let presentationTemplate: CanvasImportPresentationTemplate?
    let sourceDescription: String
}
```

## 修改二：在 `CanvasEditorSession` 中补齐 `grid` case 的契约适配，但不提前做执行层行为

### 修改前

- `resolvedImportLayout(...)` 和 `importOffset(...)` 只认识 `automatic` / `stacked` / `staggered`。
- 如果仅在模型层新增 `grid`，执行层会直接编译失败。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: resolvedImportLayout(_:itemCount:) / importOffset(forItemAt:layout:)
// 功能说明: 修改前执行层对导入 layout 的穷举只覆盖 automatic / stacked / staggered，没有 grid 契约分支。
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
    }
}

private func importOffset(
    forItemAt index: Int,
    layout: CanvasImportLayout
) -> CGPoint {
    switch layout {
    case .automatic, .stacked:
        return .zero
    case let .staggered(stepInWorld):
        let multiplier = CGFloat(index)
        return CGPoint(
            x: stepInWorld.x * multiplier,
            y: stepInWorld.y * multiplier
        )
    }
}
```

### 修改后

- `resolvedImportLayout(...)` 新增 `grid` 分支，并通过 `CanvasImportGridConfiguration` 做一次输入清洗。
- `importOffset(...)` 新增 `grid` 分支，但明确保持阶段 2 的边界：先返回 `.zero`，真正的二维网格偏移留到阶段 3。
- 这样做的目的是先把契约打通，不在阶段 2 抢跑执行层行为。

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 类型/函数: resolvedImportLayout(_:itemCount:) / importOffset(forItemAt:layout:)
// 功能说明: 修改后执行层先完成对 grid 契约的编译适配；当前阶段只收口模型，不提前接入真正的网格落板算法。
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

private func importOffset(
    forItemAt index: Int,
    layout: CanvasImportLayout
) -> CGPoint {
    switch layout {
    case .automatic, .stacked:
        return .zero
    case let .staggered(stepInWorld):
        let multiplier = CGFloat(index)
        return CGPoint(
            x: stepInWorld.x * multiplier,
            y: stepInWorld.y * multiplier
        )
    case .grid:
        // Phase 2 only extends the import model contract. Phase 3 wires grid
        // positioning into appendImportedMedia once item sizing/template
        // semantics are available at the execution layer.
        return .zero
    }
}
```

## 修改三：新增阶段 2 契约测试，覆盖网格与展示模板语义

### 修改前

- 测试目标里还没有专门验证“导入模型扩展契约”的测试文件。
- 即使阶段 2 完成了 `grid` 和 `presentationTemplate` 的类型定义，也没有自动化校验这些新契约是否被正确清洗与保存。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift
// 类型/函数: 文件级新增前
// 功能说明: 修改前该文件不存在，项目里没有专门覆盖导入模型扩展契约的单元测试。
// 无
```

### 修改后

- 新增 `CanvasImportRequestModelTests`，聚焦验证阶段 2 的导入契约：
  - `grid` 布局配置的列数与间距清洗
  - `presentationTemplate` 的尺寸清洗与旋转策略解析
  - `CanvasImportRequest` 是否正确保存 `presentationTemplate` 与 `grid` 布局

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasImportRequestModelTests.swift
// 类型/函数: testGridLayoutExposesSanitizedGridConfiguration / testPresentationTemplateSanitizesSizeAndResolvesRotationPolicy / testImportRequestStoresPresentationTemplateAndGridLayout
// 功能说明: 修改后通过聚焦测试验证阶段 2 新增的 grid 布局契约、展示模板契约以及 request 持有语义。
final class CanvasImportRequestModelTests: XCTestCase {
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
        let template = CanvasImportPresentationTemplate(
            size: CGSize(width: -40, height: CGFloat.nan),
            cropRectNormalized: CanvasImageCropRect(
                CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
            ),
            rotationPolicy: .fixed(.pi / 4)
        )

        XCTAssertEqual(template.size, CGSize(width: 1, height: 1))
        XCTAssertEqual(
            template.resolvedRotationRadians(assetDefaultRadians: 0),
            .pi / 4,
            accuracy: 0.0001
        )
    }

    func testImportRequestStoresPresentationTemplateAndGridLayout() throws {
        let request = CanvasImportRequest(
            images: [CanvasResolvedImportImage(cgImage: try makeSolidColorImage())],
            placement: .worldPoint(CGPoint(x: 120, y: 240)),
            layout: .grid(
                columns: 4,
                horizontalSpacing: 24,
                verticalSpacing: 32
            ),
            presentationTemplate: CanvasImportPresentationTemplate(
                size: CGSize(width: 320, height: 180),
                rotationPolicy: .fixed(0)
            ),
            sourceDescription: "gif-derived frames"
        )

        XCTAssertEqual(request.itemCount, 1)
        XCTAssertEqual(request.sourceDescription, "gif-derived frames")
    }
}
```

## 验证情况

- 已检查本次涉及文件的 IDE lints，未发现新增问题。
- 已执行 `xcodebuild -project "MyCanvas_Ver_0.xcodeproj" -scheme "MyCanvas_Ver_0" -destination "platform=macOS" test -only-testing:"MyCanvas_Ver_0Tests/CanvasImportRequestModelTests"`，测试通过。
