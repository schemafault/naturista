import Foundation
import ImageIO
import UniformTypeIdentifiers
import Darwin
import Flux2Core

// Spike: prove FLUX.2 Klein 4B (int4) runs end-to-end via mlx-swift,
// matching the Python defaults (1024x1024, 4 steps, guidance 1.0).
// Reports wall-clock latency and peak RSS so we can compare against the
// current Python pipeline.

let prompt = "A botanical illustration of a Pacific dogwood (Cornus nuttallii) " +
             "in the style of a 19th-century scientific plate, white background, " +
             "soft watercolor, fine ink linework."
let height = 1024
let width = 1024
let steps = 4
let guidance: Float = 1.0
let seed: UInt64 = 42

let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("flux_spike_output.png")

func peakRSSGB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    // On Darwin ru_maxrss is in bytes.
    return Double(usage.ru_maxrss) / 1_073_741_824.0
}

func savePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw NSError(domain: "FluxSpike", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "CGImageDestination create failed"])
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        throw NSError(domain: "FluxSpike", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "CGImageDestination finalize failed"])
    }
}

print("[spike] FLUX.2 Klein 4B int4 spike")
print("[spike] prompt: \(prompt)")
print("[spike] params: \(width)x\(height), steps=\(steps), guidance=\(guidance), seed=\(seed)")

// ultraMinimal = text encoder mlx4bit + transformer int4 (matches the
// Python flux2-klein-4b-mflux-4bit baseline).
let pipeline = Flux2Pipeline(
    model: .klein4B,
    quantization: .ultraMinimal
)

let loadStart = Date()
print("[spike] loading models (downloads on first run; can be multi-GB)...")
try await pipeline.loadModels()
let loadSeconds = Date().timeIntervalSince(loadStart)
print(String(format: "[spike] models loaded in %.1fs", loadSeconds))
print(String(format: "[spike] peak RSS after load: %.2f GB", peakRSSGB()))

let genStart = Date()
let image = try await pipeline.generateTextToImage(
    prompt: prompt,
    height: height,
    width: width,
    steps: steps,
    guidance: guidance,
    seed: seed
)
let genSeconds = Date().timeIntervalSince(genStart)

try savePNG(image, to: outputURL)

print("---- spike result ----")
print(String(format: "load_seconds:    %.2f", loadSeconds))
print(String(format: "generate_seconds:%.2f", genSeconds))
print(String(format: "peak_rss_gb:     %.2f", peakRSSGB()))
print("output:          \(outputURL.path)")
