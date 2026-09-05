#!/usr/bin/env bash
# Frames in, README-sized GIF out. One place, because two scenes are encoded
# outside the Nix sandbox (they need a network in the VM) and an encode that
# drifted between the sandboxed and unsandboxed paths would let a GIF pass a
# gate its sibling was never held to.
set -euo pipefail

frames="${1:?usage: encode-gif <frames-dir> <out.gif>}"
out="${2:?usage: encode-gif <frames-dir> <out.gif>}"

# 4fps: each step was held for several frames by shot(), so this dwells
# about a second and a half per state -- long enough to read, short enough
# to sit through. 900px wide is what the README's existing good recording
# uses; palette per GIF or the file is tens of megabytes.
# [0-9]*.png, not *.png: the prelude's diagnostic greeter-probe.png sorts
# after the digits and would otherwise play as the GIF's final frame.
ffmpeg -hide_banner -loglevel error \
  -framerate 4 -pattern_type glob -i "$frames/[0-9]*.png" \
  -vf "fps=4,scale=900:-1:flags=lanczos,split[a][b];\
[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer" \
  "$out"
