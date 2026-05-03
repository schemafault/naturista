import Foundation
import Flux2Core
import FluxTextEncoders

// MARK: - Container snapshot

// Frozen view of every on-disk path the app needs. Resolved once at
// launch by `Storage.bootstrap()` and never mutated. Tests build their
// own via `Storage.installForTesting(root:)` against a temp directory.
struct StorageContainer: Sendable {
    let root: URL
    let database: URL
    let assets: URL
    let originals: URL
    let working: URL
    let thumbnails: URL
    let generated: URL
    let illustrations: URL
    let plates: URL
    let models: URL

    fileprivate init(root: URL) {
        self.root = root
        self.database = root.appendingPathComponent("naturista.sqlite")
        self.assets = root.appendingPathComponent("assets", isDirectory: true)
        self.originals = assets.appendingPathComponent("originals", isDirectory: true)
        self.working = assets.appendingPathComponent("working", isDirectory: true)
        self.thumbnails = assets.appendingPathComponent("thumbnails", isDirectory: true)
        self.generated = root.appendingPathComponent("generated", isDirectory: true)
        self.illustrations = generated.appendingPathComponent("illustrations", isDirectory: true)
        self.plates = generated.appendingPathComponent("plates", isDirectory: true)
        self.models = root.appendingPathComponent("models", isDirectory: true)
    }

    fileprivate var directories: [URL] {
        [assets, originals, working, thumbnails, generated, illustrations, plates, models]
    }
}

// Per-entry artifact enumeration — the same five-path tuple that used to
// be open-coded in PipelineService.deleteEntry, now in one place.
extension StorageContainer {
    func originalURL(for entry: Entry) -> URL {
        originals.appendingPathComponent(entry.originalImageFilename)
    }

    func workingURL(for entry: Entry) -> URL {
        working.appendingPathComponent(entry.workingImageFilename)
    }

    func thumbnailURL(for entry: Entry) -> URL? {
        entry.thumbnailFilename.map { thumbnails.appendingPathComponent($0) }
    }

    func illustrationURL(for entry: Entry) -> URL? {
        entry.illustrationFilename.map { illustrations.appendingPathComponent($0) }
    }

    func plateURL(for entry: Entry) -> URL? {
        entry.plateFilename.map { plates.appendingPathComponent($0) }
    }

    // Every artifact the entry owns that currently exists on disk. Used
    // by delete to sweep files; ordering is stable but not significant.
    func files(for entry: Entry) -> [URL] {
        let candidates: [URL?] = [
            originalURL(for: entry),
            workingURL(for: entry),
            illustrationURL(for: entry),
            plateURL(for: entry),
            thumbnailURL(for: entry),
        ]
        let fm = FileManager.default
        return candidates
            .compactMap { $0 }
            .filter { fm.fileExists(atPath: $0.path) }
    }
}

// MARK: - Cloner port (for the sandbox-container migration)

// Wraps `/bin/cp -c -R src/. dest/`. The clone uses APFS clonefile when
// source and destination share a volume — copy-on-write, near-zero disk
// overhead until the user mutates the new copy. Hidden behind a port so
// tests can substitute a plain FileManager copy or a no-op.
protocol SandboxCloner: Sendable {
    func clone(from source: URL, to destination: URL) throws
}

struct SystemCloner: SandboxCloner {
    enum Failure: Error, LocalizedError {
        case nonZeroExit(status: Int32)
        var errorDescription: String? {
            switch self {
            case .nonZeroExit(let s): return "cp exited \(s)"
            }
        }
    }

    func clone(from source: URL, to destination: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/cp")
        // Trailing `/.` is the canonical "clone the contents of source into
        // an existing destination directory" form.
        task.arguments = ["-c", "-R", source.path + "/.", destination.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw Failure.nonZeroExit(status: task.terminationStatus)
        }
    }
}

// MARK: - Storage namespace

// Single boundary for filesystem layout, launch migrations, and the
// Flux2Core model-registry redirect. Production callers use
// `Storage.bootstrap()` once at launch; everything else reads
// `Storage.current` (or the `AppPaths` shim, which forwards here).
enum Storage {
    private static var _current: StorageContainer?

    // Force-unwrapped because production reads happen after `bootstrap()`
    // has installed the container. Reads before bootstrap crash with a
    // loud trap rather than misbehaving silently.
    static var current: StorageContainer {
        guard let c = _current else {
            fatalError("Storage.current read before Storage.bootstrap() / installForTesting()")
        }
        return c
    }

    // Production launch entry point. Resolves Application Support, eagerly
    // creates every subdirectory, runs the two launch migrations in the
    // required order (model-cache → sandbox-container clone), redirects
    // Flux2Core's two model registries, and freezes the result into
    // `current`. Returns the container so callers can stash it if they
    // want injection without going through the global.
    @discardableResult
    static func bootstrap(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        cloner: SandboxCloner = SystemCloner(),
        registryRedirect: (URL) -> Void = Storage.defaultRegistryRedirect
    ) -> StorageContainer {
        let root = resolveRoot(fileManager: fileManager)
        let container = StorageContainer(root: root)
        ensureDirectories(container, fileManager: fileManager)

        // Order matters: `migrateLegacyModelCache` moves files into
        // AppSupport/models that `migrateSandboxContainer` will then
        // clone into the sandbox container. Reversing the order leaves
        // legacy weights stranded in ~/.cache/.
        migrateLegacyModelCache(container, fileManager: fileManager, userDefaults: userDefaults)
        migrateSandboxContainer(fileManager: fileManager, userDefaults: userDefaults, cloner: cloner)

        registryRedirect(container.models)

        _current = container
        return container
    }

