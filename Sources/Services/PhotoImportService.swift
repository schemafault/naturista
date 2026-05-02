import Foundation

actor PhotoImportService {
    static let shared = PhotoImportService()

    private init() {}

    func importPhoto(from sourceURL: URL) async throws -> Entry {
        let id = UUID().uuidString
        let originalFilename = "\(id)_original.jpg"
        let originalDestination = AppPaths.originals.appendingPathComponent(originalFilename)

        try FileManager.default.copyItem(at: sourceURL, to: originalDestination)

        let metadata = try await ImageService.shared.extractMetadata(from: sourceURL)

        let capturedAt: String? = metadata.capturedAt.map { ISO8601DateFormatter().string(from: $0) }

        let workingURL = try await ImageService.shared.createWorkingCopy(sourceURL: originalDestination)
        let workingFilename = workingURL.lastPathComponent

        var entry = Entry(
            id: id,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            capturedAt: capturedAt,
            originalImageFilename: originalFilename,
            workingImageFilename: workingFilename
        )

        try await DatabaseService.shared.saveEntry(entry)

        let workingPath = AppPaths.working.appendingPathComponent(workingFilename).path
        do {
            let identification = try await GemmaActor.shared.identify(photoPath: workingPath)
            let encoder = JSONEncoder()
            entry.identificationJson = String(data: try encoder.encode(identification), encoding: .utf8) ?? ""
            entry.modelConfidence = identification.modelConfidence
            try await DatabaseService.shared.saveEntry(entry)
        } catch {
            let encoder = JSONEncoder()
            entry.identificationJson = String(data: try encoder.encode(["error": error.localizedDescription]), encoding: .utf8) ?? ""
            entry.userStatus = "failed"
            try await DatabaseService.shared.saveEntry(entry)
        }

        return entry
    }
}