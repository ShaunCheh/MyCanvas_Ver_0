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
final class macOSAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var window: NSWindow?
    private var rootViewController: macOSAppRootViewController?
    private static let sharedDelegate = macOSAppDelegate()
    
    static func main() {
        let app = NSApplication.shared
        app.delegate = sharedDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderBookmarkStore.logStoredBookmarkPresence()
        let viewController = macOSAppRootViewController()
        rootViewController = viewController
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
        NSApp.mainMenu = makeMainMenu()
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    @objc
    private func handleUndoMenuItem(_ sender: Any?) {
        rootViewController?.currentCanvasViewController?.performUndoCommand()
    }

    @objc
    private func handleRedoMenuItem(_ sender: Any?) {
        rootViewController?.currentCanvasViewController?.performRedoCommand()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(handleUndoMenuItem(_:)):
            return rootViewController?.currentCanvasViewController?.canUndoCommand ?? false
        case #selector(handleRedoMenuItem(_:)):
            return rootViewController?.currentCanvasViewController?.canRedoCommand ?? false
        default:
            return true
        }
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeApplicationMenuItem())
        mainMenu.addItem(makeEditMenuItem())
        return mainMenu
    }

    private func makeApplicationMenuItem() -> NSMenuItem {
        let appName = ProcessInfo.processInfo.processName
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu
        return appMenuItem
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(handleUndoMenuItem(_:)),
            keyEquivalent: "z"
        )
        undoItem.target = self
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(handleRedoMenuItem(_:)),
            keyEquivalent: "Z"
        )
        redoItem.target = self
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenuItem.submenu = editMenu
        return editMenuItem
    }
}

#endif
