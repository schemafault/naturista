import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    var window: NSWindow?
    private(set) var onboardingState: OnboardingState?

    // Tracks the cmd-Q confirmation flow. While true, the next call to
    // applicationShouldTerminate has already been answered via the modal
    // and should pass through.
    private var quitConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Show Hidden is a privacy-leaning, session-only toggle: every
        // launch starts hidden entries hidden, regardless of last
        // session's choice. Reset before any view reads `@AppStorage`.
        HiddenSettings.resetForLaunch()

        // Resolves Application Support, ensures every subdirectory,
        // runs the legacy ~/.cache → AppSupport model migration and
        // the pre-sandbox-flip container clone in the required order,
        // and redirects both Flux2Core model registries.
        Storage.bootstrap()
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

        // Build the onboarding state machine and decide whether to mount
        // OnboardingView or jump straight to ContentView. State-based
        // detection : missing model files trigger onboarding even on
        // returning launches (self-healing).
        let state = OnboardingState()
        state.phase = OnboardingDetector.needsOnboarding() ? .idle : .ready
        self.onboardingState = state

        // Defer the existing GemmaPreload startup task until we know we
        // are not in onboarding. Onboarding does its own preload during
        // the warmup phase, so running this here would race or duplicate.
        if state.phase == .ready {
            runDeferredLaunchTasks()
        }

        let styleMask: NSWindow.StyleMask = state.phase == .ready
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            : [.titled, .closable, .miniaturizable, .fullSizeContentView]

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )

        window?.title = "Naturista: My Journal"
        window?.minSize = NSSize(width: 960, height: 640)
        window?.titlebarAppearsTransparent = true
        window?.titleVisibility = .visible
        window?.appearance = NSAppearance(named: .aqua)
        window?.backgroundColor = NSColor(srgbRed: 245/255, green: 240/255, blue: 229/255, alpha: 1)
        window?.contentView = NSHostingView(rootView: RootView(state: state))
        window?.center()
        window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    // Called from RootView when the onboarding phase flips to .ready,
    // restoring the window's resize handle and re-enabling normal
    // window-min-size behavior.
    func unlockWindowResize() {
        guard let window else { return }
        window.styleMask.insert(.resizable)
    }

    // The pieces of applicationDidFinishLaunching that should only fire
    // when the user is actually using the app (not during onboarding).
    // Public so RootView can call it on the .ready transition.
    func runDeferredLaunchTasks() {
        // Warm Gemma in the background so the first identify after launch
        // skips VLMModelFactory's container build. Off by default because it
        // holds the full model resident at idle (multiple GB). Opt-in via
        // the toggle in Illustration Styles → Startup preload, persisted in
        // GemmaPreloadStore.
        if GemmaPreloadStore.shared.enabled {
            Task.detached(priority: .utility) {
                guard GemmaModelStore.shared.selected.isInstalled else { return }
                try? await ModelLease.shared.withExclusive(.identification) {
                    await GemmaActor.shared.preload()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // Intercept cmd-Q during an active onboarding download so the user
    // confirms before we tear the app down. The OnboardingView listens
    // for the show-modal notification and translates the user's choice
    // back into NSApp.reply(toApplicationShouldTerminate:).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitConfirmed { return .terminateNow }
        guard let state = onboardingState, state.hasActiveDownload else {
            return .terminateNow
        }
        quitConfirmed = true
        NotificationCenter.default.post(name: .onboardingShouldShowQuitConfirm, object: nil)
        return .terminateLater
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

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let showHidden = NSMenuItem(
            title: "Show Hidden Items",
            action: #selector(toggleShowHidden(_:)),
            keyEquivalent: "."
        )
        showHidden.keyEquivalentModifierMask = [.command, .shift]
        showHidden.target = self
        viewMenu.addItem(showHidden)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // Flips the session-only Show-Hidden toggle. SwiftUI sidebar reads
    // the same UserDefaults key via @AppStorage; the menu item's check
    // state is reapplied in validateMenuItem when AppKit re-validates
    // the menu before display.
    @objc private func toggleShowHidden(_ sender: NSMenuItem) {
        let cur = UserDefaults.standard.bool(forKey: HiddenSettings.showHiddenKey)
        UserDefaults.standard.set(!cur, forKey: HiddenSettings.showHiddenKey)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleShowHidden(_:)) {
            menuItem.state = UserDefaults.standard.bool(forKey: HiddenSettings.showHiddenKey) ? .on : .off
        }
        return true
    }
}
