# 20260317_220714_ios_canvas_chrome_coder_initializer_fix_record

## 记录范围

- 记录内容：补充记录刚刚围绕 `iOSCanvasChromeOverlayView.swift` 做的两个初始化器修复。
- 涉及源码文件：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift`
- 本次记录覆盖的两个连续修改：
  1. 修复 `Only a failable initializer can return 'nil'`
  2. 修复 `Failable initializer 'init(coder:)' cannot override a non-failable initializer`

## 问题背景

- 这两个报错都发生在同一个文件中，根因都和 `coder` 初始化器签名不匹配有关。
- 第一个报错先暴露出“非可失败初始化器直接 `return nil`”的问题。
- 第二个报错继续暴露出“`UIStackView` 父类的 `init(coder:)` 本身就是非可失败初始化器，不能被子类改成可失败版本”的问题。
- 因此，这次记录需要分两段如实说明：
  - 第一段是第一次编译错误对应的修正
  - 第二段是继续收口到根因后的最终实现

## 修改一：先修复 `UIStackView` 非可失败初始化器直接 `return nil` 的编译错误

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名: iOSCanvasChromeStackView.required init(coder:)
// 功能说明: 修改前这里使用的是非可失败初始化器，但实现中直接 `return nil`，会触发编译器报错。
final class iOSCanvasChromeStackView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init(coder: NSCoder) {
        return nil
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名: iOSCanvasChromeStackView.required init?(coder:)
// 功能说明: 第一次修复先把初始化器改成可失败签名，让 `return nil` 与当前实现语义一致，从而消除第一处报错。
final class iOSCanvasChromeStackView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        return nil
    }
}
```

## 修改二：继续按父类初始化器约束收口，统一改为不可用的 `coder` 初始化器

### 修改前

- 在第一轮修复后，`iOSCanvasChromeStackView` 虽然不再直接触发“只有可失败初始化器才能 `return nil`”的报错，但又暴露出新的编译问题：
  - `Failable initializer 'init(coder:)' cannot override a non-failable initializer`
- 这说明真正的根因不是“要不要 `return nil`”，而是：
  - `iOSCanvasChromeStackView` 继承自 `UIStackView`
  - `UIStackView` 的 `init(coder:)` 是非可失败初始化器
  - 对这种纯代码创建的 view，应该显式声明 `coder` 路径不可用，而不是继续围绕 `nil` 打补丁

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名: iOSCanvasChromeOverlayView.required init?(coder:) /
//        iOSCanvasChromeStackView.required init?(coder:)
// 功能说明: 修改前两个类都仍然使用 `return nil` 的 coder 初始化器；其中 stack view 与 UIStackView 的父类签名约束不一致。
final class iOSCanvasChromeOverlayView: UIView {
    required init?(coder: NSCoder) {
        return nil
    }
}

final class iOSCanvasChromeStackView: UIStackView {
    required init?(coder: NSCoder) {
        return nil
    }
}
```

### 修改后

- `iOSCanvasChromeOverlayView`：
  - 保持与 `UIView` 父类一致的可失败签名
  - 但显式标记 `@available(*, unavailable)`
  - 在运行期用 `fatalError` 明确阻止 nib / storyboard 路径
- `iOSCanvasChromeStackView`：
  - 改回与 `UIStackView` 父类一致的非可失败签名
  - 同样显式标记为不可用并使用 `fatalError`
- 这样修的是根因：这些类就是纯代码创建，不应该允许 `coder` 初始化路径。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift
// 函数名: iOSCanvasChromeOverlayView.required init?(coder:) /
//        iOSCanvasChromeStackView.required init(coder:)
// 功能说明: 修改后统一把 coder 初始化器标记为不可用，既满足 UIView/UIStackView 的父类签名约束，也明确表达“这些类只能代码创建”。
final class iOSCanvasChromeOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class iOSCanvasChromeStackView: UIStackView {
    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
```

## 最终结果

1. `iOSCanvasChromeStackView` 不再出现“非可失败初始化器不能 `return nil`”的问题。
2. `iOSCanvasChromeStackView` 也不再出现“可失败初始化器不能 override 非可失败初始化器”的问题。
3. `iOSCanvasChromeOverlayView` 与 `iOSCanvasChromeStackView` 都明确表达为“仅支持代码创建”的组件。
4. 这次不是继续围绕 `nil` 做局部补丁，而是把 `coder` 初始化器语义直接收口到正确的构造模型。

## 校验结果

- 已对以下文件执行 lint 检查，未发现新增问题：
  - `MyCanvas_Ver_0/Platform/iOS/Canvas/iOSCanvasChromeOverlayView.swift`
- 本次未执行 `xcodebuild` 项目级编译校验。
