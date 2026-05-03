#!/usr/bin/env python3
"""Long-lived Gemma 4 31B service via mlx-vlm.

Receives one JSON request per line on stdin, writes one JSON response per
line on stdout. Exits on EOF or SIGTERM.
"""

import json
import os
import signal
import sys
from pathlib import Path

DEFAULT_MODEL_PATH = os.path.expanduser("~/.cache/gemma-4-31b-dense-4bit-mlx")
DEFAULT_MAX_TOKENS = 2048

SYSTEM_PROMPT = """You are a natural-history identification assistant. Analyze the provided image and identify the subject.

Output ONLY valid JSON in this exact format, with no additional text:
{
  "kingdom": "plant | animal | fungus | other",
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

Rules for "kingdom":
- "plant" for any vascular or non-vascular plant.
- "animal" for any animal — mammal, bird, reptile, amphibian, fish, insect, mollusc, etc.
- "fungus" for mushrooms, brackets, lichens, and other fungi.
- "other" if the subject is not a living organism (a manufactured object, food, scenery without a clear subject). For "other" subjects, fill top_candidate.common_name with a brief description (e.g. "ham sandwich"); leave scientific_name and family as empty strings; set alternatives to [].

Populate visible_evidence with the diagnostic features visible in the image — leaf shape and venation for plants; plumage, pelage, or distinctive markings for animals; cap shape and gill arrangement for fungi; salient details for "other" subjects.

Tailor safety_note to the kingdom: warn against consumption for plants and fungi; warn against approaching or handling wildlife for animals; for "other" use a brief reference disclaimer."""

USER_PROMPT = "Identify the subject of this image. Provide your best assessment with supporting visual evidence."
FULL_PROMPT = f"{SYSTEM_PROMPT}\n\n{USER_PROMPT}"

_model = None
_processor = None
_config = None


def load_model(model_path: str):
    global _model, _processor, _config
    if _model is not None:
        return

    try:
        from mlx_vlm import load
        from mlx_vlm.utils import load_config
    except ImportError:
        raise RuntimeError("mlx-vlm not installed. Install with: pip install -U mlx-vlm")

    if not os.path.isdir(model_path):
        raise RuntimeError(f"Model directory not found: {model_path}")

    _model, _processor = load(model_path)
    _config = load_config(model_path)


def run_generation(photo_path: str) -> str:
    from mlx_vlm import generate
    from mlx_vlm.prompt_utils import apply_chat_template

    formatted = apply_chat_template(_processor, _config, FULL_PROMPT, num_images=1)
    result = generate(
        _model,
        _processor,
        formatted,
        image=[photo_path],
        max_tokens=DEFAULT_MAX_TOKENS,
        verbose=False,
    )
    # mlx-vlm returns either a str or a GenerationResult with .text
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


VALID_KINGDOMS = ("plant", "animal", "fungus", "other")


def validate_output(data: dict) -> None:
    required_fields = ["kingdom", "model_confidence", "top_candidate", "alternatives",
                       "visible_evidence", "missing_evidence", "safety_note"]
    for field in required_fields:
        if field not in data:
            raise ValueError(f"Missing required field: {field}")

    kingdom = (data.get("kingdom") or "").lower()
    if kingdom not in VALID_KINGDOMS:
        raise ValueError(f"Invalid kingdom: {data.get('kingdom')!r}")
    data["kingdom"] = kingdom

    if data["model_confidence"] not in ("high", "medium", "low"):
        raise ValueError(f"Invalid confidence value: {data['model_confidence']}")

    top = data["top_candidate"]
    for field in ["common_name", "scientific_name", "family"]:
        if field not in top:
            raise ValueError(f"Missing required field in top_candidate: {field}")


def handle_identify(params: dict) -> dict:
    photo_path = params.get("photo_path")
    if not photo_path:
        return {"error": "photo_path is required"}

    if not Path(photo_path).exists():
        return {"error": f"Photo file not found: {photo_path}"}

    try:
        raw_output = run_generation(photo_path)
        data = parse_json_output(raw_output)
        validate_output(data)
        return data
    except Exception as e:
        return {"error": str(e)}


def process_request(raw_request: str) -> dict:
    try:
        request = json.loads(raw_request.strip())
    except json.JSONDecodeError:
        return {"error": "malformed_request"}

    action = request.get("action")
    if action == "identify":
        return handle_identify(request)
    return {"error": f"Unknown action: {action}"}


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    model_path = os.environ.get("GEMMA_MODEL_PATH", DEFAULT_MODEL_PATH)
    try:
        load_model(model_path)
    except Exception as e:
        print(json.dumps({"error": f"Failed to load model: {e}"}), file=sys.stderr)
        sys.exit(1)

    for line in sys.stdin:
        if not line.strip():
            continue
        result = process_request(line)
        try:
            print(json.dumps(result), flush=True)
        except BrokenPipeError:
            sys.exit(0)


if __name__ == "__main__":
    main()
