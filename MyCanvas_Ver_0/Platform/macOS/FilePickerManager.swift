#if os(macOS)
import AppKit
import Foundation

enum FilePickerManager {
    static func selectFolder() throws -> Data? {
        let openPanel = NSOpenPanel()
        openPanel.message = "Select a folder to bookmark."
        openPanel.prompt = "Select"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = false
        openPanel.allowsMultipleSelection = false

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }

        return try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}
#endif
