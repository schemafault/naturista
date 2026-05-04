import Foundation

// MARK: - Errors

enum EntryPipelineError: Error, LocalizedError {
    case entryNotFound
    case identifyFailed(String)
    case illustrateFailed(String)
    case missingIdentification

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return "Entry not found in database."
        case .identifyFailed(let m):
            return "Identification failed: \(m)"
        case .illustrateFailed(let m):
            return "Illustration generation failed: \(m)"
        case .missingIdentification:
            return "Entry has no valid identification."
        }
    }
}

// MARK: - Ports
//
// Narrow protocols the pipeline drives. Each wraps one collaborator.
// Production conformances (in this file) adapt the existing singletons;
// tests substitute fakes via `EntryPipeline(deps:)`.

protocol IdentifierPort: Sendable {
    func identify(photoPath: String) async throws -> IdentificationResult
    func reidentify(
        photoPath: String,
        userCommonName: String?,
        userScientificName: String?
    ) async throws -> IdentificationResult
}

private struct ReidentifyUnimplemented: Error, LocalizedError {
    var errorDescription: String? { "reidentify is not implemented in this identifier." }
}

extension IdentifierPort {
    // Default so existing test fakes keep compiling. Real GemmaActor
    // overrides this; tests that exercise the correction flow can override
    // selectively in their fake.
    func reidentify(
        photoPath: String,
        userCommonName: String?,
        userScientificName: String?
    ) async throws -> IdentificationResult {
        throw ReidentifyUnimplemented()
    }
}

protocol IllustratorPort: Sendable {
    func generate(
        identification: IdentificationResult,
        entryId: UUID,
        referencePhotoPath: String?
    ) async throws -> String
}

extension IllustratorPort {
    // Default keeps existing test fakes that only implement the
    // text-to-image path compiling. Production FluxActor exposes the
    // full signature directly.
    func generate(identification: IdentificationResult, entryId: UUID) async throws -> String {
        try await generate(
            identification: identification,
            entryId: entryId,
            referencePhotoPath: nil
        )
    }
}

// Encodes the GPU-residency invariant in one place: identify work runs
// under the identification lease (Gemma stays warm), illustrate work
// under the illustration lease (FLUX releases eagerly). The pipeline
// body never names ModelLease or its tenant enum.
protocol LeasePort: Sendable {
    func withIdentify<T: Sendable>(_ work: () async throws -> T) async throws -> T
    func withIllustrate<T: Sendable>(_ work: () async throws -> T) async throws -> T
}

protocol ImagePort: Sendable {
    func extractMetadata(from url: URL) async throws -> ImageMetadata
    func createWorkingCopy(sourceURL: URL) async throws -> URL
    func createThumbnail(from sourceURL: URL) async throws -> URL
}

protocol DatabasePort: Sendable {
    func fetchEntry(id: String) async throws -> Entry?
    func saveEntry(_ entry: Entry) async throws
    func deleteEntry(id: String) async throws
}

protocol CachePort: Sendable {
    func evict(_ url: URL)
}

protocol FileImportPort: Sendable {
    // Copies the source file into AppPaths.originals as `{id}_original.jpg`
    // and returns the destination URL.
    func copyOriginal(from sourceURL: URL, id: String) throws -> URL
}

// MARK: - The pipeline

