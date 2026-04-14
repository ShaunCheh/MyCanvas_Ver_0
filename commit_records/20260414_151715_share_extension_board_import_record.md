# 20260414_151715_share_extension_board_import_record

## 记录说明

本记录基于当前工作区的实际 `changes`、这次涉及文件的 `git diff`，以及修改后的当前代码状态整理，不包含原始 `git diff` 文本。

这次记录的是 `Photos -> Share Sheet -> Add To Canvas` 的分享扩展改造，目标不是只让扩展“显示出来”，而是让它真正能够：

- 读取分享进来的图片。
- 展示“导入到已有图板 / 导入到新图板”的选择界面。
- 直接复用现有图板存储与导入链路，把图片写入目标图板。
- 通过 `App Group` 让主 App 与 Share Extension 访问同一份书签与图板目录。

当前工作区实际变更共 `14` 个文件，其中：

- 已跟踪文件修改 `8` 个。
- 新增文件 `6` 个。

本次记录涉及的当前 changes 文件如下：

- `Add To Canvas/ShareViewController.swift`
- `MyCanvas_Ver_0.xcodeproj/project.pbxproj`
- `MyCanvas_Ver_0/App/FolderBookmarkStore.swift`
- `MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift`
- `MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift`
- `MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift`
- `MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift`
- `MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift`
- `Add To Canvas/Add To Canvas.entitlements`
- `Add To Canvas/ShareExtensionImageResolver.swift`
- `Add To Canvas/ShareImportView.swift`
- `Add To Canvas/ShareImportViewModel.swift`
- `MyCanvas_Ver_0/App/MyCanvasSharedAppGroup.swift`
- `MyCanvas_Ver_0/MyCanvas_Ver_0.entitlements`

## 时间戳与取证命令

```bash
# 文件路径: /bin/date
# 函数: date
# 说明: 生成本记录文件名前缀使用的时间戳。
date +"%Y%m%d_%H%M%S"
```

```bash
# 文件路径: /usr/bin/git
# 函数: git status --short / git diff
# 说明: 确认当前工作区 changes，并据此整理下面的“修改前 / 修改后”片段。
git status --short

git diff -- \
  "Add To Canvas/ShareViewController.swift" \
  "Add To Canvas/ShareExtensionImageResolver.swift" \
  "Add To Canvas/ShareImportView.swift" \
  "Add To Canvas/ShareImportViewModel.swift" \
  "MyCanvas_Ver_0/App/MyCanvasSharedAppGroup.swift" \
  "MyCanvas_Ver_0/App/FolderBookmarkStore.swift" \
  "MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift" \
  "MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift" \
  "MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift" \
  "MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift" \
  "MyCanvas_Ver_0/Platform/macOS/macOSAppDelegate.swift" \
  "MyCanvas_Ver_0.xcodeproj/project.pbxproj"
```

## 修改一：`ShareViewController` 从模板页改成 SwiftUI 承载页

### 修改前

```swift
// 文件路径: Add To Canvas/ShareViewController.swift
// 函数: isContentValid / didSelectPost / configurationItems
// 说明: 修改前仍是 Xcode 默认模板，点击 Post 只会直接 completeRequest，不存在图板选择或图片导入逻辑。
import UIKit
import Social

class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool {
        return true
    }

    override func didSelectPost() {
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        return []
    }
}
```

### 修改后

```swift
// 文件路径: Add To Canvas/ShareViewController.swift
// 函数: viewDidLoad / embedHostingController
// 说明: 修改后不再使用模板 compose sheet，而是承载 SwiftUI 选择页，把完成/取消回调接回 extensionContext。
import SwiftUI
import UIKit

final class ShareViewController: UIViewController {
    private lazy var viewModel = ShareImportViewModel(
        extensionContext: extensionContext,
        finishHandler: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        },
        cancelHandler: { [weak self] error in
            self?.extensionContext?.cancelRequest(withError: error)
        }
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 0, height: 560)
        embedHostingController()
    }

    private func embedHostingController() {
        let hostingController = UIHostingController(
            rootView: ShareImportView(viewModel: viewModel)
        )
        // 用 UIHostingController 承载 SwiftUI 选择页，保留 extensionContext 完成/取消能力。
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}
```

