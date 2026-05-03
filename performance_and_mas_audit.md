# Naturista — Performance & Mac App Store Audit

## Context

The app currently works well at small scale, but three issues compound for users with large libraries (5,000+ illustrations) and varying machine specs:

1. **Gallery loads full-resolution images** for every visible tile and re-loads on every filter switch. There's no thumbnail layer and no shared image cache.
2. **No system-capability detection.** A user with 16GB RAM can pick the 17GB Gemma 4 31B model and discover the failure only via OS-killed Python subprocess and a generic error.
3. **The current architecture cannot ship to the Mac App Store.** The Python subprocess + `~/.cache/` model storage + sandbox-disabled entitlements are hard blockers.

This plan covers the performance and capability fixes (ship-soon, low risk) and lays out the strategic fork for MAS distribution.

---

## Findings

### Performance pipeline (today)

- **Storage:** Originals (full JPEG), Working (JPEG resampled to ~2000×2000 at 0.8 quality, ~12MB decoded), Illustrations (full-res FLUX PNG). Defined in `Sources/Services/PhotoImportService.swift:8` and `Sources/Services/ImageService.swift:44`.
- **Gallery loads working/illustration files directly.** No thumbnails. `EntryRowView.figure` (`Sources/Views/EntryRowView.swift:64`) → `LocalImage` (`:97`) reads the full file from disk into `NSImage` per visible tile. Detail view (`Sources/Views/EntryDetailView.swift:145`, `Sources/Views/PlateFrameView.swift:62`) loads the *same* file again — SwiftUI doesn't preserve it across navigation.
- **No shared image cache.** Each `LocalImage` instance is independent; switching sidebar filter (Recent / Pinned / Family) re-instantiates `MasonryGrid` (`Sources/Views/LibraryView.swift:307`) and re-reads from disk. There IS an NSCache pattern already in the codebase to mirror: `Sources/Models/Identification.swift:12`.
- **Pagination is half-eager.** Page size 16 is fine, but the paginator at `Sources/Views/LibraryView.swift:520` iterates `ForEach(0..<total)` — for 5000 entries that renders 312 page-button views. The grid itself is not lazy: `MasonryGrid` (`:447`) uses eager `HStack { ForEach { VStack { ForEach } } }`.

### Model management (today)

- **Zero capability checks.** No `ProcessInfo.physicalMemory`, no `volumeAvailableCapacity`, no Apple Silicon detection.
- Models 3.2GB–17GB stored in `~/.cache/...` (`Sources/App/ModelConfig.swift:40`).
- Singleton actors per model (`FluxActor.shared`, `GemmaActor.shared`); one Python subprocess each.
- Lease management exists (`Sources/AI/ModelLease.swift`): Gemma stays warm, Flux releases eagerly. Commit `45de7e9` adds reactive shutdown to avoid 31B+FLUX OOM on 48GB.
- Failure path: subprocess gets OS-killed → generic `modelLoadFailed` surfaced. No upfront refusal.
- HF CLI download via subprocess (`Sources/App/ModelConfig.swift:120`). Model deletion exists (commit `0bd15ae`).

### Mac App Store eligibility (today)

**Hard blockers:**
1. Sandbox disabled — `Naturista/Resources/Naturista.entitlements` sets `com.apple.security.app-sandbox = false`.
2. **External Python subprocess** at `Sources/AI/PythonRPCTransport.swift:196` runs `~/.cache/naturista-venv/bin/python3`. Sandbox prohibits executing binaries outside the bundle.
3. **Models in `~/.cache/`** — outside sandbox container.
4. **`hf` CLI subprocess** for model downloads — same restriction.

**Soft concerns:**
5. `/tmp/naturista_*.log` writes (`Sources/AI/GemmaActor.swift:85`, `Sources/AI/FluxActor.swift:33`) — should use `FileManager.default.temporaryDirectory`.
6. Multi-GB runtime downloads — allowed but UX-unfriendly first-run.

**Already fine:** user-selected file imports (`com.apple.security.files.user-selected.read-write` is set), `Application Support` container for DB/assets, no hardware/JIT entitlement needs.

---

## Recommended order — top 5 if you can only do 5 things this month

These are MAS-independent and ship value immediately.

### 1. Thumbnail pipeline + shared image cache — Effort: M (2–3 days) — DONE

