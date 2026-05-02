# Naturista Spike Scripts

## Phase 0.1a — Identification Spike

### Setup

```bash
pip install mlx-vlm
```

Download Gemma 4 31B Dense 4-bit MLX weights and place in:

```
~/.cache/gemma-4-31b-dense-4bit-mlx/
```

### Run

```bash
python identify.py /path/to/photo.jpg
```

Output JSON to stdout:
```json
{
  "model_confidence": "high",
  "top_candidate": {
    "common_name": "Common dandelion",
    "scientific_name": "Taraxacum officinale",
    "family": "Asteraceae"
  },
  "alternatives": [...],
  "visible_evidence": [...],
  "missing_evidence": [...],
  "safety_note": "Do not consume or handle based only on this identification."
}
```

### Test

```bash
python test_cli.py /path/to/photo.jpg
python test_cli.py /path/to/photo.jpg --output /path/to/result.json
```

### Test sets

**Common test set (20 plants) — exit criterion: 14/20 top-candidate correct, 4/6 remaining marked uncertain or low-confidence:**

Photograph each in good light, whole plant visible:
1. Dandelion
2. White clover
3. Common nettle
4. Dog rose
5. Pedunculate oak
6. Common ivy
7. Bramble
8. Oxeye daisy
9. Creeping thistle
10. Greater plantain
11. Silverweed
12. Wood sorrel
13. Primrose
14. Bluebell
15. Foxglove
16. Hogweed
17. Elder
18. Hawthorn
19. Silver birch
20. Broad buckler fern

**Hard test set (10 plants) — informational only:**
1. Cultivar rose (named variety)
2. Vegetative-stage nettle (no flowers)
3. Poor lighting oak shot
4. Partial view bramble
5. New Zealand native plant
6. Japanese knotweed
7. Hemlock (vs cow parsley look-alike)
8. Dock (vs sorrel look-alike)
9. Young foxglove (pre-flower)
10. Himalayan balsam

### Model path

Configure via environment variable:

```bash
export GEMMA_MODEL_PATH=~/.cache/gemma-4-31b-dense-4bit-mlx
python identify.py photo.jpg
```

---

## Phase 0.1b — Illustration Spike

### Setup

```bash
pip install flux-mlx
```

Download FLUX schnell quantised MLX weights and place in:

```
~/.cache/flux-schnell-mlx/
```

### Run

```bash
python illustrate.py /path/to/photo.jpg /path/to/identification.json /path/to/output.png
```

The photo path is accepted for reference but the illustration is generated entirely from the Gemma JSON output.

### FLUX prompt template

```
A botanical illustration of [scientific_name], [common_name], in the style of 19th century natural history plates. [subject_description]. On plain neutral background. No text, no labels, no border.
```

`subject_description` is assembled by joining `visible_evidence` array elements with "; ". If the joined result is shorter than 20 characters, a fallback description is used instead.

### Output

JSON to stdout:

```json
{"illustration_path": "/path/to/output.png", "seed": 12345, "timing_seconds": 45}
```

On timeout (>300s) or error:

```json
{"error": "generation_failed"}
```

### Test

```bash
python test_illustration.py /path/to/photo.jpg /path/to/identification.json /path/to/output.png
```

### Model path

Configure via environment variable:

```bash
export FLUX_MODEL_PATH=~/.cache/my-flux-model
python illustrate.py photo.jpg identification.json output.png
```

---

## Phase 0.1c — Layout Spike

This is a manual step, no code involved.

1. Run Phase 0.1a and 0.1b for 5 plants from the common test set
2. Take the real Gemma JSON outputs and FLUX PNGs
3. Open Figma (or Affinity, Sketch) and hand-compose one botanical plate using:
   - Aged paper texture (find a reference from Curtis's Botanical Magazine)
   - FLUX illustration
   - Title: common name
   - Scientific name: italic
   - Family
   - Notes panel
   - Border

**Exit criterion:** the composed plate reads as a coherent botanical plate. Title, scientific name, family, illustration, notes panel, paper texture, border all sit together without fighting each other.

---

## Prerequisites to run spikes

1. macOS with Apple silicon
2. 32GB+ unified memory (48GB recommended)
3. Gemma 4 31B Dense 4-bit MLX weights (~20GB)
4. FLUX schnell quantised MLX weights (~6-12GB)
5. Test photos (20 common + 10 hard plants)