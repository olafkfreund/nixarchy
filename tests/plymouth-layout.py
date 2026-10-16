#!/usr/bin/env python3
"""Hold the boot splash script's layout structure (#1285).

A display can appear after plymouthd started, and the window then grows. Every
position therefore has to be re-runnable: it lives in layout(), which
refresh_callback() calls when the window size changes. A position statement
left at top level runs once and is never redone, and nothing else notices.
"""
import re
import sys

path = sys.argv[1]
failures = []

# The script has no '#', '{' or '}' inside a string or a // or /* */ comment;
# a future one would throw the brace count off, and this reads as if it had not.
lines = [re.sub(r"#.*", "", raw).rstrip() for raw in open(path).read().splitlines()]

depth = 0
func = None
func_lines = {}
layout_called_at = None
layout_defined_at = None
last_sprite_at = 0

for n, line in enumerate(lines, 1):
    start_depth = depth
    m = re.match(r"\s*fun\s+(\w+)\s*\(", line)
    if m and start_depth == 0:
        func = m.group(1)
        func_lines[func] = []
        if func == "layout":
            layout_defined_at = n
    if func is not None:
        func_lines[func].append(line)
    # Outside every function, not only outside every brace: a position inside a
    # top-level if/for runs once too.
    if func is None and not m:
        if re.search(r"=\s*Sprite\(", line):
            last_sprite_at = n
        if re.search(r"\.(SetX|SetY|SetPosition)\(", line):
            failures.append(
                f"(a) line {n}: position set at top level, never redone when the window grows: {line.strip()}"
            )
        if line.strip() == "layout();" and start_depth == 0:
            layout_called_at = n
    depth += line.count("{") - line.count("}")
    if depth == 0:
        func = None

if layout_defined_at is None:
    failures.append("(b) no `fun layout()` in the script")
if layout_called_at is None:
    failures.append("(b) `layout();` is never called at top level, so nothing is placed at start")
elif layout_defined_at is not None and (layout_called_at < layout_defined_at or layout_called_at < last_sprite_at):
    failures.append(
        f"(b) `layout();` at line {layout_called_at} runs before `fun layout()` or a sprite it places "
        f"(defined {layout_defined_at}, last sprite {last_sprite_at})"
    )

# layout() must record the size it laid out for, or the guard below is always
# true and layout() runs on every frame.
layout_body = "\n".join(func_lines.get("layout", []))
for need in ("global.layout_width = Window.GetWidth();", "global.layout_height = Window.GetHeight();"):
    if need not in layout_body:
        failures.append(f"(d) layout() does not record the size it laid out for: missing `{need}`")

body = "\n".join(func_lines.get("refresh_callback", []))
guard = re.search(r"if\s*\(([^{]*)\)\s*\{\s*layout\(\)\s*;", body)
if not guard:
    failures.append("(c) refresh_callback() has no `if (...) { layout(); }`")
else:
    # Exactly "the window differs from what was laid out", in either dimension:
    # an inverted or swapped comparison never re-lays out a late display.
    cond = re.sub(r"\s+", "", guard.group(1))
    want = "Window.GetWidth()!=global.layout_width||Window.GetHeight()!=global.layout_height"
    if cond != want:
        failures.append(f"(c) refresh_callback()'s layout guard is `{cond}`, not `{want}`")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("plymouth layout: positions are all in layout(), called once and on window change")
