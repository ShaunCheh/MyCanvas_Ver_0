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
final class macOSAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private static let sharedDelegate = macOSAppDelegate()
    
    static func main() {
        let app = NSApplication.shared
        app.delegate = sharedDelegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FolderBookmarkStore.mirrorStoredBookmarkToSharedStoreIfNeeded()
        FolderBookmarkStore.logStoredBookmarkPresence()
        NSApp.mainMenu = makeMainMenu()
        openMainWindow()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows _: Bool
    ) -> Bool {
        openMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow === window else {
            return
        }
        window = nil
    }

    private func openMainWindow() {
        if let window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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
        window.delegate = self
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(makeApplicationMenuItem())
        mainMenu.addItem(makeFileMenuItem())
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

    private func makeFileMenuItem() -> NSMenuItem {
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "File")
        let closeItem = NSMenuItem(
            title: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu
        return fileMenuItem
    }

    private func makeEditMenuItem() -> NSMenuItem {
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")

        let undoItem = NSMenuItem(
            title: "Undo",
            action: #selector(macOSViewController.undo(_:)),
            keyEquivalent: "z"
        )
        undoItem.keyEquivalentModifierMask = [.command]
        editMenu.addItem(undoItem)

        let redoItem = NSMenuItem(
            title: "Redo",
            action: #selector(macOSViewController.redo(_:)),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)

        editMenu.addItem(.separator())

        let pasteItem = NSMenuItem(
            title: "Paste",
            action: #selector(macOSViewController.paste(_:)),
            keyEquivalent: "v"
        )
        pasteItem.keyEquivalentModifierMask = .command
        editMenu.addItem(pasteItem)

        editMenuItem.submenu = editMenu
        return editMenuItem
    }
}

#endif
