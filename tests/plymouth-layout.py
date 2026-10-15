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

# The script has no '#' inside a string, so a comment is '#' to end of line.
lines = [re.sub(r"#.*", "", raw).rstrip() for raw in open(path).read().splitlines()]

depth = 0
func = None
func_lines = {}
layout_called_at_top = False
layout_defined = False

for n, line in enumerate(lines, 1):
    start_depth = depth
    m = re.match(r"\s*fun\s+(\w+)\s*\(", line)
    if m and start_depth == 0:
        func = m.group(1)
        func_lines[func] = []
        if func == "layout":
            layout_defined = True
    if func is not None:
        func_lines[func].append(line)
    if start_depth == 0 and not m:
        if re.search(r"\.(SetX|SetY|SetPosition)\(", line):
            failures.append(
                f"(a) line {n}: position set at top level, never redone when the window grows: {line.strip()}"
            )
        if line.strip() == "layout();":
            layout_called_at_top = True
    depth += line.count("{") - line.count("}")
    if depth == 0:
        func = None

if not layout_defined:
    failures.append("(b) no `fun layout()` in the script")
if not layout_called_at_top:
    failures.append("(b) `layout();` is never called at top level, so nothing is placed at start")

body = "\n".join(func_lines.get("refresh_callback", []))
guard = re.search(r"if\s*\(([^{]*)\)\s*\{\s*layout\(\)\s*;", body)
if not guard:
    failures.append("(c) refresh_callback() has no `if (...) { layout(); }`")
else:
    cond = guard.group(1)
    for need in (
        "Window.GetWidth()",
        "Window.GetHeight()",
        "global.layout_width",
        "global.layout_height",
    ):
        if need not in cond:
            failures.append(f"(c) refresh_callback()'s layout guard does not compare {need}: if ({cond.strip()})")

if failures:
    print("\n".join(failures))
    sys.exit(1)
print("plymouth layout: positions are all in layout(), called once and on window change")
