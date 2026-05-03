import Foundation

// Which identifier GemmaActor should construct on its next cold start.
// Phase 1a only ships `.python`; `.native` becomes meaningful once
// NativeGemmaIdentifier has a real implementation (Phase 1b). The flag
// itself ships now so the toggle UX in 1d isn't blocked on plumbing.
enum IdentificationBackend: String, Sendable {
    case python
    case native
}

final class IdentificationBackendStore: @unchecked Sendable {
    static let shared = IdentificationBackendStore()

    // UserDefaults key. Bool, not raw string — `false` (default) means
    // "use Python" so a missing key keeps existing behavior.
    private let key = "gemma.useNativeBackend"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var current: IdentificationBackend {
        userDefaults.bool(forKey: key) ? .native : .python
    }

    func setUseNative(_ value: Bool) {
        userDefaults.set(value, forKey: key)
    }
}
