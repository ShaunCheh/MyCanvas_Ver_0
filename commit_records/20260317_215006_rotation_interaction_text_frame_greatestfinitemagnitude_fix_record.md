# 20260317_215006_rotation_interaction_text_frame_greatestfinitemagnitude_fix_record

## 记录范围

- 记录内容：修复旋转角度 HUD 文本排版代码里的 `greatestFiniteMagnitude` 类型推断歧义。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
- 本次记录只覆盖刚刚这一轮修复，不包含前序阶段 1~5 的主体实现。

## 问题现象

- macOS 编译报错：
  - `/Users/shaun/Library/Mobile Documents/com~apple~CloudDocs/Develop/MyCanvas_Ver_0/MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift:688:25 Ambiguous use of 'greatestFiniteMagnitude'`
- 报错位置位于 `rotationTextFrame(for:anchoredAt:)` 中给 `CGSize` 传入最大尺寸的地方。

## 根因分析

- 原实现写法是：
  - `CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)`
- 这里使用了前导点语法，但在该上下文中编译器没有拿到足够稳定的类型约束，导致 `macOS` 侧对 `.greatestFiniteMagnitude` 的静态成员解析出现歧义。
- 由于这段逻辑在 iOS 和 macOS 两端是镜像实现，因此本次修复直接统一改成显式类型：
  - `CGFloat.greatestFiniteMagnitude`
- 这样不是只压住单端报错，而是从根因上消除同类推断风险。

## 修改一：macOS 显式指定 `CGFloat.greatestFiniteMagnitude`

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: rotationTextFrame(for:anchoredAt:)
// 功能说明: 修改前使用前导点语法传入极大尺寸，依赖编译器从上下文推断 `.greatestFiniteMagnitude` 的具体类型。
private static func rotationTextFrame(
    for attributedText: NSAttributedString,
    anchoredAt anchor: CGPoint
) -> CGRect {
    let textBounds = attributedText.boundingRect(
        with: CGSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral

    return CGRect(
        x: anchor.x - (textBounds.width / 2),
        y: anchor.y - (textBounds.height / 2),
        width: textBounds.width,
        height: textBounds.height
    ).integral
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift
// 函数名: rotationTextFrame(for:anchoredAt:)
// 功能说明: 修改后显式使用 `CGFloat.greatestFiniteMagnitude`，避免 `CGSize` 参数上的静态成员解析歧义。
private static func rotationTextFrame(
    for attributedText: NSAttributedString,
    anchoredAt anchor: CGPoint
) -> CGRect {
    let textBounds = attributedText.boundingRect(
        with: CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral

    return CGRect(
        x: anchor.x - (textBounds.width / 2),
        y: anchor.y - (textBounds.height / 2),
        width: textBounds.width,
        height: textBounds.height
    ).integral
}
```

## 修改二：iOS 同步做同样的显式类型修复

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: rotationTextFrame(for:anchoredAt:)
// 功能说明: 修改前 iOS 端和 macOS 端保持同样写法，也依赖上下文推断 `.greatestFiniteMagnitude` 的类型。
private static func rotationTextFrame(
    for attributedText: NSAttributedString,
    anchoredAt anchor: CGPoint
) -> CGRect {
    let textBounds = attributedText.boundingRect(
        with: CGSize(
            width: .greatestFiniteMagnitude,
            height: .greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral

    return CGRect(
        x: anchor.x - (textBounds.width / 2),
        y: anchor.y - (textBounds.height / 2),
        width: textBounds.width,
        height: textBounds.height
    ).integral
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift
// 函数名: rotationTextFrame(for:anchoredAt:)
// 功能说明: 修改后 iOS 也统一使用 `CGFloat.greatestFiniteMagnitude`，保持双端实现一致并提前规避同类问题。
private static func rotationTextFrame(
    for attributedText: NSAttributedString,
    anchoredAt anchor: CGPoint
) -> CGRect {
    let textBounds = attributedText.boundingRect(
        with: CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        ),
        options: [
            .usesLineFragmentOrigin,
            .usesFontLeading
        ],
        context: nil
    ).integral

    return CGRect(
        x: anchor.x - (textBounds.width / 2),
        y: anchor.y - (textBounds.height / 2),
        width: textBounds.width,
        height: textBounds.height
    ).integral
}
```

## 修改结果

- `macOS` 侧的 `Ambiguous use of 'greatestFiniteMagnitude'` 已从代码层规避。
- iOS / macOS 在 `rotationTextFrame(for:anchoredAt:)` 上重新恢复为完全镜像实现。
- 文本排版逻辑本身没有变化，本次只修正了类型表达方式，不改变 HUD 文本的显示行为。

## 校验结果

- 已重新检查以下文件，当前未发现新增 lint 问题：
  - `MyCanvas_Ver_0/Platform/macOS/Canvas/macOSCanvasViewportView.swift`
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasViewportView.swift`
