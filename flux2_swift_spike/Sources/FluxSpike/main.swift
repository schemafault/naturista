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

// Warmup (also loads text encoder, which loadModels defers).
print("[spike] warmup generation (loads text encoder)...")
let warmStart = Date()
let warmImage = try await pipeline.generateTextToImage(
    prompt: prompt,
    height: height, width: width, steps: steps, guidance: guidance, seed: seed
)
let warmSeconds = Date().timeIntervalSince(warmStart)
print(String(format: "[spike] warmup: %.2fs", warmSeconds))
try savePNG(warmImage, to: outputURL)

// Steady-state: 3 generations.
var times: [Double] = []
for i in 0..<3 {
    let t0 = Date()
    _ = try await pipeline.generateTextToImage(
        prompt: prompt,
        height: height, width: width, steps: steps, guidance: guidance,
        seed: seed &+ UInt64(i + 1)
    )
    let dt = Date().timeIntervalSince(t0)
    times.append(dt)
    print(String(format: "[spike] gen %d: %.2fs", i + 1, dt))
}

let median = times.sorted()[times.count / 2]
let best = times.min()!

print("---- spike result ----")
print(String(format: "warmup_seconds:        %.2f", warmSeconds))
print(String(format: "steady_best_seconds:   %.2f", best))
print(String(format: "steady_median_seconds: %.2f", median))
print(String(format: "peak_rss_gb:           %.2f", peakRSSGB()))
print("output (warmup):       \(outputURL.path)")
