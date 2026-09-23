#!/usr/bin/env bash
# Does this recording show what the shot list said it would? (#930)
#
# tests/demo/verify-frames.sh is the GIF gate and stays exactly as it is. This
# is its video sibling, and it is a different mechanism for the same intent,
# because carrying the GIF one over would have been a check that cannot fail:
#
#   * its DIVERSITY half measures RMSE between consecutive samples and fails
#     when almost nothing changes. Its own header says that only distinguishes
#     "frozen" from "alive", and its 2% threshold was measured on 4 fps GIFs
#     where a good recording scored 2 of 11 transitions above it. At 60 fps
#     nearly every frame differs slightly from its neighbour, so a video passes
#     that trivially -- including one where the shot list never got past beat
#     two. Carrying it over would be CLAUDE.md section 1's green light.
#
#   * its CONTENT half is medium-agnostic and is the half that caught the
#     incident the gate was written for. That idea survives here, with two
#     changes that make it strictly stronger.
#
# What is stronger about beat verification:
#
#   1. OCR is partitioned PER BEAT. verify-frames.sh concatenates every sample
#      into one ocr.txt and greps each --expect against the whole of it, so an
#      expectation proves the text appeared SOMEWHERE. Here each beat gets its
#      own text and can only be satisfied within its own window -- a beat that
#      never happened cannot borrow another beat's words.
#
#   2. It runs on the RAW master and refuses anything carrying a subtitle or a
#      second video stream. Run after editing, the drawtext caption that says
#      "Plugin Browser" would satisfy the expectation that the Plugin Browser
#      opened. The check would be verifying its own subtitles.
#
# Sampling uses a WINDOW, not a point. A single frame at the beat's timestamp
# fails on compositor lag, window-open animation and frame jitter -- both
# independent reviews of the spec raised that -- so N frames are taken across
# [at + settle, at + hold] and one solid hit is enough.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: verify-beats <master> <beats.json> <shots.usv> [options]
  --settle SEC     skip this much of each beat before sampling (default 0.6)
  --samples N      frames to sample within each beat window (default 3)
  --dump DIR       keep the sampled frames and per-beat OCR text
  --allow-edited   do not refuse a file with subtitles (for debugging only)

Exits non-zero naming the first beat whose expectation was not readable.
EOF
}

master=${1:-}
beatsjson=${2:-}
shotstsv=${3:-}
[ -n "$master" ] && [ -n "$beatsjson" ] && [ -n "$shotstsv" ] || {
  usage >&2
  exit 2
}
shift 3

settle=0.6
samples=3
dump=""
allow_edited=0
while [ $# -gt 0 ]; do
  case "$1" in
    --settle) settle=$2; shift 2 ;;
    --samples) samples=$2; shift 2 ;;
    --dump) dump=$2; shift 2 ;;
    --allow-edited) allow_edited=1; shift ;;
    *) echo "verify-beats: unknown option $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -f "$master" ] || { echo "verify-beats: no such recording: $master" >&2; exit 1; }
[ -f "$beatsjson" ] || { echo "verify-beats: no beats.json: $beatsjson" >&2; exit 1; }