actor EntryPipeline {
    // Production singleton wired to real services. Tests construct their
    // own via `EntryPipeline(deps:)`.
    static let production = EntryPipeline()

    private let deps: Dependencies

    init(deps: Dependencies = .live) {
        self.deps = deps
    }

    // MARK: Public surface

    // Drag-and-drop entry point. Copies original, makes working copy +
    // best-effort thumbnail, saves the entry, runs Gemma identify, saves
    // again with the result or a failure marker. Returns the final entry
    // either way — callers inspect `.identification.status` to branch UI.
    @discardableResult
    func importPhoto(at sourceURL: URL) async throws -> Entry {
        let id = deps.newID().uuidString
        let originalURL = try deps.fileImport.copyOriginal(from: sourceURL, id: id)

        let metadata = try await deps.images.extractMetadata(from: sourceURL)
        let capturedAt = metadata.capturedAt.map { ISO8601DateFormatter().string(from: $0) }

        let workingURL = try await deps.images.createWorkingCopy(sourceURL: originalURL)
        let workingFilename = workingURL.lastPathComponent

        // Best-effort: a thumbnail failure here must not abort import.
        // ThumbnailBackfillService will retry on next launch for nil rows.
        var thumbnailFilename: String? = nil
        do {
            let thumbURL = try await deps.images.createThumbnail(from: workingURL)
            thumbnailFilename = thumbURL.lastPathComponent
        } catch {
            print("[pipeline] import thumbnail failed: \(error)")
        }

        var entry = Entry(
            id: id,
            createdAt: ISO8601DateFormatter().string(from: deps.clock()),
            capturedAt: capturedAt,
            originalImageFilename: originalURL.lastPathComponent,
            workingImageFilename: workingFilename,
            thumbnailFilename: thumbnailFilename
        )
        try await deps.db.saveEntry(entry)

        let workingPath = workingURL.path
        let identifier = deps.identifier
        do {
            let result = try await deps.lease.withIdentify {
                try await identifier.identify(photoPath: workingPath)
            }
            entry.setIdentification(.success(result))
            try await deps.db.saveEntry(entry)
        } catch {
            entry.setIdentification(.failure(error.localizedDescription))
            entry.userStatus = "failed"
            try await deps.db.saveEntry(entry)
        }

        return entry
    }

    // Idempotent: runs Gemma if identification is missing, then runs FLUX
    // and refreshes the thumbnail. Used by both "compose plate after
    // import" and "retry after a previous failure" — the entry's current
    // state determines what work runs.
    //
    // `preserveLayout` routes FLUX to image-to-image with the entry's
    // working photograph as a visual reference, so the illustration
    // borrows composition / pose from the photo. Roughly 1.5–2× slower
    // per generate; the UI labels it as such so users opt in knowingly.
    func illustrate(entryId: UUID, preserveLayout: Bool = false) async throws {
        guard var entry = try await deps.db.fetchEntry(id: entryId.uuidString) else {
            throw EntryPipelineError.entryNotFound
        }

        if entry.identification.result == nil {
            let workingPath = Storage.current.workingURL(for: entry).path
            let identifier = deps.identifier
            do {
                let result = try await deps.lease.withIdentify {
                    try await identifier.identify(photoPath: workingPath)
                }
                entry.setIdentification(.success(result))
                try await deps.db.saveEntry(entry)
            } catch {
                entry.setIdentification(.failure(error.localizedDescription))
                entry.userStatus = "failed"
                entry.notes = "Gemma identification failed: \(error.localizedDescription)"
                try await deps.db.saveEntry(entry)
                throw EntryPipelineError.identifyFailed(error.localizedDescription)
            }
        }

        guard let identification = entry.identification.result else {
            throw EntryPipelineError.missingIdentification
        }

        let referencePhotoPath = preserveLayout
            ? Storage.current.workingURL(for: entry).path
            : nil

        try await runIllustration(
            on: &entry,
            entryId: entryId,
            identification: identification,
            referencePhotoPath: referencePhotoPath,
            persistFailureToEntry: true
        )
    }

    // Gemma-only correction. Re-runs Gemma with the user-supplied common /
    // scientific name as authoritative, persists the corrected
    // identification, and returns the new result. Used by the import flow
    // (which has no illustration yet — FLUX runs on the subsequent Compose
    // step) and as the first leg of `correctIdentification`.
    @discardableResult
    func applyCorrectedIdentification(
        entryId: UUID,
        userCommonName: String?,
        userScientificName: String?
    ) async throws -> IdentificationResult {
        guard var entry = try await deps.db.fetchEntry(id: entryId.uuidString) else {
            throw EntryPipelineError.entryNotFound
        }

        let workingPath = Storage.current.workingURL(for: entry).path
        let identifier = deps.identifier
        let result: IdentificationResult
        do {
            result = try await deps.lease.withIdentify {
                try await identifier.reidentify(
                    photoPath: workingPath,
                    userCommonName: userCommonName,
                    userScientificName: userScientificName
                )
            }
        } catch {
            throw EntryPipelineError.identifyFailed(error.localizedDescription)
        }

        entry.setIdentification(.success(result))
        try await deps.db.saveEntry(entry)
        return result
    }

    // User-corrected identification with downstream re-illustration.
    // Persists the corrected identification BEFORE FLUX so a FLUX failure
    // preserves the correction; failure handling matches `regenerate`
    // (user-initiated, never marks the entry as failed). Used by the entry
    // detail panel where an illustration already exists and must be
    // refreshed.
    func correctIdentification(
        entryId: UUID,
        userCommonName: String?,
        userScientificName: String?
    ) async throws {
        let result = try await applyCorrectedIdentification(
            entryId: entryId,
            userCommonName: userCommonName,
            userScientificName: userScientificName
        )
        guard var entry = try await deps.db.fetchEntry(id: entryId.uuidString) else {
            throw EntryPipelineError.entryNotFound
        }
        try await runIllustration(
            on: &entry,
            entryId: entryId,
            identification: result,
            referencePhotoPath: nil,
            persistFailureToEntry: false
        )
    }

    // Force re-run FLUX on the existing identification. Caller must have
    // an entry with a valid identification — otherwise throws.
    // Distinct from `illustrate(entryId:)` in two ways: it ALWAYS runs
    // FLUX even if an illustration exists (overwrites), and on failure it
    // does NOT mark userStatus="failed" (this is a user-initiated retry,
    // not a fresh pipeline run; we don't want to pollute the entry with
    // a failure marker just because the user clicked Regenerate).
    //
    // `preserveLayout` mirrors `illustrate(...)`: routes FLUX to img2img
    // with the entry's working photograph as a visual reference.
    func regenerate(entryId: UUID, preserveLayout: Bool = false) async throws {
        guard var entry = try await deps.db.fetchEntry(id: entryId.uuidString) else {
            throw EntryPipelineError.entryNotFound
        }
        guard let identification = entry.identification.result else {
            throw EntryPipelineError.missingIdentification
        }

        let referencePhotoPath = preserveLayout
            ? Storage.current.workingURL(for: entry).path
            : nil

        try await runIllustration(
            on: &entry,
            entryId: entryId,
            identification: identification,
            referencePhotoPath: referencePhotoPath,
            persistFailureToEntry: false
        )
    }

    // Removes every artifact the entry owns (original, working,
    // thumbnail, illustration, plate), evicts the image cache for each,
    // then deletes the database row.
    func delete(entryId: UUID) async throws {
        if let entry = try await deps.db.fetchEntry(id: entryId.uuidString) {
            let fm = FileManager.default
            for url in Storage.current.files(for: entry) {
                try? fm.removeItem(at: url)
                deps.cache.evict(url)
            }
        }
        try await deps.db.deleteEntry(id: entryId.uuidString)
    }

    // MARK: - Internals

    // Single FLUX-success path used by both illustrate and regenerate.
    // Owns: lease wrapping, save-on-success, thumbnail refresh, and the
    // (different) failure-handling policy controlled by the flag.
    private func runIllustration(
        on entry: inout Entry,
        entryId: UUID,
        identification: IdentificationResult,
        referencePhotoPath: String?,
        persistFailureToEntry: Bool
    ) async throws {
        let illustrator = deps.illustrator
        do {
            let illustrationPath = try await deps.lease.withIllustrate {
                try await illustrator.generate(
                    identification: identification,
                    entryId: entryId,
                    referencePhotoPath: referencePhotoPath
                )
            }
            entry.illustrationFilename = URL(fileURLWithPath: illustrationPath).lastPathComponent
            await refreshThumbnail(for: &entry, illustrationPath: illustrationPath)
            entry.userStatus = "unreviewed"
            try await deps.db.saveEntry(entry)
        } catch {
            if persistFailureToEntry {
                entry.userStatus = "failed"
                entry.notes = "FLUX generation failed: \(error.localizedDescription)"
                try await deps.db.saveEntry(entry)
            }
            throw EntryPipelineError.illustrateFailed(error.localizedDescription)
        }
    }

    // After FLUX completes, the gallery should preview the finished
    // plate rather than the working photograph. Regenerate the thumbnail
    // from the new illustration, delete the prior thumbnail file, and
    // evict the cache so SwiftUI redecodes on next access. Best-effort:
    // a failure here leaves the entry with the prior thumbnail intact.
    private func refreshThumbnail(for entry: inout Entry, illustrationPath: String) async {
        let illustrationURL = URL(fileURLWithPath: illustrationPath)
        // Illustration filenames are deterministic ({entryId}_illustration.png),
        // so a regen overwrites the same path. ImageCache keys on URL — without
        // this eviction views keep showing the previously decoded NSImage until
        // app relaunch.
        deps.cache.evict(illustrationURL)
        do {
            let newThumbURL = try await deps.images.createThumbnail(from: illustrationURL)
            let oldFilename = entry.thumbnailFilename
            entry.thumbnailFilename = newThumbURL.lastPathComponent
            if let oldFilename, oldFilename != newThumbURL.lastPathComponent {
                let oldURL = Storage.current.thumbnails.appendingPathComponent(oldFilename)
                try? FileManager.default.removeItem(at: oldURL)
                deps.cache.evict(oldURL)
            }
        } catch {
            print("[pipeline] thumbnail regen failed: \(error)")
        }
    }
}

