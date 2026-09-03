#!/usr/bin/env python3
"""Turn a ttfx animation into the still frames the boot splash plays.

Plymouth has no terminal. ttfx writes ANSI to one, so it cannot run at boot --
the animation has to be rendered before it, at build time, and shipped as
images the theme script steps through.

`ttfx --parity-dump` is what makes that possible. It is ttfx's own parity
harness output: instead of pacing frames against the clock and painting them
with cursor moves, it drives the engine on a virtual clock and writes every
frame whole, as

    <decimal byte length>\\n<that many bytes of canvas>\\n

With --no-color the canvas is plain text, one line per row, so a frame needs no
terminal emulation to render -- ImageMagick can set it as a label. And the
virtual clock is what makes the build reproducible: the same seed gives the
same frames on a fast machine and a slow one.

Frames are kept one in every STEP, because 128 of them is more animation than a
boot has time for and more images than the initrd wants to carry. The theme
script plays what is kept at a matching rate; the two numbers are related and
neither is free to change alone.

Usage: nixarchy-plymouth-frames.py <dump-file> <output-dir>
Prints the number of frames written, which is what the theme script must
declare as global.frame_count.
"""

import sys
from pathlib import Path

STEP = 4


def frames(dump: bytes):
    """Split the dump on its length headers.

    By length, never by counting lines: a canvas row is allowed to be empty and
    a frame is allowed to end on one, so line counting drifts on exactly the
    frames where the animation has not filled the canvas yet.
    """
    at = 0
    while at < len(dump):
        end = dump.index(b"\n", at)
        size = int(dump[at:end])
        start = end + 1
        yield dump[start : start + size]
        # +1 for the newline ttfx writes after the frame body.
        at = start + size + 1


def main(argv):
    if len(argv) != 3:
        sys.exit(f"usage: {argv[0]} <dump-file> <output-dir>")

    dump = Path(argv[1]).read_bytes()
    out = Path(argv[2])
    out.mkdir(parents=True, exist_ok=True)

    all_frames = list(frames(dump))
    if not all_frames:
        sys.exit("no frames in the dump -- did ttfx write anything?")

    # The last frame is kept whether or not the step lands on it. It is the one
    # the animation settles into and the one the splash holds while the rest of
    # boot happens, so dropping it would end the wordmark one step short of
    # finished.
    keep = list(range(0, len(all_frames), STEP))
    if keep[-1] != len(all_frames) - 1:
        keep.append(len(all_frames) - 1)

    for kept, index in enumerate(keep):
        # Unpadded, because the theme script builds these names by
        # concatenating an integer: "frame-" + i + ".txt". frame-08 would be
        # asking the script to zero-pad, which its expression language has no
        # way to do.
        (out / f"frame-{kept}.txt").write_bytes(all_frames[index])

    print(len(keep))


if __name__ == "__main__":
    main(sys.argv)
