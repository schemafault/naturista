# Phase 0.1b — FLUX Illustration Spike

## Setup

```bash
pip install flux-mlx  # or equivalent MLX port
```

Download FLUX schnell quantised MLX weights and place in:

```
~/.cache/flux-schnell-mlx/
```

## Run

```bash
python illustrate.py /path/to/photo.jpg /path/to/identification.json /path/to/output.png
```

The photo path is accepted for reference but the illustration is generated entirely from the Gemma JSON output.

## FLUX prompt template

```
A botanical illustration of [scientific_name], [common_name], in the style of 19th century natural history plates. [subject_description]. On plain neutral background. No text, no labels, no border.
```

`subject_description` is assembled by joining `visible_evidence` array elements with "; ". If the joined result is shorter than 20 characters, a fallback description is used instead.

## Output

JSON to stdout:

```json
{"illustration_path": "/path/to/output.png", "seed": 12345, "timing_seconds": 45}
```

On timeout (>300s) or error:

```json
{"error": "generation_failed"}
```

## Test

```bash
python test_illustration.py /path/to/photo.jpg /path/to/identification.json /path/to/output.png
```

## Model path

Configure via environment variable:

```bash
export FLUX_MODEL_PATH=~/.cache/my-flux-model
python illustrate.py photo.jpg identification.json output.png
```