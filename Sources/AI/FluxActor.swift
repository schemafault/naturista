import Foundation
import CoreGraphics
import Flux2Core
import ImageIO
import MLX
import UniformTypeIdentifiers

// In-process FLUX.2 Klein 4B int4 illustration via flux-2-swift-mlx.
// Replaces the prior mflux subprocess. Same model + steps + guidance +
// dims as the Python pipeline (validated by flux2_swift_spike/), so
// output quality should match within seed variance.
//
// `ModelLease` releases this actor eagerly after each generate to keep
// FLUX from sharing the GPU with Gemma — same policy as before.
actor FluxActor {
    static let shared = FluxActor()

    enum FluxError: Error, LocalizedError {
        case generationFailed(String)
        case encodeFailed
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .generationFailed(let m): return "FLUX generation failed: \(m)"
            case .encodeFailed:            return "Failed to encode FLUX output as PNG."
            case .writeFailed(let m):      return "Failed to write FLUX output: \(m)"
            }
        }
    }

    // Match the Python pipeline (Python/flux_service.py defaults).
    private static let height = 1024
    private static let width = 1024
    private static let steps = 4
    private static let guidance: Float = 1.0

    private var pipeline: Flux2Pipeline?

    private init() {}

    func generate(identification: IdentificationResult, entryId: UUID) async throws -> String {
        // ModelLease is the production caller and shuts us down after
        // each illustration, so this defer is mostly a safety net for
        // any future caller that invokes generate() outside the lease.
        // Cheap when shutdown already drained the pool.
        defer { MLX.Memory.clearCache() }

        // Swift owns the per-kingdom templates and the {scientific_name} /
        // {common_name} / {subject} substitution — same behavior the
        // Python actor had.
        let kingdom = Kingdom.parse(identification.kingdom)
        let template = IllustrationPromptStore.shared.template(for: kingdom)
        let prompt = IllustrationPrompts.render(template: template, identification: identification)

        let illustrationFilename = "\(entryId.uuidString)_illustration.png"
        let outputURL = AppPaths.illustrations.appendingPathComponent(illustrationFilename)

        let pipeline = try await ensurePipeline()
        let seed = UInt64.random(in: 0..<UInt64(UInt32.max))
        let image: CGImage
        do {
            image = try await pipeline.generateTextToImage(
                prompt: prompt,
                height: Self.height,
                width: Self.width,
                steps: Self.steps,
                guidance: Self.guidance,
                seed: seed
            )
        } catch {
            throw FluxError.generationFailed(error.localizedDescription)
        }

        try Self.writePNG(image, to: outputURL)
        return outputURL.path
    }

    func shutdown() async {
        // Drop the pipeline so its MLXArrays are released, then drain
        // the metal allocator pool. This is what ModelLease's eager
        // release expects — the next generate cold-loads from disk.
        pipeline = nil
        MLX.Memory.clearCache()
    }

    private func ensurePipeline() async throws -> Flux2Pipeline {
        if let pipeline { return pipeline }
        let next = Flux2Pipeline(
            model: .klein4B,
            // ultraMinimal = text encoder mlx4bit + transformer int4,
            // matching the Python flux2-klein-4b-mflux-4bit baseline.
            quantization: .ultraMinimal
        )
        try await next.loadModels()
        self.pipeline = next
        return next
    }

    private static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw FluxError.encodeFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) {
            throw FluxError.writeFailed(url.path)
        }
    }
}
