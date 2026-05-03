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
        let prompt: String
        let output_path: String
    }

    func generate(identification: IdentificationResult, entryId: UUID) async throws -> String {
        // Swift owns the per-kingdom templates and the {scientific_name} /
        // {common_name} / {subject} substitution; Python receives the fully-
        // rendered prompt via the existing `prompt` RPC field. The template
        // returned by the store is the user's override or the built-in default.
        let kingdom = Kingdom.parse(identification.kingdom)
        let template = IllustrationPromptStore.shared.template(for: kingdom)
        let prompt = IllustrationPrompts.render(template: template, identification: identification)

        let illustrationFilename = "\(entryId.uuidString)_illustration.png"
        let outputPath = AppPaths.illustrations.appendingPathComponent(illustrationFilename).path

        let result = try await transport.call(
            GenerateRequest(
                action: "generate",
                prompt: prompt,
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
