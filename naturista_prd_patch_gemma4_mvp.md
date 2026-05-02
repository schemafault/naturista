# Naturista PRD patch: smaller MVP and Gemma 4 identification model

## Purpose

This patch narrows the first Naturista MVP and updates the model strategy to include Gemma 4 as the primary local identification candidate.

The revised approach separates the product into two AI responsibilities:

1. Identification: determine what the subject is, how confident the system should be, and what evidence is missing.
2. Illustration: generate the vintage naturalist artwork from confirmed or likely structured subject data.

The image-generation model should not be responsible for identification. It should render from structured input produced by the identification pipeline.

## MVP scope change

The first MVP should be smaller than the full Mac/iPhone/iPad product.

### MVP v0.1: Mac-only plant workflow

The first build should focus on a Mac-only workflow for plants.

Required flow:

1. User imports a photo into the Mac app.
2. App runs local visual identification.
3. App produces structured identification JSON.
4. App shows confidence, visible evidence, missing evidence and alternatives.
5. User can confirm or correct the identification.
6. App generates a vintage botanical illustration.
7. App composes the final plate using native-rendered text and layout.
8. App saves the result to a local SQLite-backed library.
9. User can export the generated plate as PNG or PDF.

Out of scope for v0.1:

- iPhone capture.
- iPad browsing.
- Device sync.
- Insects.
- Animals.
- Fungi.
- Cloud processing.
- Social/community features.
- Full species-database coverage.

### MVP v0.2: iPhone capture client

Add the thin iPhone client only after the Mac-only workflow is working.

v0.2 should add:

- iPhone photo capture.
- Optional note entry.
- Local network pairing with Mac.
- Upload from iPhone to Mac.
- Queue status.
- Sync completed entries back to iPhone.

### MVP v0.3: expanded subject support

Add more naturalist categories after the plant workflow is stable.

Candidate additions:

- Common insects.
- Trees.
- Fungi, with stricter safety warnings.
- Multiple photos per observation.
- Higher-quality plate layouts.
- Field-guide collection export.

## Updated model strategy

Naturista should use separate models or model roles for identification, enrichment and image generation.

### Identification model

Primary candidate:

- Gemma 4 26B A4B MoE.

Why:

- Suitable balance of capability and local cost for a 48GB Apple silicon Mac.
- Multimodal image input and text output.
- Better fit for structured visual reasoning than using the image-generation model directly.
- MoE architecture should be more practical than a fully dense model of similar headline size, subject to local runtime support and benchmarking.

Secondary candidate:

- Gemma 4 31B Dense.

Use for:

- High-quality comparison mode.
- Slower final review pass.
- Benchmarking against the 26B A4B model.

Fast candidate:

- Gemma 4 E4B.

Use for:

- Quick category detection.
- Image triage.
- Queue pre-processing.
- Early rejection of invalid/non-natural images.

Alternative models to benchmark:

- Qwen2.5-VL or Qwen3-VL where MLX-compatible versions are available.
- PaliGemma 2 for vision-focused classification and captioning.
- Florence-2 for object detection, captioning and region extraction.
- SigLIP or CLIP-style embeddings for retrieval against local species records.

## Revised AI pipeline

The MVP pipeline should use Gemma 4 as the visual reasoning layer, then ground the result against local species data.

```text
Photo
  ↓
Gemma 4 E4B quick pass
  - subject category
  - image quality
  - visible features
  - whether the image is suitable
  ↓
Gemma 4 26B A4B identification pass
  - likely candidates
  - visual evidence
  - missing evidence
  - confidence
  - alternatives
  ↓
Local species retrieval
  - taxonomy
  - common names
  - habitat
  - toxicity
  - lookalikes
  ↓
Gemma 4 comparison pass
  - compare the image evidence against retrieved candidates
  - produce structured JSON
  ↓
User confirm/edit
  ↓
FLUX image generation
  ↓
Native poster compositor
  ↓
Local library entry
```

For v0.1, this can be simplified to:

```text
Photo
  ↓
Gemma 4 26B A4B
  ↓
Structured identification JSON
  ↓
User confirm/edit
  ↓
FLUX botanical illustration
  ↓
Native poster compositor
  ↓
SQLite library
```

## Identification output contract

The identification stage must return structured data and must not claim certainty where the image is incomplete.

Example output:

```json
{
  "subject_type": "flowering_plant",
  "identification_status": "likely",
  "top_candidate": {
    "common_name": "Common dandelion",
    "scientific_name": "Taraxacum officinale",
    "family": "Asteraceae",
    "confidence": 0.78
  },
  "alternatives": [
    {
      "common_name": "Cat's-ear",
      "scientific_name": "Hypochaeris radicata",
      "reason": "Similar seed head; leaves and flower are not visible enough to exclude it."
    }
  ],
  "visible_evidence": [
    "spherical white pappus seed head",
    "single upright stalk",
    "grassland habitat"
  ],
  "missing_evidence": [
    "basal leaf shape not clearly visible",
    "yellow flower head not visible"
  ],
  "review_required": true,
  "safety_note": "Do not consume or handle based only on this identification."
}
```

## Retrieval and grounding requirement

Gemma 4 should not be treated as the final species authority.

The MVP should use local reference data to ground:

- Scientific name.
- Family.
- Taxonomy.
- Habitat.
- Distribution.
- Toxicity.
- Lookalikes.
- Safety warnings.

The model can reason over candidates, but factual enrichment should come from a curated local species database or bundled reference pack.

This matters because fine-grained naturalist identification is difficult from a single image. Common failure cases include:

- Dandelion vs cat's-ear.
- Edible plants vs toxic lookalikes.
- Similar fungi.
- Hoverfly vs wasp.
- Juvenile birds.
- Partial or low-quality photos.
- Regional variation.

The app should therefore support “likely”, “uncertain” and “needs review” states as first-class outcomes.

## Image-generation model

Image generation should remain separate from identification.

Recommended role:

- Generate vintage botanical or naturalist artwork from a structured subject description.
- Generate artwork only, not final poster text.
- Avoid asking the image model to render labels, scientific names or notes.

Recommended model family:

- FLUX-family model via MLX or Core ML-compatible tooling.
- Use a faster FLUX model for draft generation.
- Use a higher-quality quantised FLUX dev-class model for final output.

The image-generation prompt should be built from confirmed or likely structured data, not directly from the user photo alone.

## Poster compositor requirement

The final plate should be composed natively in the app.

The compositor should render:

- Title.
- Scientific name.
- Family.
- Plate number.
- Labels.
- Leader lines.
- Notes box.
- Border.
- Paper texture.
- Export layout.

This avoids misspelled labels and unreadable text from the image-generation model.

## Revised technical stack for MVP v0.1

### Mac app

- SwiftUI.
- SQLite or SwiftData for metadata.
- File-based asset storage.
- Local model runner for Gemma 4.
- Local image-generation runner for FLUX.
- Background processing queue.
- Native Core Graphics/PDFKit poster renderer.
- PNG and PDF export.

### Prototype allowance

For early experimentation, the AI pipeline may run as a local Python service called by the Mac app.

This is acceptable for rapid prototyping, but production packaging should move towards a cleaner embedded runtime where practical.

## Updated success criteria for MVP v0.1

The first MVP succeeds if:

- A user can import a plant photo on Mac.
- The app returns a plausible identification with confidence and alternatives.
- The app clearly states missing evidence and uncertainty.
- The user can correct the identification before generation.
- The app generates a visually compelling vintage botanical illustration.
- The final poster uses clean, readable native text.
- The entry is saved locally.
- The poster can be exported as PNG or PDF.
- The original photo remains preserved for comparison.

## Key principle

Naturista should be beautiful, but it should also be honest.

The product should make a user feel as if they are building a private illustrated naturalist library, while still making it clear that AI identification can be wrong and should be reviewed where accuracy or safety matters.
