import Foundation

enum ModelConfig {
    static let gemmaPath = "~/.cache/gemma-4-31b-dense-4bit-mlx"
    static let fluxPath = "~/.cache/flux-schnell-mlx"
}

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