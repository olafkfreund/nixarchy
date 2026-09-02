#!/usr/bin/env python3
"""Draw the five unbranded pieces of the boot splash: the progress track and
its bar, the passphrase field, the padlock beside it and the dot that stands
for one typed character.

The wordmark next to them is derived from Omarchy's logo.svg by
nixarchy-logo.py, because a wordmark has to keep matching upstream's pixel
grid after a bump. These five carry no mark -- they are shapes -- so there is
nothing to derive and they are drawn here instead, in the same Tokyo Night
palette the theme's background already uses.

Output is SVG, at the exact pixel size each asset is used at, and default.nix
rasterises it with the same magick call the wordmark goes through. The sizes
are not free: omarchy.script divides by 96 to scale the lock and centres the
bar inside the box by their height difference, so lock stays 84x96 and the bar
stays narrower than the box on purpose.

Everything is a filled path. No strokes and no masks -- a border is an
even-odd ring of two rounded rectangles -- so the result does not depend on
which SVG delegate ImageMagick was built with.
"""

import os
import sys

# Tokyo Night, the palette Window.SetBackground*Color already uses at 0x1a1b26.
FOREGROUND = "#c0caf5"  # text: the entry border, the lock, the bullet
TRACK = "#292e42"  # bg-highlight: the empty half of the progress bar
TRACK_EDGE = "#3b4261"  # one shade up, so the track has an edge on black
FIELD = "#16161e"  # darker than the background, so the field sits *in* it
FIELD_EDGE = "#565f89"  # comment: present without competing with the wordmark
ACCENT = "#a8cd76"  # the wordmark's own green -- see nixarchy-logo.py


def svg(width, height, body):
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" '
        f'viewBox="0 0 {width} {height}" width="{width}" height="{height}">'
        f"{body}</svg>"
    )


def rounded(x, y, w, h, r, clockwise=True):
    """One rounded-rectangle subpath, as arcs.

    `clockwise=False` reverses the winding, which is what makes an inner
    rectangle cut a hole out of an outer one under fill-rule="evenodd".
    """
    r = min(r, w / 2, h / 2)
    sweep = 1 if clockwise else 0
    if clockwise:
        pts = [
            f"M{x + r},{y}",
            f"H{x + w - r}",
            f"A{r},{r} 0 0 {sweep} {x + w},{y + r}",
            f"V{y + h - r}",
            f"A{r},{r} 0 0 {sweep} {x + w - r},{y + h}",
            f"H{x + r}",
            f"A{r},{r} 0 0 {sweep} {x},{y + h - r}",
            f"V{y + r}",
            f"A{r},{r} 0 0 {sweep} {x + r},{y}",
            "Z",
        ]
    else:
        pts = [
            f"M{x + r},{y}",
            f"A{r},{r} 0 0 {sweep} {x},{y + r}",
            f"V{y + h - r}",
            f"A{r},{r} 0 0 {sweep} {x + r},{y + h}",
            f"H{x + w - r}",
            f"A{r},{r} 0 0 {sweep} {x + w},{y + h - r}",
            f"V{y + r}",
            f"A{r},{r} 0 0 {sweep} {x + w - r},{y}",
            "Z",
        ]
    return "".join(pts)


def ring(x, y, w, h, r, thickness):
    """A rounded-rectangle border, as a filled even-odd path."""
    t = thickness
    return (
        rounded(x, y, w, h, r)
        + rounded(x + t, y + t, w - 2 * t, h - 2 * t, max(r - t, 0), clockwise=False)
    )


def progress_box():
    """The track, 300x10. Flat fill with an edge, so it reads as a container
    on a near-black background rather than as a smudge."""
    return svg(
        300,
        10,
        f'<path fill="{TRACK_EDGE}" fill-rule="evenodd" d="{ring(0, 0, 300, 10, 5, 1)}"/>'
        f'<path fill="{TRACK}" d="{rounded(1, 1, 298, 8, 4)}"/>',
    )