Status: shipped. `Entry.thumbnailFilename` + `v3_thumbnails` migration; `AppPaths.thumbnails`; `ImageService.createThumbnail` (uses `CGImageSourceCreateThumbnailAtIndex`); generation hooked into `PhotoImportService` and all FLUX paths in `PipelineService`; `ImageCache` (NSCache, 128MB cost limit) backing `LocalImage`; `ThumbnailBackfillService` actor invoked from `AppDelegate` for pre-v3 rows; `EntryRowView.figure` prefers thumbnail with fallback to illustration → working → placeholder. Detail view unchanged.

### 2. `SystemCapability` service + model picker integration — Effort: S–M (1–1.5 days)

**Why now.** Prevents OOM-kill confusion; cheap and high-trust.

New `Sources/Services/SystemCapability.swift`:

```swift
struct SystemCapability {
    let physicalMemoryGB: Double          // ProcessInfo.processInfo.physicalMemory / 1e9
    let isAppleSilicon: Bool              // sysctlbyname("hw.optional.arm64")
    let availableDiskGB: Double           // .volumeAvailableCapacityForImportantUsageKey
    let chipModel: String                 // sysctlbyname("machdep.cpu.brand_string")
}
```

(GPU memory isn't directly queryable on Apple Silicon — physical RAM is the right proxy because of unified memory.)

Add `requirements: ModelRequirements` to `ModelConfig.GemmaModel` and a `compatibility(on:) -> .compatible / .marginal / .incompatible` method.

Suggested thresholds. `ModelLease` (`Sources/AI/ModelLease.swift`, hardened in commit `45de7e9`) guarantees Gemma and FLUX are never resident simultaneously — Gemma shuts down before FLUX loads, FLUX releases eagerly after each generate. So thresholds reflect each model loaded **alone**:

| Model | Min RAM | Recommended | Min free disk |
|---|---|---|---|
| Gemma 3 4B | 8 GB | 16 GB | 5 GB |
| Gemma 3 12B | 16 GB | 24 GB | 10 GB |
| Llama 3.2 Vision 11B | 16 GB | 24 GB | 8 GB |
| Gemma 4 31B | 24 GB | 36 GB | 20 GB |
| FLUX 2 Klein (4-bit) | 12 GB | 16 GB | 25 GB |

UI behavior in the picker (`Sources/Views/IllustrationStyleSheet.swift:194`):
- **Compatible:** enabled, no annotation.
- **Marginal:** enabled, "May be slow on this Mac" caption.
- **Incompatible:** disabled, "Requires X GB RAM (you have Y)" caption, no download.
- **Intel Mac:** full-screen "Apple Silicon required" state (all current models are MLX-only).

Also add a pre-download `volumeAvailableCapacity` check to `GemmaModelDownloader.download` (`Sources/App/ModelConfig.swift:120`).

### 3. LazyVGrid migration + windowed pagination — Effort: S (1 day)

`Sources/Views/LibraryView.swift`:
- Replace `MasonryGrid` body (`:447–488`) with `LazyVGrid` + `GridItem(.adaptive(minimum: 280))`. The deterministic per-id aspect ratio (`:493`) preserves the masonry feel without a custom layout. Lazy means off-screen tiles never instantiate `EntryRowView`.
- Replace `PaginationBar`'s `ForEach(0..<total)` (`:520`) with a windowed renderer: `‹ 1 … 4 5 [6] 7 8 … 312 ›`.
- Memoize `recentIds` and `familyCounts` (`:27–45`) so they don't recompute on every body eval.

(Open question for follow-up: with thumbnails + LazyVGrid, pagination may be unnecessary. Worth A/B-ing scroll feel.)

### 4. Move models from `~/.cache/` to `~/Library/Application Support/Naturista/models/` — Effort: M (1–2 days) — DONE (mac-appy)

Status: shipped on `mac-appy`. `GemmaModel.localCachePath` now derives from `AppPaths.models.appendingPathComponent(directoryName)`; `legacyCachePath` retained for the migrator. New `AppPaths.fluxModel` URL; `FluxActor` injects `FLUX_MODEL_PATH` env so the Python flux service finds weights at the new location. `ModelStorageMigrator.migrateIfNeeded()` (inlined in `ModelConfig.swift`, called from `AppDelegate.applicationDidFinishLaunching` before any actor spins up) moves all 5 known model dirs (4 Gemma variants + FLUX) on launch, idempotent via UserDefaults flag `models.migratedToAppSupport.v1`. Verified end-to-end on this machine: ~30 GB across 5 dirs migrated successfully.

### 5. Strategic decision: MAS path

Spike done — see Option B below. Tentative decision: **Option B**. Prep work for B has begun on `mac-appy` (items 4 above + MAS-blocking remediation rows 2-3 below). Confirm before starting the multi-week native port.

---

## MAS architectural fork

### Option A — Embed Python via `python-build-standalone`

Bundle a relocatable Python (~40MB) + mlx wheels (~600MB–1.2GB) inside the app. Subprocess executes `Bundle.main.url(forResource:)`.

- **Effort:** L. Wheel signing is the painful part — every `.so`/`.dylib` (numpy, mlx, torch, etc.) needs a signature and hardened-runtime treatment.
- **Bundle size:** 1–2GB app.
- **MAS reality:** Apple has approved python-bundled apps but they get extra scrutiny; expect rejection iterations.
- **Maintenance:** every Python/MLX upgrade rebuilds the bundled venv.

**Verdict: avoid.** Highest cost, lowest gain — you keep all the Python complexity AND take on signing/bundling overhead.

### Option B — Native (MLX-Swift)

Replace Python subprocess with in-process Swift via [mlx-swift](https://github.com/ml-explore/mlx-swift). Apple Silicon only, MIT-licensed bindings to the same MLX C++ core.

- **Gemma:** `mlx-swift-examples` has Gemma 3 (and VLM support). Low-risk port.
- **FLUX:** This is the gating risk. Community FLUX-on-MLX-Swift support has been landing but isn't a one-liner.
- **Effort:** L (Gemma) + L–XL (FLUX), pending spike.
- **Loses:** subprocess crash isolation — a FLUX OOM now crashes the host app instead of just the subprocess. Mitigation: native memory pre-checks via `SystemCapability`.
- **Gains:** vastly faster cold start, no Python venv, MAS-eligible, ~half bundle size vs A, native macOS feel.

**Recommendation: 1-day MLX-Swift FLUX spike.** Prove `FLUX.1-schnell-mlx` runs end-to-end at acceptable quality/latency. If yes → commit to Option B over 6–8 weeks. If no → Option C.

**Spike result — DONE (`flux2_swift_spike/`).** Used [VincentGourbin/flux-2-swift-mlx](https://github.com/VincentGourbin/flux-2-swift-mlx) v2.1.0 (`Flux2Core` library, FLUX.2 Klein 4B int4 — same model + quantization + steps/guidance/dims as the current Python pipeline) on M4 Pro / 48 GB. Steady-state, 3 timed gens after warmup:

| Metric | Python (mflux) | Swift (mlx-swift) | Swift / Python |
|---|---|---|---|
| Best of 3 (sec) | 27.30 | 30.75 | **1.13×** |
| Median of 3 (sec) | 27.98 | 30.81 | **1.10×** |
| Run-to-run spread (sec) | 3.93 | 0.06 | Swift is steadier |

Verdict: Option B is technically viable. Swift is ~10% slower steady-state — comfortably inside the audit's 1.5× criterion — and more reliable run-to-run. Likely root cause of the gap: mflux uses pre-quantized 4-bit weights in a packed layout; flux-2-swift-mlx quantizes on-the-fly and the runtime layout doesn't always hit the fastest int4 matmul kernel. Same `Cmlx`/Metal compute under both. Gotcha discovered: any mlx-swift target must be built via `xcodebuild` (not `swift build`) — SwiftPM CLI doesn't compile the Metal shaders.

### Option C — Don't ship to MAS; stay Developer ID + notarization

Current architecture works. Notarize, distribute via website + Sparkle.

- **Effort:** S (already there).
- **Loses:** MAS discoverability, in-app purchase, App Store updates, "trust badge" for non-technical users.
- **Gains:** no architectural rewrite, Python ecosystem stays open, faster iteration.

**Verdict:** Defensible indefinitely for a niche local-AI app with technical-leaning users.

---

## MAS-blocking remediation (only if A or B is chosen)

These come AFTER the spike + decision. Item 4 above (move models out of `~/.cache/`) is shared.

| Task | Files | Effort | Status |
|---|---|---|---|
| Enable sandbox | `Naturista/Resources/Naturista.entitlements` | S | pending — depends on subprocess removal |
| Replace `/tmp/naturista_*.log` with `FileManager.default.temporaryDirectory` | `Sources/AI/GemmaActor.swift:85`, `Sources/AI/FluxActor.swift:33` | S | ✅ DONE (mac-appy) |
| Replace `hf` CLI with native Swift HuggingFace downloader (`URLSession`, parse `model.safetensors.index.json`, parallel downloads) | `Sources/App/ModelConfig.swift:120` | M | ✅ DONE (mac-appy) — `HuggingFaceDownloader` struct inlined in `ModelConfig.swift`; uses HF tree API + 4-way bounded concurrency + `.partial` rename for resume; `GemmaModelDownloader.download` rewritten to call it. **Untested end-to-end** because all 5 models are already on disk on the dev machine — first verification path is to delete a model via the picker UI and re-add it. |
| Remove all subprocess spawning (Option B) OR bundle Python (Option A) | `Sources/AI/PythonRPCTransport.swift` | XL | **in progress** (Option B) — Gemma port Phase 1a shipped (scaffolding + SPM dep + facade); see "Next session" below for current state |

---

## Next session — entry point

State of `mac-appy` branch (uncommitted as of this writeup):

- **Done on this branch:** Item 4 (model storage migration), MAS rows 2 & 3 above (logs out of `/tmp`, native HF downloader). FLUX spike at `flux2_swift_spike/`. Phase 1a (committed, `40fee44`). **Phases 1b–1e + Phase 2 (FLUX) + Phase 3 (Python teardown) all uncommitted** — see phasing below.
- **Modified files (uncommitted):** `Naturista/project.yml` (adds `swift-transformers` 1.3.0 / `Tokenizers` and `flux-2-swift-mlx` 2.1.0 / `Flux2Core` products), `Naturista/Naturista.xcodeproj/...` (regenerated), `Sources/AI/GemmaActor.swift` (full native impl, ex-facade), `Sources/AI/FluxActor.swift` (in-process Flux2Pipeline, ex-Python wrapper), `Sources/AI/Identifier.swift` (DTOs only, protocol stripped), `Sources/App/ModelConfig.swift` (drops `llama32vision_11b` + dead `pythonPath`), `Sources/App/AppDelegate.swift` (points `ModelRegistry.customModelsDirectory` at `AppPaths.models`), `Sources/Views/IllustrationStyleSheet.swift` (backend toggle removed), `performance_and_mas_audit.md`.
- **New files (uncommitted):** `Sources/AI/MLXTokenizerBridge.swift` (the `LocalTokenizerLoader` + `Tokenizers.Tokenizer` → `MLXLMCommon.Tokenizer` adapter — chosen over `MLXHuggingFace` macros to avoid the macro-plugin compile cost and keep the bridge readable; ~50 lines).
- **Deleted files (uncommitted):** `Sources/AI/PythonGemmaIdentifier.swift`, `Sources/AI/PythonRPCTransport.swift`, `Sources/AI/NativeGemmaIdentifier.swift` (merged into `GemmaActor`), `Sources/AI/IdentificationBackend.swift`, the entire `Python/` directory.
- **Branch base:** forked from `fix/lease-eager-release-flux` carrying that branch's WIP forward (SystemCapability service, etc.). Phase 1a is committed; Phase 1b is staged for review before commit.
- **Native MLX-Swift port (Option B, XL effort, 6–8 weeks) — phasing:**
  1. **Gemma port — Phase 1a: scaffolding ✅ DONE (commit `40fee44`).** `mlx-swift-lm` 3.31.3 added as SPM dep; `MLXVLM` + `MLXLMCommon` link into the app; `GemmaActor` is now a thin facade that picks `PythonGemmaIdentifier` or `NativeGemmaIdentifier` based on the flag.
  1b. **Gemma port — Phase 1b: real native impl. ✅ DONE (mac-appy, uncommitted).** `swift-transformers` 1.3.0 added as SPM dep (product `Tokenizers`). New `Sources/AI/MLXTokenizerBridge.swift` adapts `Tokenizers.Tokenizer` to `MLXLMCommon.Tokenizer` and exposes a `LocalTokenizerLoader` that wraps `Tokenizers.AutoTokenizer.from(modelFolder:)`. `NativeGemmaIdentifier.identify` now: reads `GemmaModelStore.shared.selected`, lazy-loads a `ModelContainer` via `VLMModelFactory.shared.loadContainer(from: AppPaths.models/<directoryName>, using: LocalTokenizerLoader())`, builds a `ChatSession` with the system prompt verbatim from `Python/gemma_service.py`, `maxTokens: 2048`, `temperature: 0`, and `processing: .init()` (no pre-resize — let the model's preprocessor decide). Output is post-processed identically to Python (strip ``` fences, extract outermost `{...}`, normalize "fungi" → "fungus") before decoding into `IdentificationResult`. xcodebuild succeeds. **Untested at runtime** — the flag still defaults `false` so existing behavior is preserved; manual flip via `defaults write com.naturista.app gemma.useNativeBackend -bool YES` then identify a photo on `gemma3_12b`.
  1c. **Gemma port — Phase 1c: model coverage ✅ DONE (mac-appy, uncommitted).** Static check via each model's on-disk `config.json` `model_type`: `gemma3_4b` → `gemma3` ✅, `gemma3_12b` → `gemma3` ✅, `gemma4_31b` → `gemma4` ✅. All three are in `VLMTypeRegistry.shared`. **`llama32vision_11b` (`mllama`) is not in MLXVLM**, and since the path is to remove Python entirely, the case was dropped from `GemmaModel` rather than gated — keeping a Python-only escape hatch would block 1e. Knock-on: any user who had Llama selected has UserDefaults rolling back to `gemma3_12b` automatically (`GemmaModel(rawValue:)` returns nil, `GemmaModelStore.selected` falls through). Llama weights at `~/Library/Application Support/Naturista/models/Llama-3.2-11B-Vision-Instruct-4bit/` orphan with no UI path to delete — accepted, document a manual `rm -rf` if a user complains. Runtime smoke test for the three remaining models is still user-driven.
  1d. **Gemma port — Phase 1d: UI toggle ✅ DONE (mac-appy, uncommitted).** New `backendSection` in `IllustrationStyleSheet.swift` directly under the model picker. Single switch labelled "Native (MLX-Swift) — EXPERIMENTAL" with a one-line description that flips per state. Apply-on-toggle (no Save step): the change writes UserDefaults via `IdentificationBackendStore.shared.setUseNative(_:)` and then calls `GemmaActor.shared.shutdown()` so the next identify rebuilds with the new backend. Lives in the same sheet as the model picker so users discover it together; no separate Settings panel was needed. **Subsequently removed in 1e** — the toggle is gone now that Python is gone.
  1e. **Gemma port — Phase 1e: tear down Python identification ✅ DONE (mac-appy, uncommitted).** Native is now the only identification backend. Deleted: `Sources/AI/PythonGemmaIdentifier.swift`, `Sources/AI/IdentificationBackend.swift`, `Sources/AI/NativeGemmaIdentifier.swift` (its body merged into `GemmaActor`), `Python/gemma_service.py`, the `Identifier` protocol from `Sources/AI/Identifier.swift` (only the DTOs remain), and the `backendSection` toggle from `IllustrationStyleSheet.swift`. `GemmaActor` is a single concrete actor again — no facade, no protocol. Build clean.
  2. **FLUX port ✅ DONE (mac-appy, uncommitted).** Added `flux-2-swift-mlx` 2.1.0 SPM dep (product `Flux2Core`). Rewrote `Sources/AI/FluxActor.swift` from a `PythonProcessTransport` wrapper into a `Flux2Pipeline` owner: same `generate(identification:entryId:)` public API so `PipelineService` callers don't change. Internally: lazy-loads `Flux2Pipeline(model: .klein4B, quantization: .ultraMinimal)` (matches the spike), generates at the same 1024×1024 / 4 steps / guidance 1.0 the Python pipeline used, encodes the returned `CGImage` to PNG via `CGImageDestination`. `shutdown()` releases the pipeline + calls `MLX.Memory.clearCache()`. `AppDelegate` sets `ModelRegistry.customModelsDirectory = AppPaths.models` before any FLUX call so weights live alongside Gemma. **Note**: Flux2Core's expected on-disk layout (`black-forest-labs/FLUX.2-klein-4B-bf16/`) differs from mflux's (`flux2-klein-4b-mflux-4bit/`), so first native FLUX generate triggers a fresh ~10 GB download. The old mflux dir orphans at `~/Library/Application Support/Naturista/models/flux2-klein-4b-mflux-4bit/` — accepted, manual `rm -rf` if a user complains.
  3. **Python teardown ✅ DONE (mac-appy, uncommitted).** Both actors are native. Deleted `Sources/AI/PythonRPCTransport.swift`, the entire `Python/` directory, and the dead `ModelConfig.pythonPath` constant. The venv at `~/.cache/naturista-venv/` is still on the dev machine but is no longer touched by the app — accepted, user can `rm -rf` to reclaim disk.
  4. **← NEXT.** Enable sandbox + clean up entitlements. **Gotcha**: flipping `com.apple.security.app-sandbox` to `true` in `Naturista.entitlements` rebases `FileManager.default.urls(for: .applicationSupportDirectory)` from `~/Library/Application Support/Naturista/` to `~/Library/Containers/com.naturista.app/Data/Library/Application Support/Naturista/`. Without a migration pass, every existing user's ~30 GB of weights, the SQLite DB, all originals/working/illustrations/plates orphan and the app launches fresh-state. The migration is its own day of work: a launch-time check that copies (or hard-links, since same volume) the entire `~/Library/Application Support/Naturista/` tree into the container if both paths exist, idempotent via UserDefaults flag (mirroring `ModelStorageMigrator`'s pattern). Also requires `com.apple.security.network.client` for HF downloads. Do NOT just flip the bit.
- **Spike-derived constraint to remember:** mlx-swift requires `xcodebuild` for Metal shader compilation; the existing Naturista Xcode project handles this automatically.
- **Phase 1a-derived constraint:** `MLXLMCommon` / `MLXVLM` / `MLXLLM` / `MLXEmbedders` have moved out of `mlx-swift-examples` into a dedicated repo `mlx-swift-lm` (latest tag `3.31.3` as of 2026-05-03). The audit's earlier reference to `mlx-swift-examples` for VLM is stale; new dep URL is `https://github.com/ml-explore/mlx-swift-lm`.

---

## Critical files

- `Sources/Views/EntryRowView.swift`
- `Sources/Views/LibraryView.swift`
- `Sources/Services/ImageService.swift`
- `Sources/Services/PhotoImportService.swift`
- `Sources/Services/PipelineService.swift`
- `Sources/Models/Entry.swift`
- `Sources/Models/DatabaseService.swift`
- `Sources/Models/Identification.swift` (NSCache pattern to mirror)
- `Sources/App/ModelConfig.swift`
- `Sources/AI/PythonRPCTransport.swift`
- `Sources/AI/ModelLease.swift`
- `Sources/AI/GemmaActor.swift`
- `Sources/AI/FluxActor.swift`
- `Sources/Views/IllustrationStyleSheet.swift`
- `Naturista/Resources/Naturista.entitlements`

---

## Verification

**Item 1 (thumbnails + cache).**
- Generate a 5,000-entry test library (script duplicates an existing entry with new IDs).
- Cold launch; scroll the gallery top to bottom. Use Instruments **Allocations + Time Profiler**.
- Confirm: RSS stays bounded (target: <500MB delta from idle), decoded image count tracks visible tiles only, no `LocalImage.task` reload on filter switches that revisit cached entries.
- Side-by-side smoke test: gallery thumbnail looks crisp; detail view still full-res.

**Item 2 (capability detection).**
- Manually unit-test thresholds with mocked `SystemCapability` values.
- On a real machine: confirm the picker disables incompatible models with the correct caption, marginal models show the slow-warning, and compatible models are unannotated.
- Trigger a low-disk simulation (or temp-fill the volume) and confirm download is refused before launching `hf`.

**Item 3 (LazyVGrid + windowed pagination).**
- With the same 5,000-entry library, scroll the grid; Time Profiler should show frame budget under 16ms and `EntryRowView` body invocations only for visible cells.
- Pagination bar shows at most ~9 items (first, last, current ± 2, ellipses).

**Item 4 (models move).**
- On a machine with existing `~/.cache/<modelDir>`, launch the app once; confirm directories migrated to `~/Library/Application Support/Naturista/Models/`, the migration flag is set, and a subsequent generate call works without re-download.

**MAS spike (Option B prerequisite).**
- New throwaway target. Add `mlx-swift` SPM dep. Load FLUX.1-schnell-mlx weights in process. Generate a 1024×1024 image. Time it. Memory-profile it. Compare to current Python pipeline. Decision criterion: within 1.5× of current latency and reliable across 10 runs.
