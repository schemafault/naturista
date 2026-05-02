# Naturista v0.1 PRD

## Product principle

Naturista runs entirely local. No cloud inference, no external API dependencies for identification, no data leaves the user's machine. This is a hard constraint that drives the architecture. It enables offline use and privacy-first collection building.

A relaxed-constraint version (PlantNet API plus local FLUX) would test the plate aesthetic faster and avoid most of the v0.1 risk. The constraint is deliberate. It is also the reason this PRD is structured as a phased spike rather than a single milestone.

## Problem statement and target user

Naturista is a personal illustrated field journal for amateur foragers and naturalists with some plant knowledge. The user imports a photo, gets a plausible AI identification, and ends up with a vintage-style botanical plate they can save and export.

Primary user characteristics:

- Some plant knowledge, not a professional botanist
- Wants observations turned into structured, attractive records
- Understands AI can be wrong and treats the output accordingly
- Values privacy and offline use
- Owns Apple silicon hardware with 32GB unified memory or more

Educators, professional botanists, and casually curious users may benefit but are not the primary audience and do not shape v0.1 decisions.

## What v0.1 must prove

Four risky assumptions sit underneath the product. Any one of them failing makes the rest pointless.

1. Local VLM produces useful botanical IDs from arbitrary user photos.
2. Local image diffusion produces aesthetically convincing vintage botanical plates.
3. SwiftUI Canvas compositor produces print-quality typographic layouts.
4. End-to-end macOS app integrates the pipeline reliably.

Risk is not evenly distributed. Assumptions 1 and 2 are research questions. Assumptions 3 and 4 are engineering work. v0.1 is structured to retire the research risk before committing to the engineering work.

## Phased plan

v0.1 ships in four phases. Each phase has an exit criterion. If a phase fails its exit, the project either pivots or stops. No further phase begins until the previous one passes.

### Phase 0.1a, identification spike

A Python CLI script. No UI, no SQLite, no Swift.

- Loads Gemma 4 31B Dense at 4-bit via mlx-vlm
- Accepts a photo path
- Outputs the structured identification JSON specified below
- Run against the common test set (20 plants)
- Run against the hard test set (10 plants)

**Exit criterion:** common set hits at least 14/20 top-candidate-correct, with at least 4 of the remaining 6 marked uncertain or low-confidence rather than confidently wrong. Hard set is informational only at this stage.

**If this fails:** the local-VLM premise is not viable. Options are a different VLM family (Qwen2.5-VL, MiniCPM-V), a different size, or relaxing the local-only constraint. Do not start phase 0.1b.

### Phase 0.1b, illustration spike

A second Python CLI script.

- Takes a Gemma JSON output from phase 0.1a
- Constructs the FLUX prompt per the template below
- Generates an illustration via FLUX schnell quantised MLX
- Outputs a PNG

**Exit criterion:** for 5 hand-chosen plants from the common set, the resulting illustrations are recognisably the right plant and aesthetically convincing as 19th-century botanical drawings. This is a subjective gate, judged by Nathan against reference plates from Curtis's Botanical Magazine or similar. If schnell output looks generic or mushy on fine detail, retest with FLUX dev-class quantised. If dev-class also fails the aesthetic bar, the plate concept does not work with current diffusion models.

**If this fails:** the product becomes "AI-assisted plant ID and notes" without the plate aesthetic. Reconsider whether that is worth building.

### Phase 0.1c, layout spike

Hand-compose one finished plate in any tool (Figma, Affinity, Sketch). Use real outputs from 0.1a and 0.1b. The goal is to confirm the typographic layout works at the target export size before any SwiftUI Canvas code is written.

**Exit criterion:** the composed plate reads as a coherent botanical plate. Title, scientific name, family, illustration, notes panel, paper texture, border all sit together without fighting each other.

### Phase 0.1, the app

Only begun after 0.1a, 0.1b, and 0.1c have all passed. Builds the SwiftUI app described in the rest of this PRD.

## Hardware floor

v0.1 requires Apple silicon Mac with 32GB unified memory minimum.

| Configuration | Status | Notes |
|---|---|---|
| 16GB any chip | Will not run | Gemma 4 31B at 4-bit alone is ~20GB |
| 32GB M-series | Minimum | Tight: Gemma 4-bit + FLUX schnell + Python + app + OS |
| 48GB+ M-series Pro/Max | Recommended | Comfortable headroom |

Note that 48GB requires M-series Pro or Max chip. Base M-series tops out at 32GB.

Gemma 4 31B at 8-bit needs ~34GB for the model alone and is excluded from v0.1. 8-bit becomes a v0.2 option contingent on a 64GB+ machine.

## First-run model acquisition

The app ships without weights. v0.1 uses option 2: instructions to download manually and place files in the model directory. README documents the exact paths and Hugging Face links. v0.2 introduces in-app download with progress UI.

This choice is acceptable because v0.1 ships to a technical audience comfortable with the Hugging Face CLI.

## Photo guidance

VLM identification quality depends heavily on photo composition. The app surfaces guidance on first import and in help.

