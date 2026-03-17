# 20260317_122248_unified_editoverlay_crop_handle_rotation_record

## 记录范围

- 记录内容：
  1. 在 `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift` 中，把 `crop` 模式四角方块从轴对齐矩形改为按 `handle.screenRotationRadians` 旋转绘制。
  2. 在 `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift` 中同步完成同样的旋转绘制修改。
  3. 为两个平台提炼 `cropHandlePath(...) + squareHandlePath(...)`，让 `selection` 和 `crop` 共用旋转方块 path 生成逻辑。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
- 本记录不包含：
  - shared renderer / controller 逻辑修改
  - 命中热区逻辑变更
  - 原始 gif diff
  - git commit / push

## 修改一：iOS 中让 `crop` 模式角块按角度旋转绘制

### 修改前

- `refreshCropChrome(from:)` 虽然已经从 `editOverlay.cornerHandles` 读取到了角点位置，但仍用 `cropHandleRect(centeredAt:) + CGPath(rect:)` 画轴对齐矩形。
- 结果是：方块位置会落在旋转后的四个角上，但方块自身不会跟着外框角度一起旋转。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:)
// 功能说明: 修改前 iOS crop handle 仍按轴对齐矩形绘制，只使用角点中心，不消费 handle.screenRotationRadians。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .crop(payload) = editOverlay.payload else {
        hideCropOverlay()
        return
    }

    // 省略与本次修改无关的 mask / outline 逻辑

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
        handleLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}
```

### 修改后

- `refreshCropChrome(from:)` 继续从 `editOverlay.cornerHandles` 读取四个角点，但现在额外消费 `handle.screenRotationRadians`。
- `handleLayer.frame` 统一改为 `bounds`，与 `selection` 模式保持一致，让 path 可以直接在 viewport 坐标系内按旋转角度绘制。
- `crop` 模式的四角方块现在会和 crop outline 一起保持相同角度。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:)
// 功能说明: 修改后 iOS crop handle 直接按 handle.screenRotationRadians 生成旋转方块 path，使方块与 crop 外框保持同角度。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .crop(payload) = editOverlay.payload else {
        hideCropOverlay()
        return
    }

    // 省略与本次修改无关的 mask / outline 逻辑

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.cropHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}
```

## 修改二：iOS 中提炼旋转方块 path helper，复用 `selection` / `crop`

### 修改前

- `crop` 使用独立的 `cropHandleRect(centeredAt:)`。
- `selectionHandlePath(centeredAt:rotationRadians:)` 自己在函数内部完成方块四个角的旋转计算。
- 两套逻辑在“方块大小不同，但旋转算法本质相同”这件事上是重复的。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: cropHandleRect(centeredAt:) / selectionHandlePath(centeredAt:rotationRadians:)
// 功能说明: 修改前 iOS 将 crop 的轴对齐矩形绘制与 selection 的旋转方块绘制拆成两套 helper。
private static func cropHandleRect(centeredAt center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - cropHandleSize / 2,
        y: center.y - cropHandleSize / 2,
        width: cropHandleSize,
        height: cropHandleSize
    ).standardized
}