# ---- refuse an edited cut ---------------------------------------------------
# The whole point of running on the raw master. A caption track or a second
# video stream means captions are burned in or carried, and then the gate would
# be reading its own subtitles back.
streams=$(ffprobe -v error -select_streams v -show_entries stream=index -of csv=p=0 "$master" | grep -c . || true)
subs=$(ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$master" | grep -c . || true)
if [ "$allow_edited" = 0 ] && { [ "$streams" -gt 1 ] || [ "$subs" -gt 0 ]; }; then
  echo "verify-beats: this looks like an EDITED cut ($streams video, $subs subtitle streams)." >&2
  echo "The gate runs on the raw master, or a caption satisfies the expectation it captions." >&2
  exit 1
fi

duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$master")
echo "verify-beats: $master, ${duration}s, $streams video stream(s)"

work=${dump:-$(mktemp -d)}
mkdir -p "$work"

fails=0
checked=0

# The shot list carries `expect` per beat; beats.json carries the observed time
# and the hold. Joined on the label, so a beat renamed in one and not the other
# is a missing join rather than a silent pass.
# \037, not tab: tab is whitespace and bash collapses runs of it, so a beat
# with an empty `expect` shifted its hold into that field and the gate
# reported 'nothing matching /3/'. Found by running this against a
# synthetic recording before trusting it.
while IFS=$'\t' read -r label expect hold; do
  [ -n "$label" ] || continue
  # A beat with no expectation is a deliberate breath (the desktop, the end
  # card). Counted, so "checked" cannot quietly be zero.
  checked=$((checked + 1))
  # "-" is the shot list's placeholder for an absent field. Tab is whitespace
  # and bash collapses runs of it, so an empty field would shift every later
  # one left -- the hold landed in expect and the gate reported "nothing
  # matching /3/". A placeholder cannot collapse.
  [ "$expect" != "-" ] || expect=""
  [ -n "$expect" ] && [ "$expect" != "null" ] || { echo "  --      $label (no expectation)"; continue; }

  at=$(jq -r --arg l "$label" '.beats[] | select(.label == $l) | .at' "$beatsjson")
  if [ -z "$at" ] || [ "$at" = "null" ]; then
    echo "  FAILED  $label: not in beats.json -- the take never reached this beat" >&2
    fails=$((fails + 1))
    continue
  fi

  text="$work/$label.txt"
  : > "$text"
  # N samples across [at+settle, at+hold], so animation and lag shift the hit
  # rather than losing it.
  for i in $(seq 1 "$samples"); do
    off=$(awk -v a="$at" -v s="$settle" -v h="$hold" -v i="$i" -v n="$samples" \
      'BEGIN { span = h - s; if (span < 0) span = 0; printf "%.2f", a + s + span * (i - 1) / (n > 1 ? n - 1 : 1) }')
    # A sample past the end of the recording produces no frame. That must skip
    # this sample, never abort the run: under errexit a failed `cp` fallback
    # killed the whole gate and reported nothing about any beat.
    awk -v o="$off" -v d="$duration" 'BEGIN { exit !(o < d) }' || continue

    png="$work/$label-$i.png"
    # -nostdin, and it is load-bearing. ffmpeg reads standard input, and this
    # runs inside a `while read` loop whose standard input is the shot list --
    # so without it ffmpeg eats bytes from the file the loop is iterating.
    # The symptom is not an error: labels come back with their leading
    # characters missing (`theme` as `heme`, `montage-gitlab` as
    # `ontage-gitlab`), which then fail the join and read as beats the take
    # never reached. It survived every run until a 23rd beat moved the byte
    # offsets, and the run before that had reported "all 22 beats" (#930).
    ffmpeg -nostdin -v error -ss "$off" -i "$master" -frames:v 1 -y "$png" 2>/dev/null || continue
    [ -s "$png" ] || continue

    # Upscaled before OCR for the reason verify-frames.sh gives: at video size
    # the terminal font is small enough that tesseract reads it as noise, and
    # the same frame doubled reads clean.
    if ! magick "$png" -resize 200% "$png.big.png" 2>/dev/null; then
      cp "$png" "$png.big.png" || continue
    fi
    tesseract "$png.big.png" - 2>/dev/null >> "$text" || true
  done

  if grep -qiE -- "$expect" "$text"; then
    echo "  ok      $label"
  else
    echo "  FAILED  $label: nothing matching /$expect/ at ${at}s (+${settle}..${hold}s)" >&2
    fails=$((fails + 1))
  fi
done < "$shotstsv"

# A loop that read nothing satisfies every case in silence -- tests/AGENTS.md
# says so about exactly this shape. A floor is the only thing that catches it.
if [ "$checked" -lt 5 ]; then
  echo "verify-beats: only $checked beats were checked -- the join produced almost nothing; refusing" >&2
  exit 1
fi

[ -n "$dump" ] && echo "verify-beats: frames and per-beat OCR in $work"
if [ "$fails" -gt 0 ]; then
  echo "verify-beats: $fails of $checked beats did not show what the shot list promised" >&2
  exit 1
fi
echo "verify-beats: all $checked beats show what the shot list promised"