### 这一处修改的实际效果

- 扩展页不再是系统模板里的空白 Post 页。
- 分享页入口被替换为一个可承载业务交互的 SwiftUI 界面。
- 导入成功和取消仍然通过 `extensionContext` 正常结束扩展生命周期。

## 修改二：新增 `ShareImportViewModel`，让分享页真正具备“选图板 / 新建图板 / 导入”的状态机

### 修改前

```swift
// 文件路径: Add To Canvas/ShareImportViewModel.swift
// 函数: 无
// 说明: 修改前该文件不存在，扩展没有状态管理层，也没有“加载图板列表 / 解析输入图片 / 执行导入”的流程。
// 修改前: 文件不存在
```

### 修改后

```swift
// 文件路径: Add To Canvas/ShareImportViewModel.swift
// 函数: load / importImages / saveBoard
// 说明: 修改后新增分享导入状态机，负责读取共享 UserDefaults、加载图板列表、解析分享图片并执行导入保存。
@MainActor
final class ShareImportViewModel: ObservableObject {
    @Published private(set) var boardOptions: [ShareBoardOption] = []
    @Published private(set) var incomingImageCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isImporting = false
    @Published var selectedDestination: Destination = .newBoard
    @Published var errorMessage: String?

    private func load() async {
        guard let sharedUserDefaults = MyCanvasSharedAppGroup.sharedUserDefaults else {
            throw ShareImportError.unavailableSharedStore
        }

        guard FolderBookmarkStore.hasStoredBookmarkData(userDefaults: sharedUserDefaults) else {
            throw ShareImportError.missingSelectedFolder
        }

        let resolvedImages = await ShareExtensionImageResolver.resolveImages(from: extensionContext)
        let boardSummaries = try BoardStore.listBoards(userDefaults: sharedUserDefaults)
        // 这里把共享存储中的图板目录和当前分享的图片绑定到同一个 ViewModel 状态。
        self.resolvedImages = resolvedImages
        boardOptions = boardSummaries.map { ShareBoardOption(boardID: $0.boardID, title: $0.title, updatedAt: $0.updatedAt) }
    }

    private func importImages(userDefaults: UserDefaults) async throws {
        let session = CanvasEditorSession(
            saveQueueLabel: "MyCanvas.ShareExtension.Save",
            logPrefix: "[BoardStore][ShareExtension]",
            userDefaults: userDefaults
        )

        switch selectedDestination {
        case .newBoard:
            session.startNewBoard()
        case let .existing(boardID):
            try session.loadBoard(id: boardID)
        }

        let transferRequest = CanvasTransferRequest(
            images: resolvedImages,
            placement: .cameraCenter,
            layout: .automatic,
            sourceDescription: "Photos share extension"
        )
        guard let importRequest = try CanvasMediaImportService.makeImportRequest(
            from: transferRequest,
            boardID: session.currentBoardRuntimeState()?.boardID,
            userDefaults: userDefaults
        ) else {
            throw ShareImportError.noImportableImages
        }
        _ = session.appendImportedMedia(
            importRequest.items,
            placement: importRequest.placement,
            layout: importRequest.layout,
            presentationTemplate: importRequest.presentationTemplate
        )
        try await saveBoard(session, reason: "share extension import", createBoardIfNeeded: true)
    }
}
```

### 这一处修改的实际效果

- 分享页第一次真正拥有“状态”和“业务动作”。
- 目标图板的选择与导入执行不再分散在控制器层，而是集中在一个可维护的 ViewModel 里。
- 导入动作直接复用现有 `CanvasEditorSession`、`CanvasMediaImportService`、`BoardStore` 链路，而不是新写一套临时导入逻辑。

## 修改三：新增 `ShareImportView`，把“导入到新图板 / 已有图板”的 UI 做出来

### 修改前

```swift
// 文件路径: Add To Canvas/ShareImportView.swift
// 函数: 无
// 说明: 修改前该文件不存在，扩展没有自定义业务界面。
// 修改前: 文件不存在
```

### 修改后

