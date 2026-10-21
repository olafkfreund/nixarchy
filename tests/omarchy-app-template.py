#!/usr/bin/env python3
"""Write the omarchy-app skill's templates.md out as a project (#1406).

Each `## ` heading names one or two files in backticks; the fenced blocks under
it are those files, in order. Prose between blocks is skipped. A heading naming
a file that cannot exist (`<code>.json`) is expanded by the table below.
"""
import re
import sys
from pathlib import Path

src, out, name = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
text = Path(src).read_text()
# The catalogues the template's resources.qrc lists.
expand = {"src/i18n/<code>.json": ["src/i18n/en.json", "src/i18n/da.json"]}
skip = {"bin/build", "bin/test", ".gitignore", "flake.nix"}  # not part of the build

written = []
for section in re.split(r"(?m)^## ", text)[1:]:
    head, _, body = section.partition("\n")
    paths = re.findall(r"`([^`]+)`", head)
    blocks = re.findall(r"(?ms)^```[a-z]*\n(.*?)^```$", body)
    if not paths or not blocks:
        sys.exit(f"heading {head!r} has no path or no block")
    if len(paths) != len(blocks) and paths[0] not in expand:
        sys.exit(f"heading {head!r}: {len(paths)} paths, {len(blocks)} blocks")
    for p in paths:
        if p in skip:
            continue
        for q in expand.get(p, [p]):
            q = q.replace("<name>", name)
            dest = out / q
            dest.parent.mkdir(parents=True, exist_ok=True)
            body_text = blocks[paths.index(p)] if p not in expand else blocks[0]
            dest.write_text(
                body_text.replace("<name>", name).replace("<Name>", name.capitalize())
            )
            written.append(q)

need = {f"{name}.pro", "package.nix", f"dist/{name}.desktop", f"dist/{name}.svg",
        "src/main.cpp", "src/resources.qrc", "src/Main.qml"}
missing = need - set(written)
if missing:
    sys.exit(f"templates.md no longer yields: {sorted(missing)}")
