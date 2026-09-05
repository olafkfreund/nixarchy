#!/usr/bin/env bash
# Does this GIF actually show what it claims to show?
#
# Written after docs/img/features/microvm-sandboxes.gif shipped with long
# stretches of bare wallpaper and not one frame of a running guest. Two
# checks, because the failure had two halves and neither check alone
# catches both:
#
#   * Diversity: sample N frames spread across the whole GIF and fail if
#     almost nothing changes between them. This catches the fully static
#     recording -- a wallpaper with a notification on it -- at zero cost.
#     Measured on the shipped GIFs before writing the thresholds: the
#     static-wallpaper one still had 5 of 11 sampled transitions above 2%
#     RMSE (notifications appearing), and the genuinely good
#     boxes-distrobox.gif had only 2 of 11 (a terminal holding still while
#     text accumulates). So diversity distinguishes "frozen" from "alive",
#     and nothing more -- which is why the second check exists.
#
#   * Content: OCR the sampled frames and require every --expect regex to
#     match somewhere in them. A microvm scene that never shows a guest
#     prompt fails here no matter how much its notifications wiggle. This
#     is the check that would have rejected the shipped GIF.
#
# The sampled frames are also left on disk (--dump), because the last line
# of defence is a human looking at them, and a tool that made that harder
# would be working against its own reason to exist.
set -euo pipefail

usage() {
  cat <<'EOF'
usage: verify-frames <gif> [options]
  --frames N        frames to sample across the GIF (default 12)
  --min-distinct N  sampled transitions that must differ by >2% RMSE
                    (default 2; a held-still terminal scene measures 2)
  --expect REGEX    OCR'd sample text must match (repeatable, extended
                    regex, case-insensitive)
  --max-bytes N     fail if the GIF is bigger than this (default: no limit)
  --dump DIR        keep the sampled PNGs here (default: a temp dir,
                    removed on success, kept and named on failure)
EOF
  exit 2
}

gif=""
frames=12
min_distinct=2
max_bytes=0
dump=""
expects=()
while [ $# -gt 0 ]; do
  case "$1" in
    --frames) frames="${2:?}"; shift 2 ;;
    --min-distinct) min_distinct="${2:?}"; shift 2 ;;
    --expect) expects+=("${2:?}"); shift 2 ;;
    --max-bytes) max_bytes="${2:?}"; shift 2 ;;
    --dump) dump="${2:?}"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "verify-frames: unknown option '$1'" >&2; usage ;;
    *) gif="$1"; shift ;;
  esac
done
[ -n "$gif" ] || usage
[ -r "$gif" ] || { echo "verify-frames: cannot read '$gif'" >&2; exit 1; }

cleanup=""
if [ -z "$dump" ]; then
  dump=$(mktemp -d verify-frames.XXXXXX)
  cleanup="$dump"
fi
mkdir -p "$dump"

fail=0

# ---- size ------------------------------------------------------------------
size=$(stat -c %s "$gif")
if [ "$max_bytes" -gt 0 ] && [ "$size" -gt "$max_bytes" ]; then
  echo "FAIL: $gif is $size bytes (limit $max_bytes)." >&2
  echo "  Do not degrade the encoding to squeeze it in -- cut the scene" >&2
  echo "  into two scenes instead." >&2
  fail=1
fi

# ---- sample ----------------------------------------------------------------
total=$(ffprobe -v error -select_streams v -count_frames \
  -show_entries stream=nb_read_frames -of csv=p=0 "$gif")
if [ -z "$total" ] || [ "$total" -lt 2 ]; then
  echo "FAIL: $gif decodes to ${total:-0} frames -- not a recording." >&2
  exit 1
fi
step=$(( (total - 1) / (frames - 1) ))
[ "$step" -lt 1 ] && step=1
ffmpeg -v error -i "$gif" -vf "select='not(mod(n\\,$step))'" \
  -fps_mode vfr -frames:v "$frames" "$dump/sample-%02d.png"
sampled=$(find "$dump" -name 'sample-*.png' | wc -l)
echo "sampled $sampled of $total frames (every ${step}th) into $dump"

# ---- diversity -------------------------------------------------------------
# `compare -metric RMSE` prints "absolute (fraction)" on stderr and exits
# non-zero for images that differ, so both the redirect and the `|| true`
# are load-bearing.
distinct=0
pairs=0
prev=""
for f in "$dump"/sample-*.png; do
  if [ -n "$prev" ]; then
    rmse=$(compare -metric RMSE "$prev" "$f" null: 2>&1 \
      | grep -oE '\(([0-9.e-]+)\)' | tr -d '()' || true)
    [ -n "$rmse" ] || rmse=0
    pairs=$((pairs + 1))
    if awk -v r="$rmse" 'BEGIN { exit !(r >= 0.02) }'; then
      distinct=$((distinct + 1))
    fi
    printf '  %s -> %s  RMSE %s\n' "$(basename "$prev")" "$(basename "$f")" "$rmse"
  fi
  prev="$f"
done
if [ "$distinct" -lt "$min_distinct" ]; then
  echo "FAIL: only $distinct of $pairs sampled transitions differ by >2% RMSE" >&2
  echo "  (needed $min_distinct). The recording is static or near-static --" >&2
  echo "  the screen never showed the thing changing." >&2
  fail=1
else
  echo "diversity: $distinct of $pairs sampled transitions differ (needed $min_distinct)"
fi

# ---- content ---------------------------------------------------------------
if [ "${#expects[@]}" -gt 0 ]; then
  text="$dump/ocr.txt"
  : > "$text"
  for f in "$dump"/sample-*.png; do
    tesseract "$f" - 2>/dev/null >> "$text" || true
  done
  for want in "${expects[@]}"; do
    if grep -qiE -- "$want" "$text"; then
      echo "content: found /$want/ in the sampled frames"
    else
      echo "FAIL: no sampled frame's OCR text matches /$want/." >&2
      echo "  Whatever this GIF shows, it is not the thing the scene claims." >&2
      echo "  Read $text and look at the PNGs in $dump." >&2
      fail=1
    fi
  done
fi

if [ "$fail" -ne 0 ]; then
  echo "verify-frames: $gif FAILED -- the sampled frames are in $dump" >&2
  exit 1
fi

echo "verify-frames: $gif looks like a real recording ($size bytes)"
if [ -n "$cleanup" ]; then rm -rf "$cleanup"; fi
