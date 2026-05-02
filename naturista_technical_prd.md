# Naturista technical PRD

## Product summary

Naturista is a personal naturalist library for Mac, iPhone and iPad. The user captures a plant, insect, animal, fungus or other natural subject. The system identifies it, generates a structured record, creates a vintage natural-history illustration, flags possible toxicity or danger, and stores the result in a clean local library.

The Mac is the processing hub. It performs identification, enrichment, image generation and library management. The iPhone and iPad apps act as capture, browsing and sync clients. They can send photos to the Mac for processing and view completed entries once synced.

The intended output is not just a labelled photo. Naturista should turn field observations into illustrated naturalist plates: textured paper, botanical or zoological drawing style, serif typography, common and scientific names, callouts, notes and visual variants.

## Goals

Naturista should let users build a private, local-first field journal with minimal effort. A user should be able to take a photo, submit it, and later receive a polished entry containing:

- Original observation photo.
- AI-assisted identification.
- Common name.
- Scientific name.
- Taxonomic group.
- Description.
- Habitat and distribution notes.
- Potential danger, toxicity or handling warnings.
- Generated vintage-style illustration.
- Optional poster-style naturalist plate.
- Capture date, location and device metadata where available.
- Confidence score and uncertainty notes.

The app should feel like a modern private library, not a social nature app. The core experience is collection, curation and personal discovery.

## Non-goals for the first release

Naturista should not attempt to be a professional diagnostic, medical, veterinary or foraging safety tool. It can flag possible risks, but it must not present identification or toxicity information as authoritative.

The first release should not depend on cloud inference. The Mac should perform processing locally where possible. Optional cloud fallback can be considered later, but it should not be required for the product to work.

The iPhone and iPad apps should not run the full generation pipeline in the first release. They should capture, upload, browse and sync.

Community sharing, social feeds, marketplace features and public species databases are out of scope for the first release.

## Target platforms

### Mac

The Mac app is the primary application. It manages the local library and runs the AI processing pipeline.

Primary target:

- Apple silicon Macs.
- macOS 15 or later [verify].
- Recommended: M-series Mac with at least 24GB unified memory.
- Best experience: M4 MacBook Pro or Mac Studio with 48GB+ unified memory.

### iPhone and iPad

The mobile apps are thin clients.

They should support:

- Capturing or importing photos.
- Adding optional notes.
- Sending captures to the Mac.
- Viewing synced processed entries.
- Searching and browsing the local/mobile library.
- Offline viewing of previously synced entries.

Processing on mobile is limited to image capture, basic pre-processing, queueing and sync.

## Core user flow

A user sees a plant or animal and opens Naturista on iPhone. They capture a photo and optionally add notes such as “seen near river path” or “small yellow flower, about 10cm tall”. The phone stores the observation locally and queues it for Mac processing.

When the Mac is available on the same network, the observation syncs to the Mac. The Mac imports the image, performs subject analysis, attempts identification, generates structured metadata, produces an illustrated naturalist plate, and stores the completed entry in the local library.

The completed entry syncs back to the phone and iPad. The user can then browse the generated poster, see the original photo, inspect the identification, edit fields, correct the species, regenerate the illustration, or export the plate.

## Main product surfaces

### Capture view

The mobile capture view should be quick and low-friction.

Required fields:

- Photo.
- Optional note.
- Optional location.
- Optional privacy setting for location.
- Optional category hint: plant, insect, animal, fungus, unknown.

The user should be able to capture without entering any text.

### Processing queue

The Mac app needs a visible queue showing pending, processing, completed and failed observations.

Each queue item should show:

- Thumbnail.
- Source device.
- Capture date.
- Current status.
- Identification state.
- Generation state.
- Error message if failed.
- Retry action.

### Library

The library is the main collection view.

Entries should support:

- Grid view.
- List view.
- Taxonomic grouping.
- Search by common name, scientific name, description, location, date and notes.
- Filters for plants, insects, animals, fungi and unknowns.
- Filters for poisonous, irritating, dangerous or safe/unknown.
- Favourites.
- Recently added.
- Entries needing review.

### Entry detail view

Each entry should contain:

- Generated plate.
- Original image.
- Identification summary.
- Common name.
- Scientific name.
- Taxonomy.
- Confidence.
- Description.
- Notes.
- Safety/toxicity section.
- Capture metadata.
- Generated assets.
- Edit and regenerate controls.

The app should show uncertainty clearly. If the model is unsure, the entry should be marked as “Needs review” rather than pretending to be correct.

### Poster view

The poster view is a rendered naturalist plate. It should support export as PNG, PDF and optionally TIFF.