def progress_bar():
    """The fill, 296x6 -- four pixels narrower and four shorter than the
    track, which is what insets it.

    omarchy.script centres both sprites on the window, so a narrower bar is
    automatically two pixels in from each end of the track; and it centres the
    bar in the track by their height difference, so a shorter one is two
    pixels down. The green never touches the track's edge, at any progress.

    Nothing here may vary along x: the script scales this from one pixel wide
    up to full, so a rounded cap would stretch and a horizontal gradient would
    slide. A flat rectangle survives every width it is drawn at.
    """
    return svg(296, 6, f'<path fill="{ACCENT}" d="M0,0H296V6H0Z"/>')


def entry():
    """The passphrase field, 286x48. A recessed well: darker than the
    background it sits on, with a one-pixel border."""
    return svg(
        286,
        48,
        f'<path fill="{FIELD}" fill-opacity="0.72" d="{rounded(0, 0, 286, 48, 10)}"/>'
        f'<path fill="{FIELD_EDGE}" fill-rule="evenodd" d="{ring(0, 0, 286, 48, 10, 1)}"/>',
    )


def bullet():
    """One typed character, 14x14. Drawn at double the 7x7 omarchy.script
    scales it to, so the downscale is what softens the edge."""
    return svg(
        14,
        14,
        f'<circle cx="7" cy="7" r="6" fill="{FOREGROUND}"/>',
    )


def lock():
    """The padlock, 84x96 -- omarchy.script divides by exactly those to scale
    it against the entry field, so the size is fixed even though the drawing
    is not.

    One path, four subpaths, fill-rule="nonzero", and the winding of each is
    load-bearing: body and shackle are wound the same way so they union where
    they meet, and the shackle's opening and the keyhole are wound the other
    way so they punch real holes that the background shows through.

    Even-odd will not do here. Under it the shackle's foot and the top of the
    body cancel each other and the lock comes out with a notch bitten from
    each shoulder.
    """
    cx = 42.0
    top = 32.0  # centre of the shackle's arc
    outer, inner = 22.0, 11.5  # a 10.5px-thick shackle
    body_top, body_bottom = 44.0, 92.0
    foot = 47.0  # the shackle's legs stop just inside the body

    # Clockwise: an arch, filled solid.
    shackle = (
        f"M{cx - outer},{foot}"
        f"V{top}"
        f"A{outer},{outer} 0 0 1 {cx + outer},{top}"
        f"V{foot}"
        f"H{cx - outer}"
        "Z"
    )
    # Counter-clockwise, and stopping exactly at the body's top edge so it
    # never overlaps it: the gap under the arch.
    shackle_gap = (
        f"M{cx + inner},{body_top}"
        f"V{top}"
        f"A{inner},{inner} 0 0 0 {cx - inner},{top}"
        f"V{body_top}"
        "Z"
    )
    body = rounded(6, body_top, 72, body_bottom - body_top, 10)

    # Counter-clockwise as well: a round hole with a tapered slot below it.
    kx, ky, kr = 42.0, 64.0, 7.0
    keyhole = (
        f"M{kx},{ky - kr}"
        f"A{kr},{kr} 0 0 0 {kx - 3.0},{ky + kr - 1.5}"
        f"L{kx - 2.5},{ky + 16}"
        f"H{kx + 2.5}"
        f"L{kx + 3.0},{ky + kr - 1.5}"
        f"A{kr},{kr} 0 0 0 {kx},{ky - kr}"
        "Z"
    )

    return svg(
        84,
        96,
        f'<path fill="{FOREGROUND}" fill-rule="nonzero" '
        f'd="{shackle}{shackle_gap}{body}{keyhole}"/>',
    )


ASSETS = {
    "progress_box": progress_box,
    "progress_bar": progress_bar,
    "entry": entry,
    "bullet": bullet,
    "lock": lock,
}


def main(dest):
    os.makedirs(dest, exist_ok=True)
    for name, draw in ASSETS.items():
        path = f"{dest}/{name}.svg"
        with open(path, "w") as fh:
            fh.write(draw())
        print(f"wrote {path}")


if __name__ == "__main__":
    main(sys.argv[1])
