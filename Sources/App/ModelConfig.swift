import Foundation

enum ModelConfig {
    // Computed so a model swap via the picker takes effect on the next
    // GemmaActor restart without needing app-relaunch.
    static var gemmaPath: String { GemmaModelStore.shared.selected.localCachePath }
    static let pythonPath = "~/.cache/naturista-venv/bin/python3"
}

// MARK: - Identification model registry

enum GemmaModel: String, CaseIterable, Identifiable, Sendable {
    case gemma4_31b
    case gemma3_12b
    case gemma3_4b
    case llama32vision_11b

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma4_31b:        return "Gemma 4 31B"
        case .gemma3_12b:        return "Gemma 3 12B"
        case .gemma3_4b:         return "Gemma 3 4B"
        case .llama32vision_11b: return "Llama 3.2 Vision 11B"
        }
    }

    var hfRepo: String {
        switch self {
        case .gemma4_31b:        return "mlx-community/gemma-4-31b-it-4bit"
        case .gemma3_12b:        return "mlx-community/gemma-3-12b-it-4bit"
        case .gemma3_4b:         return "mlx-community/gemma-3-4b-it-4bit"
        case .llama32vision_11b: return "mlx-community/Llama-3.2-11B-Vision-Instruct-4bit"
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
        case .llama32vision_11b: return "Llama-3.2-11B-Vision-Instruct-4bit"
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
        case .llama32vision_11b: return 5.6
        }
    }

    var blurb: String {
        switch self {
        case .gemma4_31b:        return "Original. Strongest on long-tail species."
        case .gemma3_12b:        return "Default. Half the memory of 31B with comparable accuracy on common species."
        case .gemma3_4b:         return "Lightest. Fastest. Weaker on rare species."
        case .llama32vision_11b: return "Different VLM family (Meta). Slower per photo; useful as a second opinion."
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
        case .llama32vision_11b: return ModelRequirements(minRAMGB: 16, recommendedRAMGB: 24, minDiskGB: 8)
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

// Shells out to the naturista-venv hf CLI to fetch MLX weights. The hf binary
// lives in the same venv that hosts mlx-vlm, so a successful run leaves the
// model where Python's loader expects it.
actor GemmaModelDownloader {
    enum DownloadError: Error, LocalizedError {
        case hfNotFound(path: String)
        case insufficientDisk(neededGB: Double, availableGB: Double)
        case failed(message: String)

        var errorDescription: String? {
            switch self {
            case .hfNotFound(let p):
                return "huggingface-cli not found at \(p). Install the Naturista Python environment first."
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

        let hfPath = NSString(string: "~/.cache/naturista-venv/bin/hf").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: hfPath) else {
            throw DownloadError.hfNotFound(path: hfPath)
        }

        let localDir = NSString(string: model.localCachePath).expandingTildeInPath

        // Refuse before launching hf if the volume can't hold the weights —
        // hf would otherwise fill the disk and surface a confusing error
        // mid-download. We probe the parent so the check works even if the
        // localDir doesn't exist yet.
        let targetURL = URL(fileURLWithPath: localDir)
        if let availableGB = SystemCapability.current.availableDiskGB(at: targetURL) {
            let needed = model.requirements.minDiskGB
            if availableGB < needed {
                throw DownloadError.insufficientDisk(neededGB: needed, availableGB: availableGB)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: hfPath)
        process.arguments = ["download", model.hfRepo, "--local-dir", localDir]

        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            throw DownloadError.failed(message: error.localizedDescription)
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in cont.resume() }
        }

        if process.terminationStatus != 0 {
            let errOut = (try? stderr.fileHandleForReading.readToEnd()) ?? Data()
            let raw = String(data: errOut, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw DownloadError.failed(message: String(raw.suffix(400)))
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

    // mflux 4-bit FLUX.2 Klein weights. The Python flux service reads its
    // location from FLUX_MODEL_PATH (FluxActor injects this), so the
    // directory name only needs to stay in sync with the migrator.
    static var fluxModel: URL {
        models.appendingPathComponent("flux2-klein-4b-mflux-4bit", isDirectory: true)
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

        let pairs: [(label: String, source: URL, destination: URL)] =
            GemmaModel.allCases.map { model in
                (model.directoryName,
                 URL(fileURLWithPath: model.legacyCachePath),
                 URL(fileURLWithPath: model.localCachePath))
            }
            + [(
                "flux2-klein-4b-mflux-4bit",
                URL(fileURLWithPath: NSString(string: "~/.cache/flux2-klein-4b-mflux-4bit").expandingTildeInPath),
                AppPaths.fluxModel
            )]

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
