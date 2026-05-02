#!/usr/bin/env python3
"""Test CLI for gemma_spike identify.py. Runs the script and pretty-prints output."""

import argparse
import json
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description="Run identify.py and display results")
    parser.add_argument("photo_path", help="Path to the photo file")
    parser.add_argument("--output", "-o", help="Path to save JSON output")
    args = parser.parse_args()

    result = subprocess.run(
        [sys.executable, "identify.py", args.photo_path],
        capture_output=True,
        text=True,
    )

    if result.stdout:
        try:
            data = json.loads(result.stdout)
            print(json.dumps(data, indent=2))
        except json.JSONDecodeError:
            print(result.stdout)

        if args.output:
            with open(args.output, "w") as f:
                f.write(result.stdout)
            print(f"\n[Saved to {args.output}]")

    if result.stderr:
        print("\n[STDERR]", file=sys.stderr)
        print(result.stderr, file=sys.stderr)

    sys.exit(result.returncode)


if __name__ == "__main__":
    main()
