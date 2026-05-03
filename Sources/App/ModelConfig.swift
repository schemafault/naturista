import Foundation

enum ModelConfig {
    // Computed so a model swap via the picker takes effect on the next
    // GemmaActor restart without needing app-relaunch.
    static var gemmaPath: String { GemmaModelStore.shared.selected.localCachePath }
}

// MARK: - Identification model registry

enum GemmaModel: String, CaseIterable, Identifiable, Sendable {
    case gemma4_31b
    case gemma3_12b
    case gemma3_4b

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma4_31b:        return "Gemma 4 31B"
        case .gemma3_12b:        return "Gemma 3 12B"
        case .gemma3_4b:         return "Gemma 3 4B"
        }
    }

    var hfRepo: String {
        switch self {
        case .gemma4_31b:        return "mlx-community/gemma-4-31b-it-4bit"
        case .gemma3_12b:        return "mlx-community/gemma-3-12b-it-4bit"
        case .gemma3_4b:         return "mlx-community/gemma-3-4b-it-4bit"
        }
    }

    // Per-model directory name. Kept as a stable identifier so
    // ModelStorageMigrator can find the legacy ~/.cache/<dirName> location
    // and move it under AppPaths.models on launch.
    var directoryName: String {
        switch self {
        case .gemma4_31b:        return "gemma-4-31b-dense-4bit-mlx"
        case .gemma3_12b:        return "gemma-3-12b-it-4bit"
        case .gemma3_4b:         return "gemma-3-4b-it-4bit"
        }
    }

    var localCachePath: String {
        AppPaths.models.appendingPathComponent(directoryName, isDirectory: true).path
    }

    // Pre-migration ~/.cache location, kept only so the migrator can find it.
    var legacyCachePath: String {
        NSString(string: "~/.cache/\(directoryName)").expandingTildeInPath
    }

    var approxSizeGB: Double {
        switch self {
        case .gemma4_31b:        return 17
        case .gemma3_12b:        return 7.5
        case .gemma3_4b:         return 3.2
        }
    }

    var blurb: String {
        switch self {
        case .gemma4_31b:        return "Original. Strongest on long-tail species."
        case .gemma3_12b:        return "Default. Half the memory of 31B with comparable accuracy on common species."
        case .gemma3_4b:         return "Lightest. Fastest. Weaker on rare species."
        }
    }

    var isInstalled: Bool {
        let expanded = NSString(string: localCachePath).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.appendingPathComponent("config.json").path) else { return false }
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return false }
        return contents.contains(where: { $0.hasSuffix(".safetensors") })
    }

    // RAM/disk floors per model. ModelLease guarantees Gemma and FLUX are
    // never resident simultaneously, so these reflect each model loaded
    // alone. Min = "will probably load," Recommended = "will run smoothly."
    var requirements: ModelRequirements {
        switch self {
        case .gemma3_4b:         return ModelRequirements(minRAMGB: 8,  recommendedRAMGB: 16, minDiskGB: 5)
        case .gemma3_12b:        return ModelRequirements(minRAMGB: 16, recommendedRAMGB: 24, minDiskGB: 10)
        case .gemma4_31b:        return ModelRequirements(minRAMGB: 24, recommendedRAMGB: 36, minDiskGB: 20)
        }
    }

    func compatibility(on capability: SystemCapability = .current) -> ModelCompatibility {
        if !capability.isAppleSilicon {
            return .incompatible(reason: "Requires Apple Silicon. This Mac reports \(capability.chipModel).")
        }
        let req = requirements
        let ram = capability.physicalMemoryGB
        let ramRounded = Int(ram.rounded())
        if ram < req.minRAMGB - 0.5 {
            return .incompatible(
                reason: "Needs \(formatGB(req.minRAMGB)) RAM. This Mac has \(ramRounded) GB."
            )
        }
        if ram < req.recommendedRAMGB - 0.5 {
            return .marginal(
                reason: "May be slow on \(ramRounded) GB. \(formatGB(req.recommendedRAMGB)) recommended."
            )
        }
        return .compatible
    }

    private func formatGB(_ gb: Double) -> String {
        gb.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(gb)) GB"
            : String(format: "%.1f GB", gb)
    }
}

struct ModelRequirements {
    let minRAMGB: Double
    let recommendedRAMGB: Double
    let minDiskGB: Double
}

enum ModelCompatibility: Equatable {
    case compatible
    case marginal(reason: String)
    case incompatible(reason: String)

    var isSelectable: Bool {
        switch self {
        case .compatible, .marginal: return true
        case .incompatible: return false
        }
    }

    var reason: String? {
        switch self {
        case .compatible: return nil
        case .marginal(let r), .incompatible(let r): return r
        }
    }
}

// User's chosen identification model. UserDefaults-backed.
final class GemmaModelStore: @unchecked Sendable {
    static let shared = GemmaModelStore()

    private let key = "gemma.selectedModel"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var selected: GemmaModel {
        if let raw = userDefaults.string(forKey: key), let m = GemmaModel(rawValue: raw) {
            return m
        }
        return .gemma3_12b
    }