For the dandelion example, the poster would include:

- Title: Common dandelion.
- Scientific name: Taraxacum officinale.
- Family: Asteraceae.
- Main seed head illustration.
- Flower illustration if applicable.
- Leaf illustration.
- Root illustration where useful.
- Labelled callouts.
- Notes panel.
- Textured paper background.
- Subtle border and plate number.

## AI processing pipeline

The Mac processing pipeline should be modular. Each stage should produce inspectable intermediate output so failures can be debugged and retried.

### Stage 1: Import and normalisation

Input:

- Image from iPhone, iPad or Mac.
- Optional user note.
- Optional category hint.
- Optional location/date metadata.

Processing:

- Store original image unchanged.
- Generate working copy.
- Extract EXIF metadata.
- Generate thumbnail.
- Detect orientation.
- Apply basic image quality checks.
- Detect whether the subject is usable.

Output:

- Observation record.
- Original asset.
- Normalised working image.
- Thumbnail.
- Metadata.

### Stage 2: Subject analysis

The system should identify the primary subject and determine broad category.

Possible categories:

- Plant.
- Flowering plant.
- Tree.
- Fungus.
- Insect.
- Bird.
- Mammal.
- Reptile/amphibian.
- Marine life.
- Unknown natural object.
- Non-natural or invalid image.

The model should identify visible parts where possible:

- Flower.
- Leaf.
- Stem.
- Seed head.
- Root.
- Bark.
- Wing.
- Body segments.
- Legs.
- Antennae.
- Shell.
- Fur.
- Feathers.

Output should be structured JSON.

Example:

```json
{
  "subject_category": "flowering_plant",
  "visible_parts": ["seed_head", "stem", "basal_leaves"],
  "image_quality": "good",
  "identification_difficulty": "medium",
  "notes": "Seed head is visible, flower is not visible, leaves are partially visible."
}
```

### Stage 3: Identification

Identification should combine vision model analysis with retrieval from a local species knowledge base.

The identification output should include:

- Candidate species.
- Common names.
- Scientific names.
- Confidence per candidate.
- Why the candidate was selected.
- What visual evidence supports it.
- What evidence is missing.
- Whether the entry needs human review.

Example:

```json
{
  "top_candidate": {
    "common_name": "Common dandelion",
    "scientific_name": "Taraxacum officinale",
    "family": "Asteraceae",
    "confidence": 0.82
  },
  "alternatives": [
    {
      "common_name": "Cat's-ear",
      "scientific_name": "Hypochaeris radicata",
      "confidence": 0.31
    }
  ],
  "review_required": true,
  "reasoning_summary": "The image shows a spherical pappus seed head consistent with dandelion, but leaves and flower are not sufficiently visible for definitive identification."
}
```

### Stage 4: Data enrichment

Once a likely identification exists, the app should enrich the entry from a local or bundled reference database.

Fields:

- Common name.
- Scientific name.
- Taxonomy.
- Description.
- Habitat.
- Distribution.
- Seasonality.
- Similar species.
- Safety/toxicity notes.
- Handling notes.
- Edibility warning where relevant.
- Conservation status where available [verify].
- Source references.

The app should distinguish between generated text and sourced facts. Ideally, safety/toxicity data should come from curated sources rather than only from a language model.

### Stage 5: Safety and toxicity classification

Each entry should receive a safety status:

- No known common hazard.
- Irritant.
- Toxic if ingested.
- Toxic to pets.
- Venomous.
- Biting/stinging risk.
- Allergenic.
- Environmentally hazardous/invasive [verify].
- Unknown, do not handle or consume.

The UI must not say “safe to eat” unless the user has explicitly enabled an expert mode, and even then it should use cautious wording. The default behaviour should be conservative.

For plants and fungi, the app should avoid foraging advice. It can state that a species has reported toxicity or lookalikes, but should not tell the user to consume anything.

### Stage 6: Illustration planning

Before generating the final plate, the system should create an illustration plan.

The plan defines:

- Plate title.
- Layout type.
- Main subject.
- Supporting illustrations.
- Labels.
- Notes panel.
- Background style.
- Typography style.
- Paper texture.
- Colour treatment.
- Aspect ratio.

Example:

```json
{
  "plate_title": "Common dandelion",
  "scientific_name": "Taraxacum officinale",
  "family": "Asteraceae",
  "layout": "botanical_plate_portrait",
  "elements": [
    {
      "type": "main_illustration",
      "subject": "dandelion seed head on hollow stalk",
      "position": "centre"
    },
    {
      "type": "detail_illustration",
      "subject": "single achene with pappus",
      "position": "left_upper"
    },
    {
      "type": "detail_illustration",
      "subject": "yellow flower head",
      "position": "left_middle"
    },
    {
      "type": "detail_illustration",
      "subject": "basal rosette leaf",
      "position": "right_upper"
    },
    {
      "type": "detail_illustration",
      "subject": "taproot",
      "position": "right_lower"
    }
  ],
  "labels": [
    "seed head (pappus)",
    "achene",
    "hollow flowering stalk",
    "basal rosette leaf",
    "taproot"
  ],
  "style": "19th century botanical illustration on aged textured paper"
}
```

### Stage 7: Image generation

The app should generate one or more illustrated assets.

Required assets:

- Main naturalist plate.
- Transparent or plain-background subject illustration [optional for v1].
- Thumbnail crop.

The generation model should be local on Mac.

Recommended model direction for high-quality local generation on a 48GB Apple silicon Mac:

- Primary: FLUX-family model with MLX or Core ML-compatible pipeline.
- Best quality target: quantised FLUX dev-class model.
- Faster draft target: smaller FLUX schnell/klein/lite-class model.
- Fallback: SDXL or SDXL Turbo for broader tooling support.

The app should support draft/final generation:

- Draft mode: faster, lower steps, used for preview.
- Final mode: slower, higher quality, used for export.

The generated plate should follow the observation, but it should not blindly reproduce every photographic detail. It should produce an idealised naturalist illustration based on the identified species and visible subject.

### Stage 8: Plate composition

Text-heavy posters should not rely on the image model to render all text accurately. The generated artwork and the final poster composition should be separated.

Preferred approach:

1. Generate illustration elements without text.
2. Compose final plate in native app code.
3. Render titles, labels, callout lines and notes using native typography.
4. Export final result.

This avoids common image-generation failures such as misspelled labels, broken scientific names and unreadable notes.

The poster renderer should support:

- Paper texture background.
- Border.
- Plate number.
- Title.
- Scientific name.
- Family.
- Illustration placement.
- Labels and leader lines.
- Notes box.
- Export at print resolution.

## Local model architecture

### Vision and identification

Potential local components:

- Vision-language model for image understanding.
- Embedding model for matching observations against known species descriptions.
- Local species database for retrieval.
- Small language model for structured summarisation.

The system should not rely on one model for everything. Identification should be treated as a probability and evidence problem.

Suggested architecture:

```text
Photo
  ↓
Image quality + subject detection
  ↓
Vision-language description
  ↓
Candidate species retrieval
  ↓
Species comparison
  ↓
Structured identification result
  ↓
Human-editable entry
```

### Image generation

Suggested architecture:

```text
Observation + identification
  ↓
Illustration plan JSON
  ↓
Prompt builder
  ↓
Local image model
  ↓
Generated illustration assets
  ↓
Native plate compositor
  ↓
Final poster PNG/PDF
```

### Text generation

A local language model can produce descriptions and notes, but factual fields should be grounded in retrieved reference data.

Suggested output contract:

```json
{
  "common_name": "Common dandelion",
  "scientific_name": "Taraxacum officinale",
  "family": "Asteraceae",
  "description": "...",
  "habitat": "...",
  "safety": {
    "status": "low_common_hazard",
    "notes": "...",
    "confidence": "medium"
  },
  "needs_review": true,
  "sources": []
}
```

## Data model

### Observation

```json
{
  "id": "uuid",
  "created_at": "datetime",
  "captured_at": "datetime",
  "source_device": "iPhone",
  "original_image_id": "asset_uuid",
  "working_image_id": "asset_uuid",
  "user_note": "string",
  "location": {
    "latitude": "number",
    "longitude": "number",
    "accuracy": "number",
    "privacy_level": "exact | approximate | hidden"
  },
  "status": "queued | processing | complete | failed | needs_review"
}
```

### Identification

```json
{
  "id": "uuid",
  "observation_id": "uuid",
  "common_name": "string",
  "scientific_name": "string",
  "family": "string",
  "taxonomic_rank": "species",
  "confidence": "number",
  "alternatives": [],
  "evidence": [],
  "missing_evidence": [],
  "review_required": "boolean"
}
```

### Library entry

```json
{
  "id": "uuid",
  "observation_id": "uuid",
  "identification_id": "uuid",
  "title": "string",
  "description": "string",
  "habitat": "string",
  "distribution": "string",
  "seasonality": "string",
  "safety_status": "string",
  "toxicity_notes": "string",
  "user_notes": "string",
  "tags": [],
  "favourite": "boolean",
  "created_at": "datetime",
  "updated_at": "datetime"
}
```

