#!/usr/bin/env python3
"""Long-lived FLUX schnell illustration service via MLX.

Receives JSON on stdin, sends JSON on stdout. Runs indefinitely until SIGTERM.
"""

import json
import os
import signal
import sys
import time
from pathlib import Path

DEFAULT_MODEL_PATH = os.path.expanduser("~/.cache/flux-schnell-mlx")
TIMEOUT_SECONDS = 300

_system_prompt = None
_model_instance = None


def load_model(model_path: str):
    global _model_instance
    if _model_instance is not None:
        return _model_instance

    try:
        from mlx_vlm import MLXImageGeneration
    except ImportError:
        raise RuntimeError("mlx-vlm not installed. Install with: pip install mlx-vlm")

    if not os.path.isdir(model_path):
        raise RuntimeError(f"Model directory not found: {model_path}")

    _model_instance = MLXImageGeneration(model_path, model_type="flux-schnell")
    return _model_instance


def build_prompt(identification_json_path: str) -> str:
    with open(identification_json_path, 'r') as f:
        data = json.load(f)

    scientific_name = data.get("top_candidate", {}).get("scientific_name", "")
    common_name = data.get("top_candidate", {}).get("common_name", "")

    visible_evidence = data.get("visible_evidence", [])
    subject_description = "; ".join(visible_evidence)

    if len(subject_description) < 20:
        subject_description = "a plant in the style of 19th century botanical illustration"

    template = (
        "A botanical illustration of {scientific_name}, {common_name}, "
        "in the style of 19th century natural history plates. "
        "{subject_description}. "
        "On plain neutral background. No text, no labels, no border."
    )

    prompt = template.format(
        scientific_name=scientific_name or "unknown species",
        common_name=common_name or "unknown common name",
        subject_description=subject_description
    )

    return prompt


def handle_generate(params: dict) -> dict:
    prompt = params.get("prompt")
    identification_json_path = params.get("identification_json_path")
    photo_path = params.get("photo_path")
    output_path = params.get("output_path")
    model_path = params.get("model_path", DEFAULT_MODEL_PATH)

    if not photo_path:
        return {"error": "photo_path is required"}
    if not output_path:
        return {"error": "output_path is required"}

    if not prompt:
        if identification_json_path:
            prompt = build_prompt(identification_json_path)
        else:
            return {"error": "Either prompt or identification_json_path is required"}

    photo = Path(photo_path)
    if not photo.exists():
        return {"error": f"Photo file not found: {photo_path}"}

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)

    model = load_model(model_path)

    start_time = time.time()

    try:
        result = model.generate(
            prompt,
            image_path=str(photo),
            output_path=str(output),
            timeout=TIMEOUT_SECONDS
        )
    except Exception as e:
        return {"error": f"generation_failed: {e}"}

    elapsed = time.time() - start_time

    seed = result.get("seed", 0) if isinstance(result, dict) else 0

    return {
        "imagePath": str(output.resolve()),
        "seed": seed,
        "timing_seconds": round(elapsed, 2)
    }


def process_request(raw_request: str) -> dict:
    try:
        request = json.loads(raw_request.strip())
    except json.JSONDecodeError:
        return {"error": "malformed_request"}

    action = request.get("action")
    if action == "generate":
        return handle_generate(request)
    else:
        return {"error": f"Unknown action: {action}"}


def main():
    signal.signal(signal.SIGTERM, lambda *args: sys.exit(0))

    model_path = os.environ.get("FLUX_MODEL_PATH", DEFAULT_MODEL_PATH)
    try:
        load_model(model_path)
    except Exception as e:
        print(json.dumps({"error": f"Failed to load model: {e}"}), file=sys.stderr)
        sys.exit(1)

    while True:
        try:
            line = sys.stdin.readline()
        except EOFError:
            break

        if not line:
            break

        result = process_request(line)
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()