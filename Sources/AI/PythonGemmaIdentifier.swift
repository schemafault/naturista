import Foundation

// Long-running mlx-vlm Python subprocess driving identification. Lifted
// verbatim from the original GemmaActor body — the only change is that
// it now conforms to `Identifier` so GemmaActor can swap in the native
// MLX-Swift implementation behind a feature flag (Phase 1b).
actor PythonGemmaIdentifier: Identifier {
    private let transport: PythonProcessTransport

    init() {
        self.transport = PythonProcessTransport(config: .init(
            scriptPath: PythonGemmaIdentifier.scriptPath,
            environment: {
                [
                    "GEMMA_MODEL_PATH": NSString(string: ModelConfig.gemmaPath).expandingTildeInPath
                ]
            },
            timeoutSeconds: 310,
            warmupSeconds: 2,
            stderrLogURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("naturista_gemma.log")
        ))
    }

    private static var scriptPath: String {
        AppPaths.applicationSupport
            .appendingPathComponent("Python", isDirectory: true)
            .appendingPathComponent("gemma_service.py")
            .path
    }

    private struct IdentifyRequest: Encodable, Sendable {
        let action: String
        let photo_path: String
    }

    func identify(photoPath: String) async throws -> IdentificationResult {
        let result = try await transport.call(
            IdentifyRequest(action: "identify", photo_path: photoPath),
            responseType: IdentificationResult.self
        )
        if let err = result.error, !err.isEmpty {
            throw PythonRPCError.remote(err)
        }
        return result
    }

    func shutdown() async {
        await transport.shutdown()
    }
}
