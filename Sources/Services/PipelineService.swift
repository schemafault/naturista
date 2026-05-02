import Foundation

enum PipelineError: Error, LocalizedError {
    case entryNotFound
    case gemmaFailed(String)
    case fluxFailed(String)
    case compositorFailed(String)

    var errorDescription: String? {
        switch self {
        case .entryNotFound:
            return "Entry not found in database."
        case .gemmaFailed(let message):
            return "Gemma identification failed: \(message)"
        case .fluxFailed(let message):
            return "FLUX illustration generation failed: \(message)"
        case .compositorFailed(let message):
            return "Plate composition failed: \(message)"
        }
    }
}

actor PipelineService {
    static let shared = PipelineService()

    private init() {}

    func runFullPipeline(entryId: UUID) async throws {
        var entry: Entry?
        do {
            entry = try await DatabaseService.shared.fetchEntry(id: entryId.uuidString)
        } catch {
            throw PipelineError.entryNotFound
        }

        guard var currentEntry = entry else {
            throw PipelineError.entryNotFound
        }

        let workingPath = AppPaths.working.appendingPathComponent(currentEntry.workingImageFilename).path

        var identificationResult: IdentificationResult?
        do {
            identificationResult = try await GemmaActor.shared.identify(photoPath: workingPath)
            let encoder = JSONEncoder()
            currentEntry.identificationJson = String(data: try encoder.encode(identificationResult), encoding: .utf8) ?? ""
            currentEntry.modelConfidence = identificationResult?.modelConfidence
            try await DatabaseService.shared.saveEntry(currentEntry)
        } catch {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "Gemma identification failed: \(error.localizedDescription)"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.gemmaFailed(error.localizedDescription)
        }

        guard let identification = identificationResult else {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "Gemma identification failed: no result returned"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.gemmaFailed("No identification result returned")
        }

        guard let identification = identificationResult else {
            throw PipelineError.gemmaFailed("No identification result")
        }

        let illustrationFilename: String
        do {
            let illustrationPath = try await FluxActor.shared.generate(
                photoPath: workingPath,
                identification: identification,
                entryId: entryId
            )
            illustrationFilename = URL(fileURLWithPath: illustrationPath).lastPathComponent
            currentEntry.illustrationFilename = illustrationFilename
            try await DatabaseService.shared.saveEntry(currentEntry)
        } catch {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "FLUX generation failed: \(error.localizedDescription)"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.fluxFailed(error.localizedDescription)
        }

        guard let finalEntry = try await DatabaseService.shared.fetchEntry(id: entryId.uuidString) else {
            throw PipelineError.entryNotFound
        }
        currentEntry = finalEntry

        do {
            let plateFilename = try await PlateCompositor.compose(
                entryId: entryId,
                commonName: identification.topCandidate.commonName,
                scientificName: identification.topCandidate.scientificName,
                family: identification.topCandidate.family,
                notes: currentEntry.notes,
                illustrationFilename: illustrationFilename
            )
            currentEntry.plateFilename = plateFilename
            currentEntry.userStatus = "unreviewed"
            try await DatabaseService.shared.saveEntry(currentEntry)
        } catch {
            currentEntry.userStatus = "failed"
            currentEntry.notes = "Plate composition failed: \(error.localizedDescription)"
            try await DatabaseService.shared.saveEntry(currentEntry)
            throw PipelineError.compositorFailed(error.localizedDescription)
        }
    }
}