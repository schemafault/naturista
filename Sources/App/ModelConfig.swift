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
    case qwen25vl_7b

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemma4_31b:  return "Gemma 4 31B"
        case .gemma3_12b:  return "Gemma 3 12B"
        case .gemma3_4b:   return "Gemma 3 4B"
        case .qwen25vl_7b: return "Qwen 2.5-VL 7B"
        }
    }

    var hfRepo: String {
        switch self {
        case .gemma4_31b:  return "mlx-community/gemma-4-31b-it-4bit"
        case .gemma3_12b:  return "mlx-community/gemma-3-12b-it-4bit"
        case .gemma3_4b:   return "mlx-community/gemma-3-4b-it-4bit"
        case .qwen25vl_7b: return "mlx-community/Qwen2.5-VL-7B-Instruct-4bit"
        }
    }

    // 31B intentionally points at the user's existing custom-named directory
    // so we don't trigger a re-download for an already-installed model.
    var localCachePath: String {
        switch self {
        case .gemma4_31b:  return "~/.cache/gemma-4-31b-dense-4bit-mlx"
        case .gemma3_12b:  return "~/.cache/gemma-3-12b-it-4bit"
        case .gemma3_4b:   return "~/.cache/gemma-3-4b-it-4bit"
        case .qwen25vl_7b: return "~/.cache/Qwen2.5-VL-7B-Instruct-4bit"
        }
    }

    var approxSizeGB: Double {
        switch self {
        case .gemma4_31b:  return 17
        case .gemma3_12b:  return 7.5
        case .gemma3_4b:   return 3.2
        case .qwen25vl_7b: return 5
        }
    }

    var blurb: String {
        switch self {
        case .gemma4_31b:  return "Original. Strongest on long-tail species."
        case .gemma3_12b:  return "Default. Half the memory of 31B with comparable accuracy on common species."
        case .gemma3_4b:   return "Lightest. Fastest. Weaker on rare species."
        case .qwen25vl_7b: return "Alternative VLM family. Strong general instruction following."
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
        case failed(message: String)

        var errorDescription: String? {
            switch self {
            case .hfNotFound(let p):
                return "huggingface-cli not found at \(p). Install the Naturista Python environment first."
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
        let dirs = [assets, originals, working, generated, illustrations, plates, models]
        let fm = FileManager.default
        for dir in dirs {
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
