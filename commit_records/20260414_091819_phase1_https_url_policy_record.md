# 20260414_091819_phase1_https_url_policy_record

## 记录说明

本记录基于本次 `phase 1` 实际改动的 `git status`、`git diff` 统计、当前工作区代码状态与构建/测试结果整理，不包含原始 `git diff` 文本。

本次业务代码实际只涉及 `2` 个新增文件：

- `MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift`
- `MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift`

本次工作分支：

- `feat/cross-platform-input-indicator`

写入本记录前的代码状态依据：

- `git status --short --branch` 显示当前只有 `2` 个未跟踪业务文件
- 由于这 `2` 个文件都是新增且未暂存文件，普通 `git diff -- "path"` 不会产出正文 diff
- 为了如实记录新增文件的改动规模，本记录使用 `git diff --no-index --stat -- /dev/null "path"` 统计插入行数
- `xcodebuild build` 已验证 `MyCanvas_Ver_0` app target 可以成功编译
- `xcodebuild test` 尝试只跑新增测试时，被仓库里已有测试编译错误阻塞，不是本次新增文件导致

本记录不包含：

- 原始 `git diff` 文本
- git commit / push
- 对任何已有 `.md` 文件的改写

## 时间戳与取证命令

```bash
# 文件路径: 系统命令 /bin/date
# 函数名/命令名: date
# 功能说明: 生成本记录文件名使用的时间戳前缀。
date '+%Y%m%d_%H%M%S'
#
# 实际输出:
# 20260414_091819
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git status --short --branch
# 功能说明: 记录写入本文件前的真实工作区状态，确认本次业务改动只包含两个新增文件。
git status --short --branch
#
# 实际输出:
# ## feat/cross-platform-input-indicator
# ?? MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift
# ?? MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --no-index --stat
# 功能说明: 统计新增共享 URL 策略文件的真实改动规模。
git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift"
#
# 实际输出:
# .../Platform/Shared/CanvasHTTPSURLPolicy.swift     | 109 +++++++++++++++++++++
# 1 file changed, 109 insertions(+)
```

```bash
# 文件路径: 系统命令 /usr/bin/git
# 函数名/命令名: git diff --no-index --stat
# 功能说明: 统计新增测试文件的真实改动规模。
git diff --no-index --stat -- /dev/null \
  "MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift"
#
# 实际输出:
# .../CanvasHTTPSURLPolicyTests.swift                | 89 ++++++++++++++++++++++
# 1 file changed, 89 insertions(+)
```

## 本次修改的真实目标

这一步只落实 `phase 1` 的共享边界，不触碰现有 `toolbar`、`GIF` 弹层、`Video` 弹层和 `reading mode` 行为：

1. 新增一个共享、纯 Swift 的 `HTTPS URL` 规范化与校验入口。
2. 让未来 `iOS` 与 `macOS` 网页页都能复用同一套输入处理规则。
3. 在规则层提前钉死：自动补 `https://`、拒绝 `http`、拒绝其他 scheme、拒绝缺失 host、拒绝空输入。
4. 用单测把这些规则固定住，避免后续平台实现分叉。

## 修改一：新增共享 URL 策略文件

### 修改前

修改前，仓库里没有专门面向网页输入的共享 `HTTPS URL` 规范化/校验文件；也没有一个明确的纯 Swift 入口，把“补 `https://`、拒绝 `http`、拒绝无 host”这组规则收口到一起。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift
// 函数名/符号名: 新增前不存在
// 功能说明: 修改前仓库中没有这个共享策略文件，因此未来 iOS/macOS 网页页如果直接开工，URL 输入规则会分散在各自平台代码里。
// 文件状态: 不存在
```

### 修改后

新增 `CanvasHTTPSURLPolicyError` 和 `CanvasHTTPSURLPolicy`，把错误分类、URL 规整和 scheme 判定统一收口。下面代码块展示的是实际新增后的核心内容，不是原始 `git diff` 文本。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift
// 函数名/符号名: CanvasHTTPSURLPolicyError / CanvasHTTPSURLPolicy.url(from:) / normalizedString(from:)
// 功能说明: 新增共享 URL 策略，把用户原始输入规整成 HTTPS URL，并对不允许的输入给出可区分错误。
import Foundation

enum CanvasHTTPSURLPolicyError: LocalizedError, Equatable {
    case emptyInput
    case invalidURL
    case missingHost
    case httpSchemeNotAllowed
    case unsupportedScheme(String)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Enter a website URL."
        case .invalidURL:
            return "The website URL is invalid."
        case .missingHost:
            return "The website URL must include a host."
        case .httpSchemeNotAllowed:
            return "Only HTTPS URLs are supported."
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme). Only HTTPS URLs are supported."
        }
    }
}

enum CanvasHTTPSURLPolicy {
    static func url(from rawInput: String) throws -> URL {
        // 先裁掉首尾空白，统一处理粘贴输入和手打输入。
        let trimmedInput = rawInput.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard trimmedInput.isEmpty == false else {
            throw CanvasHTTPSURLPolicyError.emptyInput
        }

        // 缺失 scheme 时自动补 https://，但显式 scheme 仍保留给后续规则判断。
        let candidateURLString = resolvedCandidateURLString(
            from: trimmedInput
        )
        guard var components = URLComponents(string: candidateURLString) else {
            throw CanvasHTTPSURLPolicyError.invalidURL
        }

        // 只放行 https；http 和其他 scheme 都被明确拒绝。
        guard let scheme = components.scheme?.lowercased() else {
            throw CanvasHTTPSURLPolicyError.invalidURL
        }
        guard scheme == "https" else {
            if scheme == "http" {
                throw CanvasHTTPSURLPolicyError.httpSchemeNotAllowed
            }
            throw CanvasHTTPSURLPolicyError.unsupportedScheme(scheme)
        }

        // host 不能为空，并统一小写，保证后续展示与加载一致。
        guard let host = components.host?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), host.isEmpty == false
        else {
            throw CanvasHTTPSURLPolicyError.missingHost
        }

        components.scheme = "https"
        components.host = host.lowercased()
        guard let resolvedURL = components.url else {
            throw CanvasHTTPSURLPolicyError.invalidURL
        }
        return resolvedURL
    }

    static func normalizedString(from rawInput: String) throws -> String {
        try url(from: rawInput).absoluteString
    }
}
```

