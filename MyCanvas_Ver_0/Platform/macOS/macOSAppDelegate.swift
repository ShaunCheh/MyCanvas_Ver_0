//
//  macOSAppDelegate.swift
//  MyCanvas_Ver_0
//
//  Created by Shaun on 2026/3/13.
//

#if os(macOS)
import Foundation
import AppKit

@main
final class macOSAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private static let sharedDelegate = macOSAppDelegate()
    
    static func main() {
        let app = NSApplication.shared
        app.delegate = sharedDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderBookmarkStore.logStoredBookmarkPresence()
        let viewController = macOSAppRootViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 需要设置最小尺寸，否则不会显示
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.center()
        window.title = "MyCanvas_Ver_0"
        window.contentViewController = viewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

#endif
