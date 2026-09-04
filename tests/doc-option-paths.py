"""Every `programs.nixarchy.*` path our prose quotes, checked against the real
option set.

Argument 1 is a JSON file written by tests/doc-options.nix: {"options": [...],
"groups": [...]}. The rest are documents to scan, or directories to walk for
them -- prose is the .md and .html; the rest of docs/ is screenshots, and a
JPEG read as text is a crash rather than a finding.

The distinction between the two lists is the whole check. A leaf option may be
freeform -- `apps.firefox.settings` takes any attribute at all -- so anything
below a leaf is accepted without pretending to know what nixpkgs allows there.
A group is just the attrset the module system builds on the way to the leaves,
and accepting anything below one would accept
`programs.nixarchy.apps.tailscale.settings.useRoutingFeatures`, which is the
sentence that made this file exist.
"""

import json
import pathlib
import re
import sys

# Deliberately anchored on our own prefix. Prose quotes plenty of option paths
# that are NixOS' rather than ours -- `services.tailscale.useRoutingFeatures`
# is a real thing to write and no list here can say whether it exists.
PATH = re.compile(r"programs\.nixarchy(?:\.[A-Za-z0-9_-]+)*")

known = json.load(open(sys.argv[1]))
options, groups = set(known["options"]), set(known["groups"])

documents = []
for arg in sys.argv[2:]:
    path = pathlib.Path(arg)
    if path.is_dir():
        documents += sorted(p for p in path.rglob("*") if p.suffix in (".md", ".html"))
    else:
        documents.append(path)

found, bad = 0, []
for doc in documents:
    for line_no, line in enumerate(doc.open(), 1):
        for path in PATH.findall(line):
            found += 1
            if path in options or path in groups:
                continue
            if any(path.startswith(opt + ".") for opt in options):
                continue
            bad.append((doc, line_no, path))

# A regex that has stopped matching passes silently, and a check that passes
# silently is the failure mode this whole file is arguing against.
if found == 0:
    sys.exit("no `programs.nixarchy.*` path found in any document: the scan "
             "matched nothing, which is a broken scan rather than clean prose")

for doc, line_no, path in bad:
    print(f"{doc}:{line_no}: {path} is not an option", file=sys.stderr)
if bad:
    sys.exit(f"{len(bad)} option path(s) quoted in prose do not exist")

print(f"{found} `programs.nixarchy.*` paths quoted in prose, all of them real")