除了主入口外，这个文件还补了两个私有辅助函数，解决“什么时候算显式 scheme”与“什么时候该自动补 https”的边界问题。

```swift
// 文件路径: MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift
// 函数名/符号名: resolvedCandidateURLString(from:) / hasExplicitSchemePrefix(_:)
// 功能说明: 新增内部辅助逻辑，避免把 query 中的 http:// 子串误判成显式 scheme，同时支持 //example.com 这种协议相对输入。
private static func resolvedCandidateURLString(
    from trimmedInput: String
) -> String {
    if trimmedInput.hasPrefix("//") {
        return "https:" + trimmedInput
    }

    guard hasExplicitSchemePrefix(trimmedInput) == false else {
        return trimmedInput
    }

    return "https://" + trimmedInput
}

private static func hasExplicitSchemePrefix(_ input: String) -> Bool {
    guard let schemeSeparatorRange = input.range(of: "://") else {
        return false
    }

    let schemeCandidate = input[..<schemeSeparatorRange.lowerBound]
    guard let firstCharacter = schemeCandidate.first else {
        return false
    }
    guard firstCharacter.isLetter else {
        return false
    }

    return schemeCandidate.dropFirst().allSatisfy { character in
        character.isLetter ||
            character.isNumber ||
            character == "+" ||
            character == "." ||
            character == "-"
    }
}
```

### 这一改动解决了什么

- 把网页 URL 规则从未来的 `iOS` / `macOS` controller 中提前抽离，避免重复实现。
- 让“自动补 `https://`”与“明确拒绝 `http`”这两件事不再依赖 UI 层各自判断。
- 给后续网页页提供一个可直接调用的共享纯逻辑边界。

## 修改二：新增 HTTPS URL 策略单测

### 修改前

