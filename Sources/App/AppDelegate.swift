import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPaths.ensureDirectories()
        ModelStorageMigrator.migrateIfNeeded()
        installMainMenu()

        Task {
            do {
                try await DatabaseService.shared.initialize()
                Task.detached(priority: .utility) {
                    await ThumbnailBackfillService.shared.runIfNeeded()
                }
            } catch {
                print("Database initialization failed: \(error)")
            }
        }

        let contentView = ContentView()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.title = "Naturista — My Journal"
        window?.minSize = NSSize(width: 960, height: 640)
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .visible
        window?.appearance = NSAppearance(named: .aqua)
        window?.backgroundColor = NSColor(srgbRed: 245/255, green: 240/255, blue: 229/255, alpha: 1)
        window?.contentView = NSHostingView(rootView: contentView)
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // Without a main menu, the standard Cmd+C/V/X/A/Z shortcuts have no
    // target — TextEditor and TextField inside the app feel "broken." This
    // installs the minimum: an app menu (so Quit works) and an Edit menu
    // wired to the responder chain so any focused text view can copy/paste.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let appName = ProcessInfo.processInfo.processName
        appMenu.addItem(withTitle: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}