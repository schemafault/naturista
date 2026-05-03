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

### 4. Move models from `~/.cache/` to `~/Library/Application Support/Naturista/Models/` — Effort: M (1–2 days)

**Why now (regardless of MAS).** `~/.cache/` is purgeable by macOS — users can lose 17GB of weights to "Free up storage" prompts and not know why the app stopped working. Also a prerequisite for any MAS path.

- `AppPaths.models` is already defined at `Sources/App/ModelConfig.swift:217`. Switch the model-path resolution to use it.
- One-shot migration on launch: if old `~/.cache/<modelDir>` exists and new path doesn't, `mv` the directory; flag completion in `UserDefaults`.
- Update `GemmaModelDownloader` to write to the new location.

### 5. Strategic decision: MAS path

This is a **decision**, not code. Make it before investing further in MAS-specific work. See next section.

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

### Option C — Don't ship to MAS; stay Developer ID + notarization

Current architecture works. Notarize, distribute via website + Sparkle.

- **Effort:** S (already there).
- **Loses:** MAS discoverability, in-app purchase, App Store updates, "trust badge" for non-technical users.
- **Gains:** no architectural rewrite, Python ecosystem stays open, faster iteration.

**Verdict:** Defensible indefinitely for a niche local-AI app with technical-leaning users.

---

## MAS-blocking remediation (only if A or B is chosen)

These come AFTER the spike + decision. Item 4 above (move models out of `~/.cache/`) is shared.

| Task | Files | Effort |
|---|---|---|
| Enable sandbox | `Naturista/Resources/Naturista.entitlements` | S |
| Replace `/tmp/naturista_*.log` with `FileManager.default.temporaryDirectory` | `Sources/AI/GemmaActor.swift:85`, `Sources/AI/FluxActor.swift:33` | S |
| Replace `hf` CLI with native Swift HuggingFace downloader (`URLSession`, parse `model.safetensors.index.json`, parallel downloads) | `Sources/App/ModelConfig.swift:120` | M |
| Remove all subprocess spawning (Option B) OR bundle Python (Option A) | `Sources/AI/PythonRPCTransport.swift` | XL |

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