```swift
// 文件路径: Add To Canvas/ShareImportView.swift
// 函数: body / ShareImportDestinationRow.body
// 说明: 修改后新增 SwiftUI 页面，显示图片数量、图板列表、取消按钮和导入按钮。
struct ShareImportView: View {
    @ObservedObject var viewModel: ShareImportViewModel

    var body: some View {
        NavigationView {
            List {
                Section {
                    Label(viewModel.incomingImageSummary, systemImage: "photo.on.rectangle.angled")
                }

                Section("目标图板") {
                    ShareImportDestinationRow(
                        title: "新建图板",
                        subtitle: "导入后自动创建一块新的图板",
                        isSelected: viewModel.selectedDestination == .newBoard
                    ) {
                        viewModel.selectedDestination = .newBoard
                    }

                    ForEach(viewModel.boardOptions) { board in
                        ShareImportDestinationRow(
                            title: board.title,
                            subtitle: board.updatedAt.formatted(date: .abbreviated, time: .shortened),
                            isSelected: viewModel.selectedDestination == .existing(board.boardID)
                        ) {
                            viewModel.selectedDestination = .existing(board.boardID)
                        }
                    }
                }
            }
            .navigationTitle("导入到图板")
            .safeAreaInset(edge: .bottom) {
                Button(action: viewModel.importSelection) {
                    Text(viewModel.importButtonTitle)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.canImport == false)
            }
        }
    }
}
```

### 这一处修改的实际效果

- 用户可以在 share sheet 里直接决定“导入到新图板”还是“导入到已有图板”。
- 如果当前没有图板，UI 会自然退化成只剩“新建图板”入口，而不是报错或空白。
- 错误信息和加载状态也能在页面内直接呈现。

## 修改四：新增 `ShareExtensionImageResolver`，把 `NSExtensionContext` 里的图片真正解析成现有导入模型

### 修改前

```swift
// 文件路径: Add To Canvas/ShareExtensionImageResolver.swift
// 函数: 无
// 说明: 修改前该文件不存在，Share Extension 没有独立的图片解析层。
// 修改前: 文件不存在
```

### 修改后

```swift
// 文件路径: Add To Canvas/ShareExtensionImageResolver.swift
// 函数: resolveImages / resolvedImage / loadImageData
// 说明: 修改后新增图片解析器，把 NSExtensionItem -> NSItemProvider -> CanvasResolvedImportImage 串起来。
enum ShareExtensionImageResolver {
    static func resolveImages(
        from extensionContext: NSExtensionContext?
    ) async -> [CanvasResolvedImportImage] {
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        var resolvedImages: [CanvasResolvedImportImage] = []

        for inputItem in inputItems {
            for itemProvider in inputItem.attachments ?? [] {
                guard let resolvedImage = await resolvedImage(from: itemProvider) else {
                    continue
                }
                resolvedImages.append(resolvedImage)
            }
        }
        return resolvedImages
    }

    private static func resolvedImage(
        from itemProvider: NSItemProvider
    ) async -> CanvasResolvedImportImage? {
        guard itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
            return nil
        }
        // 优先使用更具体的图片类型标识，再回退到 public.image，尽量保留原始导入语义。
        for typeIdentifier in preferredImageTypeIdentifiers(from: itemProvider) {
            guard
                let data = await loadImageData(from: itemProvider, typeIdentifier: typeIdentifier),
                let resolvedImage = CanvasResolvedImportImage(data: data, typeIdentifier: typeIdentifier, filenameHint: itemProvider.suggestedName)
            else {
                continue
            }
            return resolvedImage
        }
        return nil
    }
}
```

### 这一处修改的实际效果

- 分享扩展不再只知道“有 attachments”，而是能把它们变成项目现有的 `CanvasResolvedImportImage`。
- 这条解析链与主 App 导入模型保持一致，减少了数据结构分叉。

## 修改五：把共享存储从“主 App 私有 UserDefaults”提升为“主 App / 扩展共享的 App Group UserDefaults”

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数: save / storedBookmarkData / logStoredBookmarkPresence
// 说明: 修改前书签只保存在 UserDefaults.standard，Share Extension 无法直接访问主 App 之前选中的目录书签。
enum FolderBookmarkStore {
    private static let bookmarkDefaultsKey = "SelectedFolderBookmarkData"

