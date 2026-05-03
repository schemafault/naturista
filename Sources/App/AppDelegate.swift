import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPaths.ensureDirectories()

        Task {
            do {
                try await DatabaseService.shared.initialize()
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

        window?.title = "Naturista — Field Journal"
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
}