private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    let halfSize = selectionHandleSize / 2
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let localCorners = [
        CGPoint(x: -halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: halfSize),
        CGPoint(x: -halfSize, y: halfSize)
    ]
    let path = CGMutablePath()

    for (index, localCorner) in localCorners.enumerated() {
        let rotatedCorner = CGPoint(
            x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
            y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
        )
        if index == 0 {
            path.move(to: rotatedCorner)
        } else {
            path.addLine(to: rotatedCorner)
        }
    }

    path.closeSubpath()
    return path
}
```

### 修改后

- 删除 `cropHandleRect(centeredAt:)`。
- 新增 `cropHandlePath(centeredAt:rotationRadians:)`，让 `crop` 也走 path 方案。
- 新增 `squareHandlePath(centeredAt:size:rotationRadians:)`，把旋转方块的几何算法抽成一个共享 helper。
- `selectionHandlePath(...)` 也改为转调 `squareHandlePath(...)`，减少重复实现。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: cropHandlePath(centeredAt:rotationRadians:) / selectionHandlePath(centeredAt:rotationRadians:) / squareHandlePath(centeredAt:size:rotationRadians:)
// 功能说明: 修改后 iOS 统一用 squareHandlePath 生成 selection / crop 的旋转方块 path，仅通过 size 区分两类 handle 尺寸。
private static func cropHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    squareHandlePath(
        centeredAt: center,
        size: cropHandleSize,
        rotationRadians: rotationRadians
    )
}

private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    squareHandlePath(
        centeredAt: center,
        size: selectionHandleSize,
        rotationRadians: rotationRadians
    )
}

private static func squareHandlePath(
    centeredAt center: CGPoint,
    size: CGFloat,
    rotationRadians: CGFloat
) -> CGPath {
    let halfSize = size / 2
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let localCorners = [
        CGPoint(x: -halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: halfSize),
        CGPoint(x: -halfSize, y: halfSize)
    ]
    let path = CGMutablePath()

    for (index, localCorner) in localCorners.enumerated() {
        let rotatedCorner = CGPoint(
            x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
            y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
        )
        if index == 0 {
            path.move(to: rotatedCorner)
        } else {
            path.addLine(to: rotatedCorner)
        }
    }

    path.closeSubpath()
    return path
}
```

## 修改三：在 macOS 中同步让 `crop` 模式角块按角度旋转绘制

### 修改前

- macOS 版本与 iOS 相同：`refreshCropChrome(from:)` 虽然读取的是统一 `editOverlay.cornerHandles`，但仍使用 `cropHandleRect(centeredAt:)` 画轴对齐矩形。
- 结果也是方块中心点落在旋转后的四角上，但方块自身不旋转。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:)
// 功能说明: 修改前 macOS crop handle 与 iOS 一样，仍按轴对齐矩形绘制。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .crop(payload) = editOverlay.payload else {
        hideCropOverlay()
        return
    }

    // 省略与本次修改无关的 mask / outline 逻辑

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        let handleRect = Self.cropHandleRect(centeredAt: handle.screenCenter)
        handleLayer.frame = handleRect
        handleLayer.path = CGPath(
            rect: CGRect(origin: .zero, size: handleRect.size),
            transform: nil
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}
```

### 修改后

- macOS `refreshCropChrome(from:)` 也同步改为直接消费 `handle.screenRotationRadians`。
- `cropHandleLayers` 的 frame 同样改为 `bounds`，让 path 与 viewport 坐标系对齐。
- 两个平台在视觉结果上保持一致：`crop` 模式四角方块现在都会和 outline 一起转动。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: refreshCropChrome(from:)
// 功能说明: 修改后 macOS crop handle 直接按 handle.screenRotationRadians 生成旋转方块 path，与 iOS 行为保持一致。
private func refreshCropChrome(
    from editOverlay: CanvasEditRenderOverlay
) {
    guard case let .crop(payload) = editOverlay.payload else {
        hideCropOverlay()
        return
    }

    // 省略与本次修改无关的 mask / outline 逻辑

    for role in CanvasCropHandleRole.allCases {
        guard
            let handleLayer = cropHandleLayers[role],
            let handle = editOverlay.cornerHandles.first(where: {
                $0.role == Self.editHandleRole(for: role)
            })
        else {
            cropHandleLayers[role]?.path = nil
            cropHandleLayers[role]?.frame = .zero
            cropHandleLayers[role]?.isHidden = true
            continue
        }

        handleLayer.frame = bounds
        handleLayer.path = Self.cropHandlePath(
            centeredAt: handle.screenCenter,
            rotationRadians: handle.screenRotationRadians
        )
        handleLayer.isHidden = false
        handleLayer.contentsScale = currentContentsScale
    }
}
```

## 修改四：在 macOS 中同步提炼旋转方块 path helper

### 修改前

