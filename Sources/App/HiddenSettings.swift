import Foundation

// Per-launch state for the Hide-from-gallery feature. Lives outside any
// SwiftUI view so it survives view tear-down within a session, and so
// AppDelegate can reset it deterministically before the first window
// renders. UserDefaults("showHidden") backs the actual toggle so both
// the AppKit menu item and the SwiftUI sidebar see the same value via
// `@AppStorage`; this struct just centralises the key and the
// session-only reset.
enum HiddenSettings {
    static let showHiddenKey = "showHidden"

    // Called from applicationDidFinishLaunching before the first window
    // mounts. The Settings menu toggle is intentionally session-scoped
    // (a privacy default) — we nuke any leftover `true` from a prior
    // launch so each session starts with hidden entries hidden.
    static func resetForLaunch() {
        UserDefaults.standard.set(false, forKey: showHiddenKey)
    }
}

// Tracks whether the post-hide toast has already fired this session, so
// it shows once and stays out of the way after.
@MainActor
final class HiddenToastSeen {
    static let shared = HiddenToastSeen()
    var firstHideShownThisSession: Bool = false
    private init() {}
}