    func setSelected(_ model: GemmaModel) {
        userDefaults.set(model.rawValue, forKey: key)
    }
}

// Fetches MLX weights from Hugging Face directly via URLSession. No Python
// venv / hf CLI subprocess — sandbox-eligible, and the only entitlement
// needed is com.apple.security.network.client. Files land where Python's
// loader expects them.
actor GemmaModelDownloader {
    enum DownloadError: Error, LocalizedError {
        case insufficientDisk(neededGB: Double, availableGB: Double)
        case failed(message: String)

        var errorDescription: String? {
            switch self {
            case .insufficientDisk(let needed, let available):
                return String(
                    format: "Not enough free disk: needs %.0f GB, only %.1f GB available.",
                    needed, available
                )
            case .failed(let m):
                return "Download failed: \(m)"
            }
        }
    }

    static let shared = GemmaModelDownloader()

    func download(_ model: GemmaModel) async throws {
        if model.isInstalled { return }

        let target = URL(fileURLWithPath: model.localCachePath)

        do {
            try await HuggingFaceDownloader().download(
                repo: model.hfRepo,
                into: target,
                minDiskGB: model.requirements.minDiskGB
            )
        } catch let HuggingFaceDownloader.Error.insufficientDisk(needed, available) {
            throw DownloadError.insufficientDisk(neededGB: needed, availableGB: available)
        } catch {
            throw DownloadError.failed(message: error.localizedDescription)
        }

        if !model.isInstalled {
            throw DownloadError.failed(message: "Model files missing after download.")
        }
    }

    // Removes the on-disk weights for `model`. The enum entry stays, so the
    // picker still shows the option and a future Save will re-download.
    // Caller is responsible for shutting down any subprocess that has the
    // weights memory-mapped before invoking this.
    func delete(_ model: GemmaModel) throws {
        let dir = NSString(string: model.localCachePath).expandingTildeInPath
        let url = URL(fileURLWithPath: dir)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            throw DownloadError.failed(message: error.localizedDescription)
        }
    }
}

// MARK: - App paths

enum AppPaths {
    static var applicationSupport: URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let naturista = appSupport.appendingPathComponent("Naturista", isDirectory: true)
        if !fm.fileExists(atPath: naturista.path) {
            try? fm.createDirectory(at: naturista, withIntermediateDirectories: true)
        }
        return naturista
    }

    static var database: URL {
        applicationSupport.appendingPathComponent("naturista.sqlite")
    }

    static var assets: URL {
        applicationSupport.appendingPathComponent("assets", isDirectory: true)
    }

    static var originals: URL {
        assets.appendingPathComponent("originals", isDirectory: true)
    }

    static var working: URL {
        assets.appendingPathComponent("working", isDirectory: true)
    }

    static var thumbnails: URL {
        assets.appendingPathComponent("thumbnails", isDirectory: true)
    }

    static var generated: URL {
        applicationSupport.appendingPathComponent("generated", isDirectory: true)
    }

    static var illustrations: URL {
        generated.appendingPathComponent("illustrations", isDirectory: true)
    }

    static var plates: URL {
        generated.appendingPathComponent("plates", isDirectory: true)
    }

    static var models: URL {
        applicationSupport.appendingPathComponent("models", isDirectory: true)
    }

    static func ensureDirectories() {
        let dirs = [assets, originals, working, thumbnails, generated, illustrations, plates, models]
        let fm = FileManager.default
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}

// MARK: - Hugging Face downloader
//
// Mirrors a public HF repo's `main` branch into a target directory using
// URLSession. No subprocess, no Python. Intended for MLX weight repos
// (mlx-community/...) which are unauthenticated.
//
// - Uses HF's tree API with `recursive=true` to list every file.
// - Bounded concurrency (default 4) — matches what hf CLI does.
// - Resume across runs: an already-present file at the final path is
//   skipped; an interrupted download leaves a `<file>.partial` that gets
//   replaced on the next attempt.
// - Disk precheck up front so a 17 GB download doesn't fail halfway through.
struct HuggingFaceDownloader {
    enum Error: Swift.Error, LocalizedError {
        case insufficientDisk(neededGB: Double, availableGB: Double)
        case treeListFailed(repo: String, status: Int)
        case downloadFailed(file: String, status: Int)
        case ioFailure(file: String, underlying: Swift.Error)

        var errorDescription: String? {
            switch self {
            case .insufficientDisk(let needed, let available):
                return String(format: "Not enough free disk: needs %.0f GB, only %.1f GB available.", needed, available)
            case .treeListFailed(let repo, let status):
                return "Failed to list repo \(repo): HTTP \(status)."
            case .downloadFailed(let file, let status):
                return "Failed to download \(file): HTTP \(status)."
            case .ioFailure(let file, let underlying):
                return "I/O error writing \(file): \(underlying.localizedDescription)"
            }
        }
    }

    private struct TreeEntry: Decodable {
        let path: String
        let type: String   // "file" | "directory"
    }

    let session: URLSession
    let maxConcurrent: Int