- macOS 也保留着 `cropHandleRect(centeredAt:)`。
- `selectionHandlePath(...)` 独立维护旋转方块的几何计算。
- `crop` 和 `selection` 在方块 path 生成上的实现仍然重复。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: cropHandleRect(centeredAt:) / selectionHandlePath(centeredAt:rotationRadians:)
// 功能说明: 修改前 macOS 仍将 crop 的轴对齐矩形绘制与 selection 的旋转 path 绘制分开实现。
private static func cropHandleRect(centeredAt center: CGPoint) -> CGRect {
    CGRect(
        x: center.x - cropHandleSize / 2,
        y: center.y - cropHandleSize / 2,
        width: cropHandleSize,
        height: cropHandleSize
    ).standardized
}

private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    let halfSize = selectionHandleSize / 2
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let localCorners = [
        CGPoint(x: -halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: halfSize),
        CGPoint(x: -halfSize, y: halfSize)
    ]
    let path = CGMutablePath()

    for (index, localCorner) in localCorners.enumerated() {
        let rotatedCorner = CGPoint(
            x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
            y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
        )
        if index == 0 {
            path.move(to: rotatedCorner)
        } else {
            path.addLine(to: rotatedCorner)
        }
    }

    path.closeSubpath()
    return path
}
```

### 修改后

- macOS 与 iOS 同步删除 `cropHandleRect(centeredAt:)`。
- 新增 `cropHandlePath(...)` 与 `squareHandlePath(...)`。
- `selectionHandlePath(...)` 改为转调共享 helper，后续如果还要统一其它方块风格，只需维护一个方块 path 算法入口。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: cropHandlePath(centeredAt:rotationRadians:) / selectionHandlePath(centeredAt:rotationRadians:) / squareHandlePath(centeredAt:size:rotationRadians:)
// 功能说明: 修改后 macOS 统一通过 squareHandlePath 生成 selection / crop 的旋转方块，减少重复实现。
private static func cropHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    squareHandlePath(
        centeredAt: center,
        size: cropHandleSize,
        rotationRadians: rotationRadians
    )
}

private static func selectionHandlePath(
    centeredAt center: CGPoint,
    rotationRadians: CGFloat
) -> CGPath {
    squareHandlePath(
        centeredAt: center,
        size: selectionHandleSize,
        rotationRadians: rotationRadians
    )
}

private static func squareHandlePath(
    centeredAt center: CGPoint,
    size: CGFloat,
    rotationRadians: CGFloat
) -> CGPath {
    let halfSize = size / 2
    let cosine = cos(rotationRadians)
    let sine = sin(rotationRadians)
    let localCorners = [
        CGPoint(x: -halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: -halfSize),
        CGPoint(x: halfSize, y: halfSize),
        CGPoint(x: -halfSize, y: halfSize)
    ]
    let path = CGMutablePath()

    for (index, localCorner) in localCorners.enumerated() {
        let rotatedCorner = CGPoint(
            x: center.x + (localCorner.x * cosine) - (localCorner.y * sine),
            y: center.y + (localCorner.x * sine) + (localCorner.y * cosine)
        )
        if index == 0 {
            path.move(to: rotatedCorner)
        } else {
            path.addLine(to: rotatedCorner)
        }
    }

    path.closeSubpath()
    return path
}
```

## 验证结果

### 变更范围确认

```bash
# 功能说明: 确认本次视觉修正只落在两个 viewport 文件上
git status --short
```

- 结果：只包含以下两个源码文件修改。
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`

### Lints

- `ReadLints` 检查以下文件后无报错：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`

### 构建验证

```bash
# 功能说明: iOS Simulator Debug 构建验证；沿用工作区内 derivedDataPath 和禁签名参数
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath ".build/ios-sim" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  AD_HOC_CODE_SIGNING_ALLOWED=NO
```

- 结果：`Exit code 0`，构建通过。

```bash
# 功能说明: macOS Debug 构建验证；沿用工作区内 derivedDataPath
"/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild" \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  -derivedDataPath ".build/macos" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

- 结果：`Exit code 0`，构建通过。

## 本次修改结论

- 当前 `crop` 模式四角方块已经和 `selection` 模式一样，既跟随角点位置，也会按外框角度旋转绘制。
- 这次修改只动了 viewport 绘制层，没有改变 controller 的命中热区和交互状态机，因此风险面较小。
- `crop` / `selection` 已在两个平台上共用同类旋转方块 path 逻辑，后续若还要统一 handle 风格，入口已经收口完成。