- Good: whole plant in frame, clear leaves and flowers, multiple angles where possible, natural lighting.
- Poor: distant single shot, heavy occlusion, only bark or shadow.
- Multiple photos of the same plant increase confidence in v0.2; v0.1 accepts a single photo per entry.

The app does not pre-screen photo quality in v0.1. E4B triage is a v0.2 candidate.

## User flow

1. User opens app and clicks Import Photo (file picker only).
2. App runs Gemma 4 identification in a Python subprocess.
3. Identification panel shows top candidate, alternatives, model certainty bucket, visible evidence, missing evidence, safety note.
4. User clicks Generate Plate.
5. App runs FLUX schnell illustration generation.
6. App composes plate in SwiftUI Canvas.
7. App saves entry to SQLite.
8. User can edit notes, retry the full pipeline, or export plate as PNG.

There is no re-identify button, no separate regenerate button, and no per-stage retry. Retry reruns the whole pipeline from the original photo. Notes are preserved across retries; everything else is regenerated.

## Identification quality criteria

### Common test set, 20 plants

Dandelion, clover, nettle, rose, oak, ivy, bramble, daisy, thistle, plantain, silverweed, wood sorrel, primrose, bluebell, foxglove, hogweed, elder, hawthorn, birch, fern. Photographed in good light, full plant visible.

**Target:** 14 of 20 top-candidate correct. Of the remaining 6, at least 4 marked uncertain or low-confidence.

### Hard test set, 10 plants

Plants chosen to stress the model: cultivars (named rose varieties), vegetative-stage plants without flowers, plants in poor lighting, partial views, plants outside Western Europe, look-alike pairs (cow parsley vs hemlock, dock vs sorrel).

**Target:** informational only for phase 0.1a exit. Used to set realistic user expectations in v0.1 messaging. If the hard set hits below 3/10, the safety messaging needs to be more conservative.

If the common set target is not met, v0.1 does not ship. The pipeline is not ready.

## Model configuration

One Gemma 4 model: Gemma 4 31B Dense, 4-bit MLX via mlx-vlm. No 8-bit option in v0.1 (out of memory on the floor hardware). No MoE variant. No size comparison.

One FLUX model: FLUX schnell quantised MLX. Drop to FLUX dev-class quantised only if phase 0.1b fails the aesthetic bar with schnell.

Configuration is code-based. User clones the repo and edits Swift constants:

```swift
enum ModelConfig {
    static let gemmaPath = "~/.cache/gemma-4-31b-dense-4bit-mlx"
    static let fluxPath = "~/.cache/flux-schnell-mlx"
}
```

The Python subprocess receives the config via JSON at startup.

## FLUX prompt construction

The step from identification JSON to image generation prompt is explicit, not magic.

Template:

```
A botanical illustration of [scientific_name], [common_name], in the style of 19th century natural history plates. [subject_description_from_visible_evidence]. On plain neutral background. No text, no labels, no border.
```

Worked example for dandelion:

```
A botanical illustration of Taraxacum officinale, common dandelion, in the style of 19th century natural history plates. Mature spherical white pappus seed head on a hollow upright stalk with basal leaves visible. On plain neutral background. No text, no labels, no border.
```

The app builds the prompt from:

- Scientific name from Gemma output
- Common name from Gemma output
- Subject description assembled from the `visible_evidence` array
- Fixed stylistic hints

If `visible_evidence` is sparse, the app uses a conservative generic description rather than fabricating details.

## Identification output

Gemma 4 returns structured JSON.

```json
{
  "model_confidence": "high | medium | low",
  "top_candidate": {
    "common_name": "string",
    "scientific_name": "string",
    "family": "string"
  },
  "alternatives": [
    {
      "common_name": "string",
      "scientific_name": "string",
      "reason": "string"
    }
  ],
  "visible_evidence": ["string"],
  "missing_evidence": ["string"],
  "safety_note": "Do not consume or handle based only on this identification."
}
```

`model_confidence` is surfaced as coarse buckets, not raw numbers. The UI labels this field as "Model certainty" and includes the explanatory note "Model certainty is not the same as accuracy" alongside it. LLM self-reported confidence is not a reliable proxy for correctness, and users should not read 'high' as 'correct'.

`model_confidence` describes the model's output. `user_status` (defined below) describes user action. The two are independent: a 'high' confidence ID can have `user_status: rejected` if the user disagrees.

## Data model

### Entry

```json
{
  "id": "uuid",
  "created_at": "datetime",
  "captured_at": "datetime | null",
  "original_image_filename": "uuid_original.jpg",
  "working_image_filename": "uuid_working.jpg",
  "identification_json": "text",
  "model_confidence": "high | medium | low",
  "user_status": "unreviewed | confirmed | rejected | failed",
  "illustration_filename": "uuid_illustration.png | null",
  "plate_filename": "uuid_plate.png | null",
  "notes": "string"
}
```

`captured_at` is read from EXIF on import where available. If EXIF is absent, the field is null and the UI shows the import date instead.

`user_status: failed` covers entries where the pipeline did not complete. The original photo is preserved and notes can still be attached. Retry reruns the pipeline.

