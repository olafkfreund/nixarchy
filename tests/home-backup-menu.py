"""The two home-backup menu rows, checked against the generated extension.

The rows are the only way most people will ever reach nixarchy-home-backup,
and three separate things can silently break one: the generator drops a row
whose id upstream does not ship, the action can name a command that no longer
exists, and the `when` can drift away from the script's own ownership gate --
which leaves a row that appears on a machine where clicking it prints a
refusal. None of the three fails a build on its own.
"""

import json
import re
import sys

raw = open(sys.argv[1]).read()
# The same two transformations MenuModel.js applies to the JSONC.
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
menu = json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))

GATE = "nixarchy-home-backup --check"

for row_id, want_action in (
    ("trigger.home-backup", "nixarchy-home-backup"),
    ("trigger.home-backup.restore", "nixarchy-home-backup restore"),
):
    row = menu.get(row_id)
    if row is None:
        sys.exit(f"no {row_id} row: the backup is reachable only by typing its name")
    if not row.get("action", "").endswith(want_action):
        sys.exit(f"{row_id} does not run {want_action!r}: {row.get('action')!r}")
    if row.get("when") != GATE:
        sys.exit(
            f"{row_id} is not gated on the ownership marker (when={row.get('when')!r}). "
            "It would be offered on a machine where the command refuses."
        )
    # MenuModel.js falls back to the raw id for a missing label and to "" for
    # everything else, so an omitted key renders as "trigger.home-backup"
    # rather than inheriting anything.
    for key in ("label", "icon", "description"):
        if not row.get(key):
            sys.exit(f"{row_id} has no {key}; the menu renders the raw id")

print("both home-backup menu rows are present, gated and labelled")