修改前，测试目标中没有任何专门覆盖网页 URL 规则的测试文件；因此即便后续接入网页页，也没有自动化手段防止输入规范化规则被改坏。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift
// 函数名/符号名: 新增前不存在
// 功能说明: 修改前仓库中没有专门验证 HTTPS URL 规范化与拒绝规则的测试文件。
// 文件状态: 不存在
```

### 修改后

新增 `CanvasHTTPSURLPolicyTests`，把最容易分叉的规则直接钉死。下面代码块展示的是实际新增后的测试主体与断言辅助函数。

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift
// 函数名/符号名: CanvasHTTPSURLPolicyTests
// 功能说明: 新增单测文件，覆盖补 https、保留 https、拒绝 http、拒绝无 host、拒绝空输入等关键规则。
import Foundation
import XCTest
@testable import MyCanvas_Ver_0

final class CanvasHTTPSURLPolicyTests: XCTestCase {
    func testNormalizedStringAddsHTTPSWhenSchemeIsMissing() throws {
        // 验证最基础的网页输入体验：用户只输域名时自动补 https://。
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "  example.com/docs?q=1  "
            ),
            "https://example.com/docs?q=1"
        )
    }

    func testNormalizedStringPreservesExplicitHTTPSURL() throws {
        // 验证显式 https 输入不会被错误重写，只做大小写规整。
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "HTTPS://Example.COM/Docs?q=1#Intro"
            ),
            "https://example.com/Docs?q=1#Intro"
        )
    }

    func testNormalizedStringSupportsHostAndPortWithoutScheme() throws {
        // 验证 host:port 形式在无 scheme 时仍能被正确补全。
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "example.com:8443/web/app"
            ),
            "https://example.com:8443/web/app"
        )
    }

    func testNormalizedStringDoesNotTreatQuerySchemeSubstringAsExplicitScheme() throws {
        // 验证 query 中的 http:// 不会把整串输入误判成已有 scheme。
        XCTAssertEqual(
            try CanvasHTTPSURLPolicy.normalizedString(
                from: "example.com/login?redirect=http://legacy.example.com"
            ),
            "https://example.com/login?redirect=http://legacy.example.com"
        )
    }

    func testHTTPURLsAreRejected() {
        assertPolicyError(
            for: "http://example.com",
            expectedError: .httpSchemeNotAllowed
        )
    }

    func testUnsupportedSchemesAreRejected() {
        assertPolicyError(
            for: "ftp://example.com",
            expectedError: .unsupportedScheme("ftp")
        )
    }

    func testEmptyInputIsRejected() {
        assertPolicyError(
            for: "  \n\t  ",
            expectedError: .emptyInput
        )
    }

    func testMissingHostIsRejected() {
        assertPolicyError(
            for: "https:///missing-host",
            expectedError: .missingHost
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift
// 函数名/符号名: assertPolicyError(for:expectedError:file:line:)
// 功能说明: 抽出统一错误断言，确保所有失败场景都验证到精确错误类型，而不是只验证“抛错了”。
private func assertPolicyError(
    for rawInput: String,
    expectedError: CanvasHTTPSURLPolicyError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(
        try CanvasHTTPSURLPolicy.normalizedString(from: rawInput),
        file: file,
        line: line
    ) { error in
        XCTAssertEqual(
            error as? CanvasHTTPSURLPolicyError,
            expectedError,
            file: file,
            line: line
        )
    }
}
```

### 这一改动解决了什么

- 把共享 URL 规则变成可回归验证的契约，而不是只靠肉眼检查。
- 保护了后续网页页最核心的输入边界。
- 确保未来如果有人调整 URL 处理逻辑，会第一时间被单测拦下来。

## 与当前 changes 的对应关系

从当前工作区状态看，本次 `phase 1` 没有修改任何旧文件，只是新增了两个文件：

1. 一个共享纯逻辑文件，负责 URL 策略。
2. 一个测试文件，负责覆盖 URL 策略规则。

这意味着：

- 现有 `toolbar` 行为没有被改动。
- 现有 `GIF` / `Video` 页面没有被改动。
- `reading mode` 行为没有被改动。
- `phase 1` 的影响面被控制在共享纯逻辑边界内。

## 构建与测试取证

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild build
# 功能说明: 验证 app target 可以成功编译这次新增的共享 URL 策略代码。
xcodebuild build \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS"
#
# 实际结果摘要:
# ** BUILD SUCCEEDED **
```

```bash
# 文件路径: 系统命令 /usr/bin/xcodebuild
# 函数名/命令名: xcodebuild test
# 功能说明: 尝试仅运行新增的 HTTPS URL 单测；测试目标被仓库里既有测试编译错误阻塞，不是本次新增文件导致。
xcodebuild test \
  -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "platform=macOS" \
  -only-testing:"MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests"
#
# 实际结果摘要:
# Testing failed:
# Extra argument 'updatedAt' in call
# Missing arguments for parameters 'contentUpdatedAt', 'viewStateUpdatedAt' in call
# Cannot assign to property: 'updatedAt' is a get-only property
#
# 失败位置:
# - MyCanvas_Ver_0Tests/CanvasEditorSessionAlignmentOverlayTests.swift
# - MyCanvas_Ver_0Tests/BoardVideoStorageTests.swift
```

同时，构建日志里可以看到这次新增文件已经进入编译流程：

- `MyCanvas_Ver_0/Platform/Shared/CanvasHTTPSURLPolicy.swift`
- `MyCanvas_Ver_0Tests/CanvasHTTPSURLPolicyTests.swift`

因此，这次测试未完成的根因不是本记录中新增的 URL 策略代码本身。

## 结论

本次 `phase 1` 的实际落地结果是：

1. 新增了共享的 `CanvasHTTPSURLPolicy`，把网页输入规则统一收口。
2. 新增了 `CanvasHTTPSURLPolicyTests`，把关键 URL 边界规则固定成自动化测试。
3. 没有改动现有 `toolbar`、`GIF`、`Video`、`reading mode` 代码路径。
4. `MyCanvas_Ver_0` app target 编译通过。
5. 测试目标因仓库中已有测试编译错误被阻塞，需要在后续阶段单独处理。