All filenames are UUID-based. Originals are stored in `assets/originals/`, working copies in `assets/working/`, generated illustrations in `generated/illustrations/`, composed plates in `generated/plates/`.

## Poster compositor

Single botanical portrait layout, rendered in SwiftUI Canvas.

The compositor renders:

- Aged paper texture, native asset
- FLUX illustration, composited
- Title (common name)
- Scientific name (italic)
- Family
- Plate number, auto-incremented at save time, not user-editable in v0.1
- Notes panel, populated from the entry's `notes` field
- Border

Labels with leader lines are not in v0.1. FLUX produces a flat image and the app does not know the geometry of what is inside it. Anatomical labels require image segmentation, which is a v0.2 candidate. v0.1 plates are clean: title, taxonomy, illustration, notes.

All text is rendered natively. FLUX never generates text.

## Technical stack

| Component | Choice |
|---|---|
| Platform | macOS 14.0+ [verify: confirm SwiftUI features used do not require 15.0] |
| UI | SwiftUI |
| Data layer | SQLite via GRDB |
| AI runtime | Embedded Python MLX subprocess |
| IPC | JSON over stdin/stdout |
| Concurrency | Swift Concurrency, async/await, actors |
| Image generation | FLUX schnell MLX |
| Compositor | SwiftUI Canvas |
| Import | File picker only |
| Export | PNG only |

## Directory structure

```
~/Library/Application Support/Naturista/
├── naturista.sqlite
├── assets/
│   ├── originals/
│   └── working/
├── generated/
│   ├── illustrations/
│   └── plates/
└── models/
```

The folder is portable. SQLite stores filenames only, never absolute paths. Directory layout is derived from a constant in the Swift code. Moving the folder between machines must round-trip cleanly, and there is a test for this.

## Storage management

Each entry stores up to four image files: original, working, illustration, plate. Modern phone photos are 4-12MB each. A typical entry footprint is 15-40MB. After 200 entries, the library can exceed 5GB.

v0.1 mitigations:

- Original photos are downsampled to 4MP maximum on import. The full resolution is not retained.
- Working copies are JPEG at quality 0.8.
- Library size is shown in the about panel.

A storage management UI (delete entry, bulk operations, export and clear) is a v0.2 candidate.

## Failure handling

Pipeline stages: import, identify, generate, compose, save. Failures are concrete and named.

| Failure | App behaviour |
|---|---|
| Photo cannot be decoded | Reject at import. No entry created. |
| Gemma returns malformed JSON | Retry once. On second failure, save entry with `user_status: failed` and the raw output in notes. |
| Gemma returns no candidates | Save entry with `user_status: failed` and "no plant detected" in notes. |
| FLUX subprocess crashes or times out (>300s) | Save entry with identification preserved, illustration and plate null, `user_status: failed`. |
| Compositor fails | Save entry with illustration preserved, plate null, `user_status: failed`. |
| SQLite write fails | Show error dialog. No entry persisted. |

Failed entries are visible in the library and can be retried. The original photo is preserved in every failure case except photo decode failure.

## Safety and trust

- Model certainty is shown as high, medium, or low buckets.
- The label reads "Model certainty" and is annotated "Not a measure of accuracy".
- Every entry shows: "Do not consume or handle based only on this identification."
- The hard test set hit rate informs the strength of this messaging in v0.1. If the hard set scores below 3/10, the safety note is reinforced with a second line about look-alike species.
- The original photo is preserved alongside the generated plate.
- Low-confidence entries are visually distinguished in the library (badge, muted styling).

## Out of scope for v0.1

- iPhone or iPad capture clients
- Device sync
- Drag-and-drop import
- Search and filter
- Favourites
- Editing taxonomy or scientific name (notes only)
- Re-identify and standalone regenerate (full pipeline retry only)
- E4B triage stage
- MoE benchmark comparison
- FLUX dev-class as a default path
- Photos library integration
- Model management UI
- Anatomical labels and leader lines on plates
- Multiple poster layouts
- PDF export
- Storage management UI
- Curated species database

## Success criteria

v0.1 ships when all of these are true:

1. Phases 0.1a and 0.1b have passed their exit criteria.
2. Phase 0.1c has produced a layout that reads.
3. The user can import a photo via file picker.
4. Gemma 4 returns the structured identification JSON.
5. The user can click Generate Plate and FLUX produces an illustration.
6. The compositor produces a legible plate with correct scientific name and native text.
7. The entry persists across app restarts.
8. The user can export the plate as PNG.
9. The original photo is preserved.
10. Library folder is portable across Macs with no path rewriting.
11. Failed entries are visible and retryable.

## v0.2 candidates

In rough priority order:

- iPhone capture client with local network pairing
- In-app model download with progress UI
- E4B triage stage for photo quality and category check
- Anatomical labels and leader lines via image segmentation
- Search and filter in library
- Favourites
- FLUX dev-class quantised for higher quality output
- Multiple poster layout variants
- Curated species database for safety grounding
- PDF export
- Storage management UI
- Multi-photo entries