    init(session: URLSession = .shared, maxConcurrent: Int = 4) {
        self.session = session
        self.maxConcurrent = maxConcurrent
    }

    func download(
        repo: String,
        into directory: URL,
        minDiskGB: Double = 0,
        progress: (@Sendable (_ filesDone: Int, _ filesTotal: Int) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if minDiskGB > 0,
           let availableGB = SystemCapability.current.availableDiskGB(at: directory),
           availableGB < minDiskGB {
            throw Error.insufficientDisk(neededGB: minDiskGB, availableGB: availableGB)
        }

        let entries = try await listTree(repo: repo)
        let files = entries.filter { $0.type == "file" }.map(\.path)

        let counter = DownloadCounter(total: files.count, progress: progress)
        await counter.report()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = files.makeIterator()
            // Seed up to maxConcurrent.
            for _ in 0..<maxConcurrent {
                guard let next = iterator.next() else { break }
                group.addTask {
                    try await fetchFile(repo: repo, path: next, into: directory)
                }
            }
            // As each finishes, enqueue the next.
            while try await group.next() != nil {
                await counter.increment()
                if let next = iterator.next() {
                    group.addTask {
                        try await fetchFile(repo: repo, path: next, into: directory)
                    }
                }
            }
        }
    }

    private func listTree(repo: String) async throws -> [TreeEntry] {
        var components = URLComponents(string: "https://huggingface.co/api/models/\(repo)/tree/main")!
        components.queryItems = [URLQueryItem(name: "recursive", value: "true")]
        let url = components.url!

        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Error.treeListFailed(repo: repo, status: status)
        }
        return try JSONDecoder().decode([TreeEntry].self, from: data)
    }

    private func fetchFile(repo: String, path: String, into directory: URL) async throws {
        let target = directory.appendingPathComponent(path)
        let parent = target.deletingLastPathComponent()
        let fm = FileManager.default
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        // Resume: skip files we already have. Lets a re-run after Cmd-Q
        // pick up where it left off without re-downloading 12 GB.
        if fm.fileExists(atPath: target.path) { return }

        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(path)")!
        let (tmpURL, response) = try await session.download(from: url)
        defer { try? fm.removeItem(at: tmpURL) }

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw Error.downloadFailed(file: path, status: status)
        }

        // Two-step rename: tmp → <name>.partial → <name>. Quarantines a
        // half-written file across crashes so a future run can detect it.
        let partial = target.appendingPathExtension("partial")
        if fm.fileExists(atPath: partial.path) {
            try? fm.removeItem(at: partial)
        }
        do {
            try fm.moveItem(at: tmpURL, to: partial)
            try fm.moveItem(at: partial, to: target)
        } catch {
            throw Error.ioFailure(file: path, underlying: error)
        }
    }
}

// Actor purely so the progress callback fires on a stable executor and we
// don't tear up the value-type Downloader with mutable state.
private actor DownloadCounter {
    private var done: Int = 0
    private let total: Int
    private let progress: (@Sendable (Int, Int) -> Void)?

    init(total: Int, progress: (@Sendable (Int, Int) -> Void)?) {
        self.total = total
        self.progress = progress
    }

    func report() { progress?(done, total) }

    func increment() {
        done += 1
        progress?(done, total)
    }
}

// MARK: - Legacy ~/.cache → AppPaths.models migration
//
// One-shot launch migration. ~/.cache/ is purgeable by macOS, so users can
// lose 17 GB of weights to a "Free up storage" prompt and not understand
// why a generate call now wants to re-download. Idempotent: a successful
// pass sets the UserDefaults flag and subsequent launches no-op. Per-model
// failures are logged and skipped — they do not block app launch.
enum ModelStorageMigrator {
    private static let completedFlag = "models.migratedToAppSupport.v1"

    static func migrateIfNeeded(userDefaults: UserDefaults = .standard,
                                fileManager: FileManager = .default) {
        if userDefaults.bool(forKey: completedFlag) { return }

        // Only Gemma weights are migrated. The legacy mflux FLUX layout
        // is gone — Flux2Core uses a different on-disk structure
        // (black-forest-labs/...) and re-downloads on first use.
        let pairs: [(label: String, source: URL, destination: URL)] =
            GemmaModel.allCases.map { model in
                (model.directoryName,
                 URL(fileURLWithPath: model.legacyCachePath),
                 URL(fileURLWithPath: model.localCachePath))
            }

        try? fileManager.createDirectory(at: AppPaths.models,
                                         withIntermediateDirectories: true)

        for pair in pairs {
            guard fileManager.fileExists(atPath: pair.source.path) else { continue }

            if fileManager.fileExists(atPath: pair.destination.path) {
                print("[migrate] \(pair.label): destination already exists, skipping (\(pair.source.path))")
                continue
            }

            do {
                try fileManager.moveItem(at: pair.source, to: pair.destination)
                print("[migrate] \(pair.label): moved to \(pair.destination.path)")
            } catch {
                print("[migrate] \(pair.label): FAILED — \(error.localizedDescription)")
            }
        }

        userDefaults.set(true, forKey: completedFlag)
    }
}
