#!/usr/bin/env python3
"""Phase 0.1a identification spike: Gemma 4 31B via mlx-vlm."""

import argparse
import json
import os
import sys
from pathlib import Path

DEFAULT_MODEL_PATH = os.path.expanduser("~/.cache/gemma-4-31b-dense-4bit-mlx")
DEFAULT_MAX_TOKENS = 2048

SYSTEM_PROMPT = """You are a botanical identification assistant. Analyze the provided image and identify the plant.

Output ONLY valid JSON in this exact format, with no additional text:
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
}"""

USER_PROMPT = "Identify this plant. Provide your best assessment with supporting visual evidence."
PROMPT = f"{SYSTEM_PROMPT}\n\n{USER_PROMPT}"


def identify(photo_path: str, model_path: str) -> str:
    try:
        from mlx_vlm import load, generate
        from mlx_vlm.prompt_utils import apply_chat_template
        from mlx_vlm.utils import load_config
    except ImportError:
        raise RuntimeError("mlx-vlm not installed. Install with: pip install -U mlx-vlm")

    if not os.path.isdir(model_path):
        raise RuntimeError(f"Model directory not found: {model_path}")

    model, processor = load(model_path)
    config = load_config(model_path)
    formatted = apply_chat_template(processor, config, PROMPT, num_images=1)
    result = generate(
        model,
        processor,
        formatted,
        image=[photo_path],
        max_tokens=DEFAULT_MAX_TOKENS,
        verbose=False,
    )
    return getattr(result, "text", result)


def parse_json_output(raw_output: str) -> dict:
    raw_output = raw_output.strip()

    if raw_output.startswith("```"):
        lines = raw_output.split("\n")
        start = None
        end = None
        for i, line in enumerate(lines):
            if line.strip().startswith("```") and start is None:
                start = i + 1
            elif line.strip() == "```" and start is not None:
                end = i
                break
        if start is not None and end is not None:
            raw_output = "\n".join(lines[start:end])

    try:
        return json.loads(raw_output)
    except json.JSONDecodeError:
        try:
            start = raw_output.index("{")
            end = raw_output.rindex("}") + 1
            return json.loads(raw_output[start:end])
        except (ValueError, json.JSONDecodeError) as e:
            raise ValueError(f"Failed to parse JSON output: {e}")


def validate_output(data: dict) -> None:
    required_fields = ["model_confidence", "top_candidate", "alternatives",
                       "visible_evidence", "missing_evidence", "safety_note"]
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Missing required field: {field}")

    if data["model_confidence"] not in ("high", "medium", "low"):
        raise ValueError(f"Invalid confidence value: {data['model_confidence']}")

    top = data["top_candidate"]
    for field in ["common_name", "scientific_name", "family"]:
        if field not in top:
            raise ValueError(f"Missing required field in top_candidate: {field}")


def main():
    parser = argparse.ArgumentParser(description="Identify plants using Gemma 4 31B via mlx-vlm")
    parser.add_argument("photo_path", help="Path to the photo file")
    parser.add_argument(
        "--model-path",
        default=os.environ.get("GEMMA_MODEL_PATH", DEFAULT_MODEL_PATH),
        help="Path to the model directory",
    )
    args = parser.parse_args()

    photo_path = Path(args.photo_path)
    if not photo_path.exists():
        print(json.dumps({"error": f"Photo file not found: {args.photo_path}"}), file=sys.stderr)
        sys.exit(1)

    try:
        raw_output = identify(str(photo_path), args.model_path)
        data = parse_json_output(raw_output)
        validate_output(data)
        print(json.dumps(data, indent=2))
    except Exception as e:
        print(json.dumps({"error": str(e)}), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