### Generated asset

```json
{
  "id": "uuid",
  "entry_id": "uuid",
  "asset_type": "plate | illustration | thumbnail | export",
  "prompt": "string",
  "model": "string",
  "seed": "number",
  "generation_settings": {},
  "file_path": "string",
  "created_at": "datetime"
}
```

## Storage

The product should be local-first.

Recommended storage:

- SQLite for metadata.
- File-system asset store for images and generated outputs.
- App-managed library bundle or folder.
- Optional iCloud Drive integration later [verify].
- Local network sync between iPhone/iPad and Mac.

The library should be portable. A user should be able to back up or move their Naturista library as a single package or folder.

## Sync model

The iPhone and iPad apps should sync with the Mac over the local network.

Minimum viable sync:

- Mobile device discovers Mac app on same network.
- User pairs device with Mac.
- Mobile uploads pending observations.
- Mac processes observations.
- Mobile downloads completed entries and generated assets.

Recommended pairing:

- QR code displayed on Mac.
- Mobile scans QR code.
- Shared key established.
- Local encrypted connection used for sync.

Sync should tolerate offline usage. Captures remain queued on mobile until the Mac is available.

## Privacy

Naturista should be privacy-first.

Requirements:

- Original photos remain local unless user explicitly exports or shares.
- Location data is optional.
- User can remove or approximate location.
- No cloud processing in v1 unless explicitly enabled later.
- Local library can be encrypted [verify for v1].
- Pairing between devices must be authenticated.
- Sync traffic should be encrypted.

## Safety and trust requirements

The app must treat identification as uncertain unless verified.

Required UI states:

- High confidence.
- Medium confidence.
- Low confidence.
- Needs review.
- Conflicting candidates.
- Insufficient image quality.

For toxicity and danger:

- Use conservative wording.
- Never imply medical, veterinary or foraging certainty.
- Include “Do not consume or handle based only on this identification” wording in relevant contexts.
- Allow the user to mark an entry as personally verified.

The app should preserve the original photo alongside the generated plate so the user can always compare the source observation.

## Functional requirements

### Capture

- User can capture a new photo from iPhone or iPad.
- User can import an existing photo.
- User can add optional notes.
- User can choose whether to include location.
- Capture can be queued offline.
- Capture syncs to Mac when available.

### Processing

- Mac receives queued observations.
- Mac runs identification.
- Mac creates structured entry.
- Mac flags uncertainty.
- Mac generates naturalist illustration.
- Mac composes poster.
- Mac stores all outputs.

### Editing

- User can edit common name.
- User can edit scientific name.
- User can correct taxonomy.
- User can edit description and notes.
- User can change safety status.
- User can regenerate illustration.
- User can regenerate poster layout.
- User can mark entry as verified.

### Library

- User can browse all entries.
- User can search entries.
- User can filter by category.
- User can filter by safety status.
- User can group by date, location or taxonomy.
- User can favourite entries.
- User can delete entries.
- User can export individual entries.

### Export

- Export poster as PNG.
- Export poster as PDF.
- Export entry data as JSON.
- Export original photo.
- Optional later: export a field-guide collection as a PDF book.

## Non-functional requirements

### Performance

On a 48GB Apple silicon Mac:

- Import and thumbnail generation should complete in seconds.
- Identification should usually complete in under one minute [verify].
- Draft illustration should complete in a few minutes or less [verify].
- Final illustration may take longer, but should run unattended.
- The app should support queue processing without blocking the UI.

### Reliability

- Failed processing stages should be retryable.
- A failure in image generation should not lose identification data.
- The original photo must never be overwritten.
- The database should be resilient to interrupted processing.
- Long-running generation should survive app backgrounding where possible [verify].

### Quality

Generated plates should be judged against:

- Anatomical plausibility.
- Consistency with identified species.
- Clean composition.
- Readable native-rendered text.
- Good print/export quality.
- Avoidance of invented labels.
- Avoidance of misleading dangerous/safe claims.

## MVP scope

The first usable version should include:

- Mac app with local library.
- iPhone capture app.
- Local network pairing.
- Upload from iPhone to Mac.
- Processing queue on Mac.
- Identification pipeline.
- Structured entry creation.
- Safety/toxicity flag.
- Vintage botanical/naturalist plate generation.
- Native poster compositor.
- Sync completed entries back to iPhone.
- PNG/PDF export.

MVP can limit supported subject types to:

- Common plants.
- Flowers.
- Trees.
- Fungi.
- Common insects.

Animals can be added once the core pipeline is stable.

