#!/usr/bin/env python3
"""Long-lived Gemma 4 31B Dense service via mlx-vlm.

Receives JSON on stdin, sends JSON on stdout. Runs indefinitely until SIGTERM.
"""

import json
import os
import signal
import sys
from pathlib import Path

DEFAULT_MODEL_PATH = os.path.expanduser("~/.cache/gemma-4-31b-dense-4bit-mlx")
TIMEOUT_SECONDS = 300

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
FULL_PROMPT = f"{SYSTEM_PROMPT}\n\n{USER_PROMPT}"

_model_instance = None


def load_model(model_path: str):
    global _model_instance
    if _model_instance is not None:
        return _model_instance

    try:
        from mlx_vlm import MLXVLM
    except ImportError:
        raise RuntimeError("mlx-vlm not installed. Install with: pip install mlx-vlm")

    if not os.path.isdir(model_path):
        raise RuntimeError(f"Model directory not found: {model_path}")

    _model_instance = MLXVLM(model_path)
    return _model_instance


def parse_json_output(raw_output: str) -> dict:
    raw_output = raw_output.strip()

    if raw_output.startswith("```json"):
        lines = raw_output.split("\n")
        start = None
        end = None
        for i, line in enumerate(lines):
            if line.strip() == "```json":
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

    confidence = data["model_confidence"]
    if confidence not in ("high", "medium", "low"):
        raise ValueError(f"Invalid confidence value: {confidence}")

    top = data["top_candidate"]
    for field in ["common_name", "scientific_name", "family"]:
        if field not in top:
            raise ValueError(f"Missing required field in top_candidate: {field}")


def handle_identify(params: dict) -> dict:
    photo_path = params.get("photo_path")
    model_path = params.get("model_path", DEFAULT_MODEL_PATH)

    if not photo_path:
        return {"error": "photo_path is required"}

    photo = Path(photo_path)
    if not photo.exists():
        return {"error": f"Photo file not found: {photo_path}"}

    model = load_model(model_path)
    raw_output = model.generate(str(photo), FULL_PROMPT, timeout=TIMEOUT_SECONDS)
    data = parse_json_output(raw_output)
    validate_output(data)
    return data


def process_request(raw_request: str) -> dict:
    try:
        request = json.loads(raw_request.strip())
    except json.JSONDecodeError:
        return {"error": "malformed_output"}

    action = request.get("action")
    if action == "identify":
        return handle_identify(request)
    else:
        return {"error": f"Unknown action: {action}"}


def main():
    signal.signal(signal.SIGTERM, lambda *args: sys.exit(0))

    model_path = os.environ.get("GEMMA_MODEL_PATH", DEFAULT_MODEL_PATH)
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
