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
// FLUX from sharing the GPU with Gemma : same policy as before.

// Per-call generation knobs. Defaults match the Python pipeline; the
// detail-view "Regenerate with options" sheet lets users override per
// generation without touching the standard pipeline path.
struct FluxGenerationParams: Sendable, Equatable {
    var width: Int
    var height: Int
    var steps: Int
    var guidance: Float

    // Match the Python pipeline (Python/flux_service.py defaults).
    static let defaultTextToImage = FluxGenerationParams(
        width: 1024, height: 1024, steps: 4, guidance: 1.0
    )

    // Image-to-image runs the same Klein 4B turbo path but with the
    // user's photograph as a visual reference. The turbo distillation
    // applies in both modes; we start at the same 4-step budget as
    // text-to-image and bump only if results are mush. Slightly higher
    // guidance because the reference image gives the prompt more to
    // contend with.
    static let defaultImageToImage = FluxGenerationParams(
        width: 1024, height: 1024, steps: 6, guidance: 1.5
    )
}

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

    private var pipeline: Flux2Pipeline?

    private init() {}

    // Convenience matching `IllustratorPort`. Picks defaults based on
    // whether a reference photo is supplied and writes to the canonical
    // entry illustration path. The standard pipeline path uses this.
    func generate(
        identification: IdentificationResult,
        entryId: UUID,
        referencePhotoPath: String? = nil,
        customPrompt: String? = nil
    ) async throws -> String {
        let params: FluxGenerationParams = referencePhotoPath != nil
            ? .defaultImageToImage
            : .defaultTextToImage
        let url = AppPaths.illustrations.appendingPathComponent(
            "\(entryId.uuidString)_illustration.png"
        )
        return try await generate(
            identification: identification,
            referencePhotoPath: referencePhotoPath,
            customPrompt: customPrompt,
            params: params,
            outputURL: url
        )
    }

    // Full-control overload. Takes explicit generation params and an
    // explicit output URL so callers (the variant flow) can target a
    // non-canonical filename without overwriting the entry's saved
    // illustration.
    func generate(
        identification: IdentificationResult,
        referencePhotoPath: String?,
        customPrompt: String?,
        params: FluxGenerationParams,
        outputURL: URL
    ) async throws -> String {
        // ModelLease is the production caller and shuts us down after
        // each illustration, so this defer is mostly a safety net for
        // any future caller that invokes generate() outside the lease.
        // Cheap when shutdown already drained the pool.
        defer { MLX.Memory.clearCache() }

        // Swift owns the per-kingdom templates and the {scientific_name} /
        // {common_name} / {subject} substitution — same behavior the
        // Python actor had. A non-empty `customPrompt` overrides the
        // template path entirely so per-entry edits ship to FLUX verbatim.
        let prompt: String
        if let custom = customPrompt?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            prompt = custom
        } else {
            let kingdom = Kingdom.parse(identification.kingdom)
            let template = IllustrationPromptStore.shared.template(for: kingdom)
            prompt = IllustrationPrompts.render(template: template, identification: identification)
        }

        let pipeline = try await ensurePipeline()
        let seed = UInt64.random(in: 0..<UInt64(UInt32.max))
        let image: CGImage
        do {
            if let referencePhotoPath {
                let reference = try Self.loadCGImage(atPath: referencePhotoPath)
                image = try await pipeline.generateImageToImage(
                    prompt: prompt,
                    images: [reference],
                    height: params.height,
                    width: params.width,
                    steps: params.steps,
                    guidance: params.guidance,
                    seed: seed
                )
            } else {
                image = try await pipeline.generateTextToImage(
                    prompt: prompt,
                    height: params.height,
                    width: params.width,
                    steps: params.steps,
                    guidance: params.guidance,
                    seed: seed
                )
            }
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
            quantization: Self.quantization(
                for: SystemCapability.current,
                preference: FluxQuantizationStore.shared.selected
            )
        )
        try await next.loadModels()
        self.pipeline = next
        return next
    }

    // `.minimal` (mlx4bit text encoder + qint8 transformer, ~47 GB peak
    // per Flux2QuantizationConfig.imageGenerationPhaseMemoryGB) is the
    // fidelity target — qint8 preserved color vs. the prior mflux
    // pipeline, while on-the-fly int4 introduced visible hue and
    // desaturation shifts. On Macs that can't seat 47 GB the auto path
    // falls back to `.ultraMinimal` (int4 transformer, ~30 GB peak) —
    // less faithful but loads instead of OOM-killing the app.
    //
    // Power users override via FluxQuantizationStore: pin `.balanced`
    // for sharper output on big Macs, or `.ultraMinimal` to free RAM for
    // other workloads. ModelLease evicts Gemma before FLUX loads, so the
    // FLUX budget is full RAM minus OS overhead.
    static func quantization(
        for capability: SystemCapability,
        preference: FluxQuantizationPreference
    ) -> Flux2QuantizationConfig {
        switch preference {
        case .ultraMinimal: return .ultraMinimal
        case .minimal:      return .minimal
        case .balanced:     return .balanced
        case .auto:         return capability.physicalMemoryGB >= 48 ? .minimal : .ultraMinimal
        }
    }

    private static func loadCGImage(atPath path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw FluxError.generationFailed("Could not read reference photo at \(path)")
        }
        return image
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
