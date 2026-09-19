#!/usr/bin/env python3
"""Fail the build if our banner does not fit the window upstream sized for its own.

Upstream's floating terminal is sized for upstream's logo.txt, so ours may be no
wider, and ARCHY -- sliced from upstream -- must sit in upstream's own columns
(#764). Counted in characters: every block glyph is three bytes, so awk's
length() in the builder's C locale would read 87 columns as about 250.
"""

import sys

ours, theirs = (open(f, encoding="utf-8").read().split("\n") for f in sys.argv[1:3])
wide, fits = max(map(len, ours)), max(map(len, theirs))

fail = []
if wide > fits:
    fail.append(f"banner is {wide} columns; upstream's window fits {fits}")
if len(ours) != len(theirs):
    fail.append(f"banner is {len(ours)} lines; upstream's is {len(theirs)}")
else:
    # Column 28 onward is ARCHY in both, so it has to be upstream's, byte for byte.
    for n, (a, b) in enumerate(zip(ours, theirs), 1):
        if a[27:].rstrip() != b[27:].rstrip():
            fail.append(f"line {n}: columns 28 onward are not upstream's ARCHY")
            break

for f in fail:
    print(f"logo.txt: {f}", file=sys.stderr)
sys.exit(1 if fail else 0)
