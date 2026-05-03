import Foundation

struct FluxGenerationResult: Codable, Sendable {
    var illustrationPath: String
    var seed: Int
    var timingSeconds: Double

    enum CodingKeys: String, CodingKey {
        case illustrationPath = "illustration_path"
        case seed
        case timingSeconds = "timing_seconds"
    }
}

actor FluxActor {
    static let shared = FluxActor()

    private static var scriptPath: String {
        AppPaths.applicationSupport
            .appendingPathComponent("Python", isDirectory: true)
            .appendingPathComponent("flux_service.py")
            .path
    }

    private let transport: PythonProcessTransport

    private init() {
        self.transport = PythonProcessTransport(config: .init(
            scriptPath: FluxActor.scriptPath,
            environment: [:],
            timeoutSeconds: 310,
            warmupSeconds: 2,
            stderrLogURL: URL(fileURLWithPath: "/tmp/naturista_flux.log")
        ))
    }

    private struct GenerateRequest: Encodable, Sendable {
        let action: String
        let identification_json_path: String
        let photo_path: String
        let output_path: String
    }

    func generate(photoPath: String, identification: IdentificationResult, entryId: UUID) async throws -> String {
        // FLUX takes the identification as a sidecar JSON file rather than
        // inline; write it once, hand the path over, clean up on exit.
        let identificationJsonPath = AppPaths.applicationSupport
            .appendingPathComponent("temp_identification_\(entryId.uuidString).json")
        try JSONEncoder().encode(identification).write(to: identificationJsonPath)
        defer { try? FileManager.default.removeItem(at: identificationJsonPath) }

        let illustrationFilename = "\(entryId.uuidString)_illustration.png"
        let outputPath = AppPaths.illustrations.appendingPathComponent(illustrationFilename).path

        let result = try await transport.call(
            GenerateRequest(
                action: "generate",
                identification_json_path: identificationJsonPath.path,
                photo_path: photoPath,
                output_path: outputPath
            ),
            responseType: FluxGenerationResult.self
        )
        return result.illustrationPath
    }

    func shutdown() async {
        await transport.shutdown()
    }
}
