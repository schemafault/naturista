import AppKit
import Foundation

// Shared decoded-NSImage cache for the gallery. Without this, a 4×N
// LazyVGrid re-decodes the same JPEG every time a tile reappears
// (filter switch, scroll-back, navigation pop), which dominates frame
// time on large libraries. NSCache evicts under memory pressure and on
// totalCostLimit overrun. Pattern mirrors IdentificationCache in
// Sources/Models/Identification.swift.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 300
        c.totalCostLimit = 128 * 1024 * 1024
        return c
    }()

    private init() {}

    // Returns a decoded NSImage from cache, or loads-and-caches from disk.
    // Disk reads happen on a detached task so the caller's actor isn't
    // blocked. Returns nil only if the file is missing or undecodable.
    func image(for url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) {
            return hit
        }
        let loaded = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return NSImage(data: data)
        }.value
        if let loaded {
            cache.setObject(loaded, forKey: url as NSURL, cost: estimatedCost(of: loaded))
        }
        return loaded
    }

    func evict(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    private func estimatedCost(of image: NSImage) -> Int {
        let size = image.size
        let pixels = Int(size.width * size.height)
        return max(pixels * 4, 1)
    }
}
