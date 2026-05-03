#!/usr/bin/env python3
"""Long-lived FLUX.2-klein illustration service via mflux.

Receives one JSON request per line on stdin, writes one JSON response per
line on stdout. Exits on EOF or SIGTERM.

Weights are loaded from a local mflux save directory. Pre-quantize once with:
    mflux-save --model flux2-klein-4b --quantize 4 --path ~/.cache/flux2-klein-4b-mflux-4bit

Prompt templates and per-kingdom substitution live in Swift
(Sources/AI/IllustrationPrompts.swift). This script renders whatever
fully-formed prompt string Swift sends; it does no template lookup.
"""

import json
import os
import random
import signal
import sys
import time
from pathlib import Path

DEFAULT_MODEL_PATH = os.path.expanduser("~/.cache/flux2-klein-4b-mflux-4bit")
DEFAULT_MODEL_NAME = "flux2-klein-4b"
DEFAULT_HEIGHT = 1024
DEFAULT_WIDTH = 1024
DEFAULT_NUM_STEPS = 4
DEFAULT_GUIDANCE = 1.0  # required for distilled FLUX.2
DEFAULT_SCHEDULER = "flow_match_euler_discrete"

_flux = None
_image_util = None


def load_model():
    global _flux, _image_util
    if _flux is not None:
        return

    try:
        from mflux.models.common.config import ModelConfig
        from mflux.models.flux2.variants import Flux2Klein
        from mflux.utils.image_util import ImageUtil
    except ImportError:
        raise RuntimeError("mflux not installed. Install with: pip install mflux")

    model_path = os.environ.get("FLUX_MODEL_PATH", DEFAULT_MODEL_PATH)
    if not os.path.isdir(model_path):
        raise RuntimeError(f"Model directory not found: {model_path}")

    _flux = Flux2Klein(
        model_config=ModelConfig.from_name(model_name=DEFAULT_MODEL_NAME),
        model_path=model_path,
    )
    _image_util = ImageUtil


def handle_generate(params: dict) -> dict:
    prompt = params.get("prompt")
    output_path = params.get("output_path")
    height = int(params.get("height", DEFAULT_HEIGHT))
    width = int(params.get("width", DEFAULT_WIDTH))
    num_steps = int(params.get("num_steps", DEFAULT_NUM_STEPS))
    seed = params.get("seed")
    if seed is None:
        seed = random.randint(0, 2**32 - 1)
    seed = int(seed)

    if not output_path:
        return {"error": "output_path is required"}
    if not prompt:
        return {"error": "prompt is required"}

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    pre_existed = output.exists()
    pre_size = output.stat().st_size if pre_existed else -1
    print(f"[flux.py] generate output={output} pre_existed={pre_existed} pre_size={pre_size} seed={seed}", file=sys.stderr, flush=True)

    start = time.time()
    try:
        image = _flux.generate_image(
            seed=seed,
            prompt=prompt,
            width=width,
            height=height,
            guidance=DEFAULT_GUIDANCE,
            num_inference_steps=num_steps,
            scheduler=DEFAULT_SCHEDULER,
        )
        # Call GeneratedImage.save directly. ImageUtil.save_image would re-dispatch
        # to GeneratedImage.save with default overwrite=False, silently writing to a
        # numbered sibling (_1.png, _2.png, ...) instead of replacing the file.
        image.save(path=str(output), overwrite=True)
    except Exception as e:
        print(f"[flux.py] generation_failed: {e}", file=sys.stderr, flush=True)
        return {"error": f"generation_failed: {e}"}

    post_size = output.stat().st_size if output.exists() else -1
    print(f"[flux.py] wrote {output} post_size={post_size}", file=sys.stderr, flush=True)
    return {
        "illustration_path": str(output.resolve()),
        "seed": seed,
        "timing_seconds": round(time.time() - start, 2),
    }


def process_request(raw_request: str) -> dict:
    try:
        request = json.loads(raw_request.strip())
    except json.JSONDecodeError:
        return {"error": "malformed_request"}

    action = request.get("action")
    if action == "generate":
        return handle_generate(request)
    return {"error": f"Unknown action: {action}"}


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    try:
        load_model()
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
