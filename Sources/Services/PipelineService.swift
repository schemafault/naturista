import Foundation

enum PipelineError: Error, LocalizedError {
    case entryNotFound
    case gemmaFailed(String)
    case fluxFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return "Entry not found in database."
        case .gemmaFailed(let message):
            return "Gemma identification failed: \(message)"
        case .fluxFailed(let message):
            return "FLUX illustration generation failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}

actor PipelineService {
    static let shared = PipelineService()

    private init() {}

    func deleteEntry(entryId: UUID) async throws {
        let entry = try await DatabaseService.shared.fetchEntry(id: entryId.uuidString)

        if let entry = entry {
            let fm = FileManager.default
            let candidates: [URL] = [
                AppPaths.originals.appendingPathComponent(entry.originalImageFilename),
                AppPaths.working.appendingPathComponent(entry.workingImageFilename),
                entry.illustrationFilename.map { AppPaths.illustrations.appendingPathComponent($0) },
                entry.plateFilename.map { AppPaths.plates.appendingPathComponent($0) },
            ].compactMap { $0 }

            for url in candidates where fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        try await DatabaseService.shared.deleteEntry(id: entryId.uuidString)
    }

    // Re-runs FLUX on the existing identification to produce a fresh
    // illustration. The plate composition is rendered live by SwiftUI,
    // so there's nothing else to recompose.
    func regenerateIllustration(entryId: UUID) async throws {
        print("[regenerate] start entryId=\(entryId.uuidString)")
        guard var currentEntry = try await DatabaseService.shared.fetchEntry(id: entryId.uuidString) else {
            throw PipelineError.entryNotFound
        }
        print("[regenerate] existing illustrationFilename=\(currentEntry.illustrationFilename ?? "<nil>")")

        guard let identification = currentEntry.identification.result else {
            throw PipelineError.gemmaFailed("Entry has no valid identification.")
        }

        do {
            let illustrationPath = try await ModelLease.shared.withExclusive(.illustration) {
                try await FluxActor.shared.generate(
                    identification: identification,
                    entryId: entryId
                )
            }
            print("[regenerate] FluxActor returned path=\(illustrationPath)")
            let attrs = try? FileManager.default.attributesOfItem(atPath: illustrationPath)
            let size = (attrs?[.size] as? Int) ?? -1
            let mtime = (attrs?[.modificationDate] as? Date)?.description ?? "<unknown>"
            print("[regenerate] file size=\(size) mtime=\(mtime)")
            currentEntry.illustrationFilename = URL(fileURLWithPath: illustrationPath).lastPathComponent
            try await DatabaseService.shared.saveEntry(currentEntry)
            print("[regenerate] saved illustrationFilename=\(currentEntry.illustrationFilename ?? "<nil>")")
        } catch {
            print("[regenerate] error: \(error)")
            throw PipelineError.fluxFailed(error.localizedDescription)
        }
    }

    // Pipeline now stops once FLUX has produced an illustration. The
    // herbarium plate is rendered live by SwiftUI, so there's no
    // post-processing step to bake text into a PNG.
    func runIllustration(entryId: UUID) async throws {
        guard var currentEntry = try await DatabaseService.shared.fetchEntry(id: entryId.uuidString) else {
            throw PipelineError.entryNotFound
        }

        guard let identification = currentEntry.identification.result else {
            throw PipelineError.gemmaFailed("Entry has no valid identification.")
        }

        do {
            let illustrationPath = try await ModelLease.shared.withExclusive(.illustration) {
                try await FluxActor.shared.generate(
                    identification: identification,
                    entryId: entryId
                )
            }
            currentEntry.illustrationFilename = URL(fileURLWithPath: illustrationPath).lastPathComponent
            currentEntry.userStatus = "unreviewed"
            try await DatabaseService.shared.saveEntry(currentEntry)
        } catch {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "FLUX generation failed: \(error.localizedDescription)"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.fluxFailed(error.localizedDescription)
        }
    }

    func runFullPipeline(entryId: UUID) async throws {
        guard var currentEntry = try await DatabaseService.shared.fetchEntry(id: entryId.uuidString) else {
            throw PipelineError.entryNotFound
        }

        let workingPath = AppPaths.working.appendingPathComponent(currentEntry.workingImageFilename).path

        let identification: IdentificationResult
        do {
            let result = try await ModelLease.shared.withExclusive(.identification) {
                try await GemmaActor.shared.identify(photoPath: workingPath)
            }
            currentEntry.setIdentification(.success(result))
            try await DatabaseService.shared.saveEntry(currentEntry)
            identification = result
        } catch {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "Gemma identification failed: \(error.localizedDescription)"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.gemmaFailed(error.localizedDescription)
        }

        do {
            let illustrationPath = try await ModelLease.shared.withExclusive(.illustration) {
                try await FluxActor.shared.generate(
                    identification: identification,
                    entryId: entryId
                )
            }
            currentEntry.illustrationFilename = URL(fileURLWithPath: illustrationPath).lastPathComponent
            currentEntry.userStatus = "unreviewed"
            try await DatabaseService.shared.saveEntry(currentEntry)
        } catch {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "FLUX generation failed: \(error.localizedDescription)"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.fluxFailed(error.localizedDescription)
        }
    }
}
