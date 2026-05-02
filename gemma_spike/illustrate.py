#!/usr/bin/env python3
"""Phase 0.1b illustration spike: FLUX.1-schnell via DiffusionKit MLX."""

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path

DEFAULT_MODEL_VERSION = "argmaxinc/mlx-FLUX.1-schnell-4bit-quantized"
DEFAULT_HEIGHT = 1024
DEFAULT_WIDTH = 1024
DEFAULT_NUM_STEPS = 4
DEFAULT_CFG_WEIGHT = 0.0
FALLBACK_SUBJECT = "a plant in the style of 19th century botanical illustration"


def build_prompt(identification_data: dict) -> str:
    top = identification_data.get("top_candidate", {})
    scientific_name = top.get("scientific_name") or "unknown species"
    common_name = top.get("common_name") or "unknown common name"

    visible = identification_data.get("visible_evidence", [])
    subject = "; ".join(visible)
    if len(subject) < 20:
        subject = FALLBACK_SUBJECT

    return (
        f"A botanical illustration of {scientific_name}, {common_name}, "
        f"in the style of 19th century natural history plates. "
        f"{subject}. "
        f"On plain neutral background. No text, no labels, no border."
    )


def generate_illustration(prompt: str, output_path: str, model_version: str, seed: int) -> dict:
    try:
        from diffusionkit.mlx import FluxPipeline
    except ImportError:
        raise RuntimeError("diffusionkit not installed. Install with: pip install diffusionkit")

    pipeline = FluxPipeline(
        shift=1.0,
        model_version=model_version,
        low_memory_mode=True,
        a16=True,
        w16=True,
    )

    start = time.time()
    image, _ = pipeline.generate_image(
        prompt,
        cfg_weight=DEFAULT_CFG_WEIGHT,
        num_steps=DEFAULT_NUM_STEPS,
        seed=seed,
        latent_size=(DEFAULT_HEIGHT // 8, DEFAULT_WIDTH // 8),
    )
    image.save(output_path)

    return {
        "illustration_path": output_path,
        "seed": seed,
        "timing_seconds": round(time.time() - start, 2),
    }


def main():
    parser = argparse.ArgumentParser(description="Generate botanical illustration via FLUX.1-schnell")
    parser.add_argument("photo_path", help="Path to the source photo (for reference only — unused)")
    parser.add_argument("identification_json_path", help="Path to Gemma JSON output")
    parser.add_argument("output_png_path", help="Path for output PNG")
    parser.add_argument(
        "--model-version",
        default=os.environ.get("FLUX_MODEL_VERSION", DEFAULT_MODEL_VERSION),
        help="Hugging Face repo for the FLUX MLX weights",
    )
    args = parser.parse_args()

    if not Path(args.identification_json_path).exists():
        print(json.dumps({"error": f"Identification JSON not found: {args.identification_json_path}"}), file=sys.stderr)
        sys.exit(1)

    try:
        with open(args.identification_json_path) as f:
            identification_data = json.load(f)
    except json.JSONDecodeError as e:
        print(json.dumps({"error": f"Invalid JSON: {e}"}), file=sys.stderr)
        sys.exit(1)

    prompt = build_prompt(identification_data)
    seed = random.randint(0, 2**32 - 1)

    output = Path(args.output_png_path)
    output.parent.mkdir(parents=True, exist_ok=True)

    try:
        result = generate_illustration(prompt, str(output), args.model_version, seed)
    except Exception as e:
        print(json.dumps({"error": f"generation_failed: {e}"}), file=sys.stderr)
        sys.exit(1)

    print(json.dumps(result))


if __name__ == "__main__":
    main()
