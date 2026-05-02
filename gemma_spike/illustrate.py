#!/usr/bin/env python3
"""Phase 0.1b illustration spike: FLUX schnell quantised MLX."""

import argparse
import json
import os
import random
import signal
import sys
import time
from pathlib import Path

DEFAULT_FLUX_MODEL_PATH = os.path.expanduser("~/.cache/flux-schnell-mlx")
TIMEOUT_SECONDS = 300

FALLBACK_SUBJECT_DESCRIPTION = "a plant in the style of 19th century botanical illustration"


def build_flux_prompt(identification_data: dict) -> str:
    scientific_name = identification_data.get("top_candidate", {}).get("scientific_name", "unknown")
    common_name = identification_data.get("top_candidate", {}).get("common_name", "unknown")
    visible_evidence = identification_data.get("visible_evidence", [])

    subject_description = "; ".join(visible_evidence)
    if len(subject_description) < 20:
        subject_description = FALLBACK_SUBJECT_DESCRIPTION

    prompt = (
        f"A botanical illustration of {scientific_name}, {common_name}, "
        f"in the style of 19th century natural history plates. "
        f"{subject_description}. "
        f"On plain neutral background. No text, no labels, no border."
    )
    return prompt


def load_flux_mlx():
    try:
        from flux.aggregate import FluxImagePipeline
        return FluxImagePipeline
    except ImportError:
        return None


def generate_illustration(
    prompt: str,
    output_path: str,
    model_path: str,
    timeout: int = TIMEOUT_SECONDS,
) -> dict:
    FluxImagePipeline = load_flux_mlx()
    if FluxImagePipeline is None:
        raise RuntimeError("flux-mlx not installed. Install from: https://github.com/bghira/flux-schnell")

    if not os.path.isdir(model_path):
        raise RuntimeError(f"Model directory not found: {model_path}")

    seed = random.randint(0, 2**32 - 1)
    start_time = time.time()

    class TimeoutException(Exception):
        pass

    def timeout_handler(signum, frame):
        raise TimeoutException(f"Generation timed out after {timeout} seconds")

    old_handler = signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(timeout)

    try:
        pipeline = FluxImagePipeline(model_path)
        result = pipeline.generate(
            prompt,
            seed=seed,
            output_path=output_path,
            timeout=timeout,
        )
        elapsed = time.time() - start_time
        return {
            "illustration_path": output_path,
            "seed": seed,
            "timing_seconds": round(elapsed, 2),
        }
    except TimeoutException:
        return {"error": "generation_failed"}
    finally:
        signal.alarm(0)
        signal.signal(signal.SIGALRM, old_handler)


def main():
    parser = argparse.ArgumentParser(
        description="Generate botanical illustration via FLUX schnell MLX"
    )
    parser.add_argument("photo_path", help="Path to the source photo (for reference only)")
    parser.add_argument("identification_json_path", help="Path to Gemma JSON output")
    parser.add_argument("output_png_path", help="Path for output PNG")
    parser.add_argument(
        "--model-path",
        default=os.environ.get("FLUX_MODEL_PATH", DEFAULT_FLUX_MODEL_PATH),
        help="Path to FLUX model directory",
    )
    args = parser.parse_args()

    if not Path(args.identification_json_path).exists():
        print(json.dumps({"error": f"Identification JSON not found: {args.identification_json_path}"}), file=sys.stderr)
        sys.exit(1)

    try:
        with open(args.identification_json_path, "r") as f:
            identification_data = json.load(f)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON: {e}"}), file=sys.stderr)
        sys.exit(1)

    prompt = build_flux_prompt(identification_data)

    result = generate_illustration(
        prompt=prompt,
        output_path=args.output_png_path,
        model_path=args.model_path,
        timeout=TIMEOUT_SECONDS,
    )

    print(json.dumps(result))


if __name__ == "__main__":
    main()