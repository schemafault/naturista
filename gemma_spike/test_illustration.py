#!/usr/bin/env python3
"""Test script for illustration spike."""
import sys

if len(sys.argv) < 4:
    print("Usage: python test_illustration.py /path/to/photo.jpg /path/to/identification.json /path/to/output.png")
    sys.exit(1)

from illustrate import main

sys.argv = ["illustrate.py"] + sys.argv[1:]
main()