    static func save(_ bookmarkData: Data, userDefaults: UserDefaults = .standard) {
        userDefaults.set(bookmarkData, forKey: bookmarkDefaultsKey)
    }

    static func storedBookmarkData(userDefaults: UserDefaults = .standard) -> Data? {
        userDefaults.data(forKey: bookmarkDefaultsKey)
    }

    static func logStoredBookmarkPresence(userDefaults: UserDefaults = .standard) {
        print("[FolderBookmark] UserDefaults has bookmark data: \(hasStoredBookmarkData(userDefaults: userDefaults))")
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/App/MyCanvasSharedAppGroup.swift
// 函数: sharedUserDefaults / requireSharedUserDefaults
// 说明: 修改后新增共享 App Group 定义，主 App 和 Share Extension 都通过同一个 suite 访问共享配置。
enum MyCanvasSharedAppGroup {
    static let identifier = "group.shaunyu.MyCanvas-Ver-0.shared"

    static var sharedUserDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/App/FolderBookmarkStore.swift
// 函数: save / storedBookmarkData / mirrorStoredBookmarkToSharedStoreIfNeeded / logStoredBookmarkPresence
// 说明: 修改后书签在主 store 与共享 store 间双向兼容，老用户也会在启动时被自动迁移到共享存储。
enum FolderBookmarkStore {
    static func save(_ bookmarkData: Data, userDefaults: UserDefaults = .standard) {
        persist(bookmarkData, in: userDefaults)
        if let sharedUserDefaults = sharedUserDefaults(distinctFrom: userDefaults) {
            persist(bookmarkData, in: sharedUserDefaults)
        }
    }

    static func storedBookmarkData(userDefaults: UserDefaults = .standard) -> Data? {
        if let bookmarkData = userDefaults.data(forKey: bookmarkDefaultsKey) {
            return bookmarkData
        }
        return fallbackBookmarkData(for: userDefaults)
    }

    static func mirrorStoredBookmarkToSharedStoreIfNeeded(
        userDefaults: UserDefaults = .standard
    ) {
        guard
            let sharedUserDefaults = sharedUserDefaults(distinctFrom: userDefaults),
            sharedUserDefaults.data(forKey: bookmarkDefaultsKey) == nil,
            let bookmarkData = userDefaults.data(forKey: bookmarkDefaultsKey)
        else {
            return
        }
        // 启动时把旧的 standard 书签镜像到 App Group，避免老用户必须重新选目录。
        persist(bookmarkData, in: sharedUserDefaults)
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Platform/iOS/iOSAppDelegate.swift
// 函数: application(_:didFinishLaunchingWithOptions:)
// 说明: iOS 启动时会自动触发一次旧书签向共享存储的迁移。
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
) -> Bool {
    FolderBookmarkStore.mirrorStoredBookmarkToSharedStoreIfNeeded()
    FolderBookmarkStore.logStoredBookmarkPresence()
    // ... 其余启动逻辑省略 ...
    return true
}
```

### 这一处修改的实际效果

- 分享扩展终于能访问主 App 已经选好的图板目录。
- 老用户不需要手动重新选择目录，启动主 App 一次即可完成旧书签迁移。
- `FolderBookmarkStore` 不再被 `UserDefaults.standard` 锁死。

## 修改六：把现有导入/保存链路改成可注入 `userDefaults`，让 Share Extension 能直接复用存储层

### 修改前

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 函数: makeImportRequest
// 说明: 修改前导入服务内部只会走默认存储上下文，无法指定 Share Extension 这边的共享 UserDefaults。
enum CanvasMediaImportService {
    static func makeImportRequest(
        from transferRequest: CanvasTransferRequest,
        boardID: UUID? = nil
    ) throws -> CanvasImportRequest? {
        let assetsDirectoryURL: URL?
        if transferRequest.containsVideo {
            guard let boardID else {
                throw CanvasMediaImportServiceError.missingBoardIDForVideoImport
            }
            assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(for: boardID)
        } else {
            assetsDirectoryURL = nil
        }
        // 修改前这里仍然只能落到默认存储上下文，调用方无法替换为共享 UserDefaults。
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数: init / enqueueSave
// 说明: 修改前保存协调器只会调用 BoardStore.saveBoard(snapshot)，没有注入共享 UserDefaults 的通道。
final class BoardSaveCoordinator {
    init(
        queueLabel: String,
        logPrefix: String,
        autosaveDelay: TimeInterval = 0.35
    ) {
        self.autosaveDelay = autosaveDelay
        self.logPrefix = logPrefix
        saveQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    private func enqueueSave(
        snapshot: BoardSaveSnapshot,
        reason: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        saveQueue.async { [logPrefix] in
            do {
                try BoardStore.saveBoard(snapshot)
            } catch {
                print("\(logPrefix) Failed to save board (\(reason)): \(error)")
            }
        }
    }
}
```

### 修改后

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Import/CanvasMediaImportService.swift
// 函数: makeImportRequest
// 说明: 修改后导入服务允许上层显式传入共享 UserDefaults，视频资源目录也会落在同一套共享图板上下文里。
enum CanvasMediaImportService {
    static func makeImportRequest(
        from transferRequest: CanvasTransferRequest,
        boardID: UUID? = nil,
        userDefaults: UserDefaults = .standard
    ) throws -> CanvasImportRequest? {
        let assetsDirectoryURL: URL?
        if transferRequest.containsVideo {
            assetsDirectoryURL = try BoardStore.ensureAssetsDirectoryURL(
                for: boardID!,
                userDefaults: userDefaults
            )
        } else {
            assetsDirectoryURL = nil
        }
        // 这里继续沿用原有导入管线，只是把存储上下文显式注入进来。
        return CanvasImportRequest(
            items: importItems,
            placement: transferRequest.placement,
            layout: transferRequest.layout,
            sourceDescription: transferRequest.sourceDescription
        )
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Storage/BoardSaveCoordinator.swift
// 函数: init / enqueueSave
// 说明: 修改后保存协调器持有 userDefaults，并在后台保存时把它继续传给 BoardStore。
final class BoardSaveCoordinator {
    private let userDefaults: UserDefaults

    init(
        queueLabel: String,
        logPrefix: String,
        userDefaults: UserDefaults = .standard,
        autosaveDelay: TimeInterval = 0.35
    ) {
        self.userDefaults = userDefaults
        self.autosaveDelay = autosaveDelay
        self.logPrefix = logPrefix
        saveQueue = DispatchQueue(label: queueLabel, qos: .utility)
    }

    private func enqueueSave(
        snapshot: BoardSaveSnapshot,
        reason: String,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        saveQueue.async { [logPrefix, userDefaults] in
            try BoardStore.saveBoard(
                snapshot,
                userDefaults: userDefaults
            )
        }
    }
}
```

```swift
// 文件路径: MyCanvas_Ver_0/Canvas/Editing/CanvasEditorSession.swift
// 函数: init / loadBoard / restorePersistedBoardIfPossible / ensureActiveBoardIdentityIfNeeded
// 说明: 修改后编辑会话也持有 userDefaults，使 Share Extension 可在共享存储上下文里直接复用现有图板打开与保存逻辑。
final class CanvasEditorSession {
    private let userDefaults: UserDefaults

    init(
        saveQueueLabel: String,
        logPrefix: String,
        userDefaults: UserDefaults = .standard
    ) {
        self.userDefaults = userDefaults
        saveCoordinator = BoardSaveCoordinator(
            queueLabel: saveQueueLabel,
            logPrefix: logPrefix,
            userDefaults: userDefaults
        )
    }

    func loadBoard(id: UUID) throws {
        let runtimeState = try BoardStore.loadBoard(
            id: id,
            userDefaults: userDefaults
        )
        applyBoardRuntimeState(runtimeState)
    }
}
```

### 这一处修改的实际效果

- Share Extension 不需要再绕一层“唤起主 App 再导入”才能写盘。
- 现有导入、会话、保存链路被保留，只是把存储上下文显式化。
- 主 App 仍可继续使用默认 `UserDefaults.standard`，不会破坏原有行为。

## 修改七：工程接线，给主 App / 扩展都加上 `App Group`，并让扩展编入需要的共享代码

### 修改前

```text
// 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
// 配置项: PBXNativeTarget.fileSystemSynchronizedGroups / XCBuildConfiguration.buildSettings
// 说明: 修改前 Add To Canvas target 只包含自己的源目录，没有显式接入 App / Canvas / Platform/Shared，也没有 entitlements 配置。
fileSystemSynchronizedGroups = (
    28A9EB782F8DEFCD004160FE /* Add To Canvas */,
);

buildSettings = {
    CODE_SIGN_STYLE = Automatic;
    // 修改前: 没有 CODE_SIGN_ENTITLEMENTS
};
```

### 修改后

```text
// 文件路径: MyCanvas_Ver_0.xcodeproj/project.pbxproj
// 配置项: PBXNativeTarget.fileSystemSynchronizedGroups / XCBuildConfiguration.buildSettings
// 说明: 修改后 Add To Canvas target 显式纳入 App、Canvas、BoardList、Rendering 这几块共享代码，并给主 App / 扩展都接上 entitlements。
fileSystemSynchronizedGroups = (
    28F1A0012F8E0001004160FE /* App */,
    28F1A0022F8E0001004160FE /* Canvas */,
    28F1A0032F8E0001004160FE /* BoardList */,
    28F1A0042F8E0001004160FE /* Rendering */,
    28A9EB782F8DEFCD004160FE /* Add To Canvas */,
);

buildSettings = {
    CODE_SIGN_ENTITLEMENTS = "MyCanvas_Ver_0/MyCanvas_Ver_0.entitlements";
};

buildSettings = {
    CODE_SIGN_ENTITLEMENTS = "Add To Canvas/Add To Canvas.entitlements";
};
```

```xml
<!-- 文件路径: MyCanvas_Ver_0/MyCanvas_Ver_0.entitlements -->
<!-- 配置项: com.apple.security.application-groups -->
<!-- 说明: 主 App 加入与 Share Extension 相同的 App Group。 -->
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.shaunyu.MyCanvas-Ver-0.shared</string>
    </array>
</dict>
```

```xml
<!-- 文件路径: Add To Canvas/Add To Canvas.entitlements -->
<!-- 配置项: com.apple.security.application-groups -->
<!-- 说明: Share Extension 加入同一个 App Group，才能访问共享书签和共享图板上下文。 -->
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.shaunyu.MyCanvas-Ver-0.shared</string>
    </array>
</dict>
```

### 这一处修改的实际效果

- 扩展不再只是 UI target，而是能真正编入并复用图板导入所需的共享代码。
- 主 App 与扩展都持有同一个 `App Group`，共享 `UserDefaults` 才能真正生效。

## 修改八：这次改造不是“只新增 UI”，而是把分享导入闭环补齐

这次不是做一个好看的分享页壳子，而是同时补齐了下面这个闭环：

1. `Photos Share Sheet` 把图片交给 `Add To Canvas`。
2. `ShareViewController` 承载 `ShareImportView`。
3. `ShareImportViewModel.load()` 从共享存储读取书签和图板列表。
4. `ShareExtensionImageResolver` 把分享输入转成 `CanvasResolvedImportImage`。
5. `CanvasEditorSession + CanvasMediaImportService + BoardSaveCoordinator` 在共享 `userDefaults` 上下文里执行导入和保存。
6. 保存结果直接落入已有图板目录，或者新建一块图板后再落入。

因此，这次改造的真实边界是：

- 补了 UI。
- 补了图片解析。
- 补了共享存储。
- 补了会话与保存注入。
- 补了 target / entitlement 工程接线。

## 构建验证

```bash
# 文件路径: /usr/bin/xcodebuild
# 函数: xcodebuild -project -scheme -destination build
# 说明: 验证主 App scheme 与 Add To Canvas target 的本次改动可以一起通过 iOS Simulator 构建。
xcodebuild -project "MyCanvas_Ver_0.xcodeproj" \
  -scheme "MyCanvas_Ver_0" \
  -destination "generic/platform=iOS Simulator" \
  build
```

验证结果：

- 构建通过。
- 期间修正过一次 SwiftUI 样式推断问题和一次扩展 target 共享代码接线问题。
- 最终 `xcodebuild` 返回成功，说明当前工程配置、Share Extension 源码和共享存储接线在编译层面已经闭合。