    // Test entry point. Builds a container rooted at `root`, ensures
    // every subdirectory exists, installs as `current`. Skips both
    // migrations and the registry redirect — tests don't care about
    // either, and `Process` invocation isn't friendly to CI.
    @discardableResult
    static func installForTesting(
        root: URL,
        fileManager: FileManager = .default
    ) -> StorageContainer {
        let container = StorageContainer(root: root)
        ensureDirectories(container, fileManager: fileManager)
        _current = container
        return container
    }

    // Default Flux2Core redirect. FLUX has TWO downloaders with
    // independent customModelsDirectory overrides: Flux2Core
    // (transformer + VAE) and FluxTextEncoders (Qwen3 text encoder).
    // Both must be redirected, otherwise the text encoder silently
    // lands in the wrong place and the pipeline throws "Klein text
    // encoder not loaded" at first generate.
    static func defaultRegistryRedirect(_ models: URL) {
        ModelRegistry.customModelsDirectory = models
        TextEncoderModelDownloader.customModelsDirectory = models
        TextEncoderModelDownloader.reconfigureHubApi()
    }

    // MARK: - Internals (root resolution + migrations)

    private static func resolveRoot(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Naturista", isDirectory: true)
    }

    private static func ensureDirectories(_ container: StorageContainer, fileManager: FileManager) {
        // Eagerly create the root and every subdirectory. Replaces the
        // load-bearing side-effect that `AppPaths.applicationSupport`
        // used to do on first read.
        if !fileManager.fileExists(atPath: container.root.path) {
            try? fileManager.createDirectory(at: container.root, withIntermediateDirectories: true)
        }
        for dir in container.directories {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // Pre-migration ~/.cache layout. Stable per-model directory names so
    // we can find the legacy location even when GemmaModel's enum cases
    // change.
    private static let legacyModelDirectories: [String] = [
        "gemma-4-31b-dense-4bit-mlx",
        "gemma-3-12b-it-4bit",
        "gemma-3-4b-it-4bit",
    ]

    private static let legacyModelMigratedFlag = "models.migratedToAppSupport.v1"

    private static func migrateLegacyModelCache(
        _ container: StorageContainer,
        fileManager: FileManager,
        userDefaults: UserDefaults
    ) {
        if userDefaults.bool(forKey: legacyModelMigratedFlag) { return }

        for directoryName in legacyModelDirectories {
            let source = URL(fileURLWithPath:
                NSString(string: "~/.cache/\(directoryName)").expandingTildeInPath)
            let destination = container.models.appendingPathComponent(directoryName, isDirectory: true)

            guard fileManager.fileExists(atPath: source.path) else { continue }
            if fileManager.fileExists(atPath: destination.path) {
                print("[storage] \(directoryName): destination already exists, skipping")
                continue
            }
            do {
                try fileManager.moveItem(at: source, to: destination)
                print("[storage] \(directoryName): moved to \(destination.path)")
            } catch {
                print("[storage] \(directoryName): FAILED — \(error.localizedDescription)")
            }
        }

        userDefaults.set(true, forKey: legacyModelMigratedFlag)
    }

    private static let sandboxMigratedFlag = "sandbox.containerMigratedV1"

    // One-shot pre-flip clone of `~/Library/Application Support/Naturista`
    // into `~/Library/Containers/<bundleId>/Data/Library/Application
    // Support/Naturista`, so that flipping `com.apple.security.app-sandbox`
    // to `true` doesn't strand the user's data. Idempotent: detects when
    // it's already running inside the container and no-ops.
    private static func migrateSandboxContainer(
        fileManager: FileManager,
        userDefaults: UserDefaults,
        cloner: SandboxCloner
    ) {
        if userDefaults.bool(forKey: sandboxMigratedFlag) { return }

        guard let bundleId = Bundle.main.bundleIdentifier else {
            print("[storage] no bundle id, skipping sandbox migrate")
            return
        }

        let liveAppSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        if liveAppSupport.path.contains("/Containers/") {
            print("[storage] already inside sandbox container, skipping")
            userDefaults.set(true, forKey: sandboxMigratedFlag)
            return
        }

        let home = fileManager.homeDirectoryForCurrentUser
        let unsandboxed = home
            .appendingPathComponent("Library/Application Support/Naturista", isDirectory: true)
        let containerRoot = home
            .appendingPathComponent("Library/Containers/\(bundleId)/Data/Library/Application Support/Naturista", isDirectory: true)

        guard fileManager.fileExists(atPath: unsandboxed.path) else {
            print("[storage] no unsandboxed data to migrate")
            userDefaults.set(true, forKey: sandboxMigratedFlag)
            return
        }

        // Don't clobber an existing populated container — the user may
        // have already run a sandboxed build.
        if let contents = try? fileManager.contentsOfDirectory(atPath: containerRoot.path),
           !contents.isEmpty {
            print("[storage] container already populated, skipping clone")
            userDefaults.set(true, forKey: sandboxMigratedFlag)
            return
        }

        do {
            try fileManager.createDirectory(
                at: containerRoot.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(at: containerRoot, withIntermediateDirectories: true)
        } catch {
            print("[storage] could not create container parent: \(error.localizedDescription)")
            return
        }

        do {
            try cloner.clone(from: unsandboxed, to: containerRoot)
        } catch {
            print("[storage] cp failed: \(error.localizedDescription); will retry next launch")
            return
        }

        print("[storage] cloned \(unsandboxed.path) → \(containerRoot.path)")
        userDefaults.set(true, forKey: sandboxMigratedFlag)
    }
}
