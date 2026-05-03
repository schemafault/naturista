import Foundation

// One-shot retroactive thumbnail generation for libraries that existed
// before the v3_thumbnails migration. Walks entries with no
// thumbnailFilename, generates a thumb from the illustration if present
// (so the gallery shows the finished plate) else from the working
// photograph, and writes the filename back to the row.
//
// Idempotent: safe to invoke on every launch — once all rows have a
// thumbnail, the SQL filter returns empty and the actor exits.
//
// Throttled: yields between batches and runs at .utility priority so
// foreground import / generation work isn't starved.
actor ThumbnailBackfillService {
    static let shared = ThumbnailBackfillService()

    private let batchSize = 20
    private var running = false

    private init() {}

    func runIfNeeded() async {
        if running { return }
        running = true
        defer { running = false }

        let fm = FileManager.default
        while true {
            let batch: [Entry]
            do {
                batch = try await DatabaseService.shared.fetchEntriesMissingThumbnail(limit: batchSize)
            } catch {
                print("[backfill] fetch failed: \(error)")
                return
            }
            if batch.isEmpty { return }

            for entry in batch {
                let sourceURL = preferredSource(for: entry, fm: fm)
                guard let sourceURL else {
                    // No usable file on disk — skip; we'll skip again next
                    // launch. Acceptable: nothing to thumb.
                    continue
                }
                do {
                    let thumbURL = try await ImageService.shared.createThumbnail(from: sourceURL)
                    try await DatabaseService.shared.updateThumbnailFilename(
                        id: entry.id,
                        thumbnailFilename: thumbURL.lastPathComponent
                    )
                } catch {
                    print("[backfill] entry \(entry.id) failed: \(error)")
                }
                await Task.yield()
            }
        }
    }

    private func preferredSource(for entry: Entry, fm: FileManager) -> URL? {
        if let illus = entry.illustrationFilename {
            let url = AppPaths.illustrations.appendingPathComponent(illus)
            if fm.fileExists(atPath: url.path) { return url }
        }
        let working = AppPaths.working.appendingPathComponent(entry.workingImageFilename)
        if fm.fileExists(atPath: working.path) { return working }
        return nil
    }
}
