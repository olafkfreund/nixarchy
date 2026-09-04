"""Every Install row upstream offers, against what the selection covers.

Run from tests/options.nix. A row added by an Omarchy bump cannot then go
unmapped without someone deciding it should -- and a row upstream *removes*
shows up too, so the exception list cannot rot into a list of things that no
longer exist.

The exceptions are named rather than counted. "How many are unmapped" is a
number that drifts quietly; "which ones, and why" is a decision.
"""

import json
import os
import re
import sys

raw = open(os.environ["menuFile"]).read()
# The two transformations MenuModel.js applies.
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
raw = re.sub(r",(\s*[}\]])", r"\1", raw)

rows = {
    k
    for k, v in json.loads(raw).items()
    if k.startswith("install.") and "action" in v
}
known = set(os.environ["mapped"].split()) | set(os.environ["notApps"].split())

unmapped = sorted(rows - known)
stale = sorted(known - rows)

if unmapped:
    sys.exit(
        "these Install rows are neither in data/apps.nix nor listed as "
        "actions:\n  " + " ".join(unmapped)
        + "\nMap them, or say in tests/options.nix why they are not apps."
    )
if stale:
    sys.exit(
        "these are mapped or excused but no longer exist upstream:\n  "
        + " ".join(stale)
        + "\nAn Omarchy bump removed them; drop them here too."
    )
print(f"all {len(rows)} Install rows are mapped or accounted for")

# ---- every command a menu row names must exist ---------------------------
# A row whose command is gone renders normally and does nothing when chosen,
# which is the quietest way for an Omarchy bump to break the desktop.
#
# Both prefixes, and the merged menu rather than the package's own, because
# together those two narrownesses left every row nixarchy writes unchecked.
#
# The pattern was `\bomarchy-`, so `nixarchy-apply`, `nixarchy-search`,
# `nixarchy-app-enable`, `nixarchy-app-disable`, `nixarchy-app-remove` and
# `nixarchy-service-enable` were invisible to it -- our commands, the ones
# with no upstream keeping their names still, the ones a refactor here renames
# in a single commit. And the file it read was the package's menu, which is
# upstream's plus the Ask rows; the rows those commands appear in are written
# by modules/apps.nix into the merged defaults ($treeMenu) that OMARCHY_PATH
# points at, so even a widened pattern aimed at the old file would have found
# nothing to check. Between them: 75 rows -- every Install and Remove row for
# an app, every service row, Apply changes, Search -- named a command no check
# had ever confirmed exists. Renaming one of those writeShellApplications and
# missing its menu row cost nothing at build time and produced a row that
# still drew, still highlighted, and did nothing when chosen.
#
# `have` is two places for the same reason the names are two families:
# Omarchy's scripts are files in the tree's bin/, ours are packages on the
# reference machine's system PATH.
#
# Two shapes are excluded because they are not invocations. `when:` guards can
# name an *Arch package* -- install.editor.emacs tests
# `omarchy-pkg-present omarchy-emacs`, which is a package, not a command. And
# remove.webapp greps Exec= lines for `omarchy-webapp-handler`, which is a
# pattern. Both were flagged the first time this ran, and both are fine.
tree_raw = open(os.environ["treeMenu"]).read()
tree_raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", tree_raw, flags=re.M)
tree_raw = re.sub(r",(\s*[}\]])", r"\1", tree_raw)
menu = json.loads(tree_raw)
have = set(os.listdir(os.path.join(os.environ["omarchyPath"], "bin")))
have |= set(os.listdir(os.path.join(os.environ["vm"], "sw", "bin")))
not_invocations = {"omarchy-emacs", "omarchy-webapp-handler"}

missing = {}
for key, row in menu.items():
    for field in ("action", "when", "disabled", "checked"):
        for cmd in set(re.findall(r"\b(?:omarchy|nixarchy)-[a-z0-9-]+", str(row.get(field, "")))):
            if cmd not in have and cmd not in not_invocations:
                missing.setdefault(cmd, []).append(key)

if missing:
    sys.exit(
        "these menu rows name a command that does not exist:\n  "
        + "\n  ".join(f"{c} <- {' '.join(sorted(k))}" for c, k in sorted(missing.items()))
        + "\nAn Omarchy bump removed or renamed it, or a rename here did; the "
        "rows still draw and do nothing when chosen."
    )
print(f"all {len(menu)} menu rows name commands that exist")