## Suggested v1 technical stack

### Mac app

- Swift / SwiftUI.
- SQLite or SwiftData for metadata.
- File-based asset storage.
- MLX or Core ML for local inference.
- Local HTTP/WebSocket service for paired device sync.
- Background processing queue.
- Native Core Graphics/PDFKit poster renderer.

### iPhone/iPad app

- Swift / SwiftUI.
- Camera capture.
- Local queue storage.
- Bonjour/local discovery.
- Pairing via QR code.
- Sync client.
- Offline library viewer.

### AI services inside the Mac app

Run as either:

- Embedded Swift modules where practical.
- Local Python service for early prototypes.
- Later migration to Swift/MLX/Core ML for productisation.

A Python service is acceptable for prototype speed, but a packaged app will need careful dependency management.

## Poster generation strategy

The product should not ask the image model to generate the final complete poster with all text. That will produce spelling errors and inconsistent labels.

Use a two-layer strategy:

### Layer 1: Artwork generation

Generate clean illustrations:

- Main subject.
- Detail studies.
- Optional leaf/root/flower/insect detail.
- Textured paper background if desired.

Prompts should request no text, no labels and no border.

### Layer 2: Native composition

The app places:

- Title.
- Latin name.
- Family.
- Labels.
- Callout lines.
- Notes box.
- Border.
- Plate number.
- Paper texture.
- Final layout.

This gives the product a much more polished and controllable result.

## Example generated plate specification

For the attached dandelion-like input, the system might produce:

```json
{
  "title": "Common dandelion",
  "scientific_name": "Taraxacum officinale",
  "family": "Asteraceae",
  "plate_number": "Plate XII",
  "layout": "portrait_botanical",
  "main_subject": "mature dandelion seed head on hollow green stalk",
  "supporting_details": [
    "yellow flower head",
    "single achene with pappus",
    "basal rosette leaf",
    "taproot",
    "spent capitulum"
  ],
  "labels": [
    "seed head (pappus)",
    "achene",
    "hollow flowering stalk",
    "spent capitulum",
    "basal rosette leaf",
    "taproot"
  ],
  "notes": [
    "Perennial herb with a deep taproot.",
    "Leaves form a basal rosette with variable toothed margins.",
    "Flower head composed of many yellow ligulate florets.",
    "The spherical seed head carries achenes, each attached to a pappus for wind dispersal.",
    "Flowering stalks are hollow and exude milky latex when cut.",
    "Common in meadows, lawns and disturbed ground."
  ],
  "safety": {
    "status": "low common hazard",
    "note": "May cause irritation in some people. Do not consume based only on this identification."
  }
}
```

## Risks

### Identification accuracy

A single photo may not show enough information for reliable identification. The system must support uncertain results and alternatives.

Mitigation:

- Require confidence scores.
- Store alternatives.
- Mark entries as needing review.
- Encourage additional photos for low-confidence entries.

### Toxicity and danger claims

Incorrect safety claims could be harmful.

Mitigation:

- Conservative language.
- Curated safety sources.
- No consumption recommendations.
- Clear uncertainty indicators.

### Text in generated images

Image models are poor at reliable text rendering.

Mitigation:

- Generate artwork only.
- Render all text natively.

### Local model packaging

Large models increase app size and complicate installation.

Mitigation:

- Download models on demand.
- Offer quality presets.
- Allow model location management.
- Provide a small default model and optional high-quality model pack.

### Performance

High-quality generation may be slow on laptops.

Mitigation:

- Queue-based processing.
- Draft/final modes.
- Batch overnight processing.
- Pause/resume queue.
- User-selectable quality levels.

## Open questions

- Should v1 support only plants first, or include insects and animals from the start?
- Should the model pack be bundled, downloaded after install, or user-managed?
- Should the app include a curated offline species database, or use user-provided/reference packs?
- Should location be exact, approximate or disabled by default?
- Should completed plates sync in full resolution to mobile, or should mobile receive optimised versions?
- Should the Mac app expose a local API for advanced users?
- Should generated plates be editable as layered compositions?
- Should users be able to create themed collections, such as “garden”, “walks”, “Scotland”, “fungi”, or “dangerous species”?

## Success criteria

Naturista succeeds if a user can capture a natural subject and later receive a beautiful, structured, editable entry without needing to understand the underlying models.

For the first release, success means:

- Capture from iPhone works reliably.
- Mac processing produces useful identifications.
- The generated plates are visually compelling.
- Text labels are readable and correct.
- The local library feels fast and private.
- Users can correct mistakes.
- The system is honest about uncertainty.