// MARK: - Dependencies

extension EntryPipeline {
    struct Dependencies: Sendable {
        var fileImport: FileImportPort
        var images: ImagePort
        var identifier: IdentifierPort
        var illustrator: IllustratorPort
        var lease: LeasePort
        var db: DatabasePort
        var cache: CachePort
        var clock: @Sendable () -> Date
        var newID: @Sendable () -> UUID

        static let live = Dependencies(
            fileImport: LiveFileImport(),
            images: LiveImage(),
            identifier: GemmaActor.shared,
            illustrator: FluxActor.shared,
            lease: LiveLease(),
            db: DatabaseService.shared,
            cache: ImageCache.shared,
            clock: { Date() },
            newID: { UUID() }
        )
    }
}

// MARK: - Production port adapters

// Each adapter is a one-line shim onto an existing actor / singleton.
// Lives in this file because they're the production wiring; nobody else
// needs them.

private struct LiveFileImport: FileImportPort {
    func copyOriginal(from sourceURL: URL, id: String) throws -> URL {
        let originalFilename = "\(id)_original.jpg"
        let destination = Storage.current.originals.appendingPathComponent(originalFilename)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }
}

// `ImageService.createWorkingCopy` and `createThumbnail` carry default-
// valued parameters (maxPixels, maxPixelSize, jpegQuality) that the
// pipeline doesn't override. A direct extension can't satisfy the port
// because the selectors differ, so wrap.
private struct LiveImage: ImagePort {
    func extractMetadata(from url: URL) async throws -> ImageMetadata {
        try await ImageService.shared.extractMetadata(from: url)
    }
    func createWorkingCopy(sourceURL: URL) async throws -> URL {
        try await ImageService.shared.createWorkingCopy(sourceURL: sourceURL)
    }
    func createThumbnail(from sourceURL: URL) async throws -> URL {
        try await ImageService.shared.createThumbnail(from: sourceURL)
    }
}

extension GemmaActor: IdentifierPort {}

extension FluxActor: IllustratorPort {}

extension DatabaseService: DatabasePort {}

extension ImageCache: CachePort {}

// Wraps `ModelLease.shared.withExclusive(_:_:)` and pins each side to
// its tenant. The pipeline never names ModelLeaseTenant; this adapter
// is the one place that mapping lives.
private struct LiveLease: LeasePort {
    func withIdentify<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        try await ModelLease.shared.withExclusive(.identification, work)
    }
    func withIllustrate<T: Sendable>(_ work: () async throws -> T) async throws -> T {
        try await ModelLease.shared.withExclusive(.illustration, work)
    }
}
