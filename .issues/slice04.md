## Parent

#1

## What to build

Embed a Python FLUX subprocess that generates vintage botanical illustrations. Prompt builder assembles scientific name + common name + visible_evidence into the FLUX prompt template. FLUX schnell quantised MLX runs the generation.

## Prompt builder

Template:
```
A botanical illustration of [scientific_name], [common_name], in the style of 19th century natural history plates. [subject_description_from_visible_evidence]. On plain neutral background. No text, no labels, no border.
```

Assemble from: scientific_name, common_name, visible_evidence array joined with "; ". If visible_evidence is empty or very sparse (< 20 chars total), use a conservative generic description: "a plant in the style of 19th century botanical illustration".

## Interface contract

**Input:**
```json
{
  "action": "generate",
  "photo_path": "/path/to/original.jpg",
  "identification_json_path": "/path/to/identification.json",
  "output_path": "/path/to/output.png",
  "model_path": "~/.cache/flux-schnell-mlx"
}
```

**Output:**
```json
{
  "illustration_path": "/path/to/output.png",
  "seed": 12345,
  "timing_seconds": 45
}
```

On timeout (>300s) or crash: return `{"error": "generation_failed"}`.

## Acceptance criteria

- [ ] Prompt builder correctly assembles scientific name + common name + visible_evidence
- [ ] Conservative fallback prompt when visible_evidence is sparse
- [ ] FLUX schnell loads and generates illustration
- [ ] Output PNG saved to generated/illustrations/ with UUID filename
- [ ] Entry updated: illustration_filename populated
- [ ] Timeout: 300 seconds max, then graceful failure

## Blocked by

#7 (identification panel UI exists and has access to Gemma JSON)