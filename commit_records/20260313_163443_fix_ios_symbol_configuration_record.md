# 20260313_163443_fix_ios_symbol_configuration_record

## 记录范围

- 记录内容：修复 `iOSViewController` 中 `UIButton` 的 SF Symbol 配置写法错误。
- 目标：消除 `Cannot assign to value: 'preferredSymbolConfigurationForImage' is a method` 编译错误。
- 本次未包含：导入链路逻辑变化、交互逻辑变化、任何 macOS 侧修改。

## 变更 1：修复 iOS 导入按钮的符号配置赋值位置

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/初始化位置: importButton 属性初始化闭包
// 功能说明: 修改前把 preferredSymbolConfigurationForImage 当成 UIButton 的可写属性，导致编译错误。
private let importButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    var configuration = UIButton.Configuration.filled()
    configuration.image = UIImage(systemName: "plus")
    configuration.baseBackgroundColor = .systemBlue
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    button.configuration = configuration
    return button
}()
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSViewController.swift
// 函数/初始化位置: importButton 属性初始化闭包
// 功能说明: 修改后把符号配置写到 UIButton.Configuration 上，保持现有按钮结构不变，同时修正 UIKit API 的正确用法。
private let importButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    var configuration = UIButton.Configuration.filled()
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
    configuration.image = UIImage(systemName: "plus")
    configuration.baseBackgroundColor = .systemBlue
    configuration.baseForegroundColor = .white
    configuration.cornerStyle = .capsule
    button.configuration = configuration
    return button
}()
```

## 当前结果

- `iOSViewController` 中的导入按钮仍然保持原有视觉和结构。
- 仅修复了 SF Symbol 配置的 API 用法。
- 该修复用于消除 `preferredSymbolConfigurationForImage` 的编译错误，不影响阶段六的选图与导入链路设计。
