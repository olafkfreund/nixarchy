"""Every generated menu row is reachable by browsing, and every shared alias
summons the row it was meant to (#1302).

Applies MenuModel.js's rules (normalizeItem, resolveRoute) and Menu.qml's
browse rule (a screen lists rows whose parent is its id; a menu row opens its
id, a link row opens its target) to the generated defaults file. `when` and
`disabled` are runtime visibility and are deliberately ignored.
"""

import json
import re
import sys

# alias -> the row `omarchy menu summon <alias>` must open. An alias two rows
# declare, or one an exact id (or go/menu) takes first, must be listed here.
EXPECTED = {
    "ai": "trigger.ask",
    "app": "apps",
    "ask": "trigger.ask.anything",
    "connect": "setup.remote.gliff",
    "gliff": "setup.remote.gliff",
    "help": "help",
    "install": "install",
    "remote": "setup.remote",
    "update": "update",
    "why": "trigger.ask.logs",
}

raw = open(sys.argv[1]).read()
# The same two transformations MenuModel.js applies to the JSONC.
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
menu = json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
rows = {k: v for k, v in menu.items() if isinstance(v, dict)}

# Refuse rather than pass on a parse that found next to nothing.
if len(rows) < 200 or "install" not in rows:
    sys.exit(f"menu tree: parsed {len(rows)} rows (no 'install'?); refusing rather than passing")


def parent_of(row_id, row):
    if row_id == "root":
        return ""
    if "parent" in row:  # MenuModel.js: value.parent !== undefined
        return row["parent"]
    return row_id.rsplit(".", 1)[0] if "." in row_id else "root"


def kind_of(row):
    return "action" if row.get("action") else ("link" if row.get("target") else "menu")


children = {}
for row_id, row in rows.items():
    children.setdefault(parent_of(row_id, row), []).append(row_id)

# Walk the screens a user can open, starting at root.
seen_screens, listed, todo = set(), set(), ["root"]
while todo:
    screen = todo.pop()
    if screen in seen_screens:
        continue
    seen_screens.add(screen)
    for child in children.get(screen, []):
        listed.add(child)
        kind = kind_of(rows[child])
        if kind == "menu":
            todo.append(child)
        elif kind == "link":
            todo.append(rows[child]["target"])

errors = []
for row_id, row in rows.items():
    if row_id == "root" or row_id in listed:
        continue
    parent = parent_of(row_id, row)
    if parent != "root" and parent not in rows:
        errors.append(f"orphan: {row_id} (parent {parent} is not a row)")
    elif parent in rows and kind_of(rows[parent]) == "action":
        errors.append(f"under an action: {row_id} (parent {parent} has an action)")
    else:
        errors.append(f"unreachable: {row_id} (parent {parent})")

# Nixarchy's own folder (#1412): a root of its own straight after Trigger, and
# the rows it holds. A row that merely dropped `parent` still falls back to
# Trigger and is reachable, so reachability above cannot see it.
NIXARCHY_CHILDREN = [
    "trigger.devenv", "trigger.podman", "trigger.box", "trigger.vm", "trigger.vm-list",
    "trigger.herdr", "trigger.github-actions", "trigger.gitlab-pipelines", "help",
]
roots = [k for k, v in rows.items() if parent_of(k, v) == "root"]
if "trigger" not in roots or "nixarchy" not in roots:
    errors.append("root: 'trigger' or 'nixarchy' is not a root row")
elif roots.index("nixarchy") != roots.index("trigger") + 1:
    errors.append(f"root order: nixarchy is not directly after trigger: {' '.join(roots)}")
for child in NIXARCHY_CHILDREN:
    if child not in rows:
        errors.append(f"nixarchy folder: {child} is not a row")
    elif parent_of(child, rows[child]) != "nixarchy":
        errors.append(f"nixarchy folder: {child} has parent {parent_of(child, rows[child])}, expected nixarchy")


def norm(alias):
    return str(alias or "").lower().replace("_", "-")


def aliases_of(row):
    a = row.get("aliases")
    return [x for x in (a if isinstance(a, list) else [a]) if x]


def resolve(word):  # MenuModel.js resolveRoute
    if not word or word in ("go", "menu"):
        return "root"
    if word in rows:
        return word
    for row_id, row in rows.items():
        if word in map(norm, aliases_of(row)):
            return row_id
    return word


declared = {}
for row_id, row in rows.items():
    for alias in aliases_of(row):
        owners = declared.setdefault(norm(alias), [])
        if row_id not in owners:
            owners.append(row_id)

for alias, owners in declared.items():
    winner = resolve(alias)
    shared = len(owners) > 1 or winner not in owners
    if alias in EXPECTED:
        if winner != EXPECTED[alias]:
            errors.append(f"alias {alias}: resolves to {winner}, expected {EXPECTED[alias]}")
    elif shared:
        errors.append(
            f"alias {alias}: declared by {', '.join(owners)}; resolves to {winner}; "
            "not in the expected table"
        )
for alias in EXPECTED:
    if alias not in declared:
        errors.append(f"alias {alias}: in the expected table but no row declares it")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)
print(f"menu tree: {len(rows)} rows, all reachable; {len(EXPECTED)} shared or shadowed aliases as expected")
