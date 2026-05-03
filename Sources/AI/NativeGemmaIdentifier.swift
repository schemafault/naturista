import Foundation
import MLXLMCommon
import MLXVLM

// Placeholder for Phase 1b. Imports the MLX-Swift surface so the SPM
// wiring is exercised by Phase 1a's build, but does not yet load weights
// or run inference. Flipping `gemma.useNativeBackend = true` while this
// is in place returns a clear error rather than silent failure.
//
// Phase 1b will replace `identify` with a real `VLMModelFactory` +
// `MLXLMCommon` pipeline backed by mlx-community/gemma-{3,4}-*-4bit
// weights at AppPaths.models.
actor NativeGemmaIdentifier: Identifier {
    enum NotImplemented: Error, LocalizedError {
        case nativeBackendNotYetShipped

        var errorDescription: String? {
            "The native MLX-Swift identification backend isn't shipped yet. Disable it in Settings to fall back to the Python backend."
        }
    }

    init() {}

    func identify(photoPath: String) async throws -> IdentificationResult {
        // Reference one symbol from each imported library so the link
        // step has a real reason to pull them in. Cheap, keeps the code
        // honest about what it depends on.
        _ = VLMModelFactory.shared
        _ = ModelRegistry.self

        throw NotImplemented.nativeBackendNotYetShipped
    }

    func shutdown() async {
        // No resident state yet — nothing to tear down.
    }
}
