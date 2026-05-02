## Parent

#1

## What to build

Embed a Python MLX subprocess in the app that wraps Gemma 4 31B Dense via mlx-vlm. Communication via JSON over stdin/stdout, managed by a Swift Actor.

## Interface contract

**Input (sent to Python on stdin):**
```json
{
  "action": "identify",
  "photo_path": "/absolute/path/to/image.jpg",
  "model_path": "~/.cache/gemma-4-31b-dense-4bit-mlx"
}
```

**Output (read from stdout):**
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
  "safety_note": "string"
}
```

On malformed JSON: retry once, then return error JSON with `error: "malformed_output"`.

## Acceptance criteria

- [ ] Python subprocess starts and stays alive (reusable, not one-shot per call)
- [ ] Actor sends JSON input and receives JSON output
- [ ] Model path is configurable (code constants for v0.1)
- [ ] Timeout: 300 seconds max per call
- [ ] Crash handling: subprocess restarts on next call
- [ ] Entry updated: identification_json populated, model_confidence set, user_status set to unreviewed

## Blocked by

#5 (app shell must exist first)