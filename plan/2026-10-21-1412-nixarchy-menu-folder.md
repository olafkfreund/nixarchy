---
status: approved
issue: 1412
spec: spec/2026-10-21-1412-nixarchy-menu-folder.md
---

# Plan: a top-level Nixarchy folder for nixarchy's panels and Nixi, after Trigger

## Decisions (approved intent and spec)

- **A new root row `nixarchy`** ("Nixarchy", the snowflake icon, a short
  description, no `action`, no `when`, no alias). It is emitted only when
  at least one child row is emitted, decided at evaluation.
- **Eight rows get `parent = "nixarchy";` and keep their ids**, written
  in this order:
  1. `trigger.devenv` (:775)
  2. `trigger.podman` (:793)
  3. `trigger.box` (:813)
  4. `trigger.vm` (:829)
  5. `trigger.vm-list` (:842)
  6. `trigger.herdr` (:421)
  7. `trigger.github-actions` (:442)
  8. `trigger.gitlab-pipelines` (:464)
  9. `help` (:377), last
- `trigger.hardware.hybrid-gpu` stays under Trigger, and the `learn.*`
  rows stay in Learn.
- **The generator** (`modules/apps.nix:1233-1234`) reinserts `nixarchy`
  directly after `trigger`, and exits naming `trigger` if upstream lacks
  it.
- **Checks:**
  - `tests/menu-tree.py` asserts the root order (`trigger` then
    `nixarchy`) and the eight parents. `EXPECTED["help"] = "help"` (:22)
    stays: it maps the search alias to the row **id**, not to a parent.
  - `tests/options.nix` asserts the folder in both states.
- **Docs:** Trigger ▸ X becomes Nixarchy ▸ X for these rows;
  `modules/AGENTS.md` records the precedent; the demo gets a `nixarchy`
  frame.
- `nixi`'s installer row states no `parent` (`install.py:311-313`), so
  ours survives the merge.

## Repo traps

- **The generator is Python embedded in Nix.** Keep its style, and a file
  rather than `python3 -c` if new code grows (#1205).
- `nix fmt`, then `git diff --stat`.
- Cheap builds go one at a time, under the flock, by drvPath.
  `.#omarchy` and anything pulling the menu tree only when the load is
  below 12.
- `checks.options` is VM-tier (11.5 GB). Its assertions are written and
  CI runs them; do not build it locally.
- A row without a matching upstream id fails the generator ("upstream
  menu has no rows") only for **override** rows. `nixarchy` is a new id,
  so check how new ids are emitted (#226: `trigger.vm` was new) and
  follow that path.

## Steps (coder, one at a time; the lead commits)

1. **The folder row and the parents** (`modules/apps.nix`).
   - Add the `nixarchy` row next to the existing new-id rows, conditional
     on any child being present (`lib.optionalAttrs`).
   - Add `parent = "nixarchy";` to the eight rows plus `help`.
   - Verify: build the generated menu derivation (the
     `nixarchy-omarchy-menu.jsonc` drv, as `menu-actions` builds it) and
     check that `jq` shows the nine parents and the new root.
2. **The generator's ordering** (`modules/apps.nix:1233`).
   - Rebuild `full`, inserting `nixarchy` after `trigger`.
   - `sys.exit("upstream menu has no trigger root; cannot place nixarchy")`
     if absent.
   - Verify: the root keys of the generated file are in order.
3. **The checks** (`tests/menu-tree.py`, `tests/options.nix`).
   - `menu-tree.py`: the root order and the parents.
   - `options.nix`: a both-states case. On: the generated menu has
     `nixarchy`. Off: with every child disabled, it has none. Find which
     fixture can turn every child off; if none can, assert the on state
     and say so.
   - Red:
     - the order: the generator without the reinsertion (`menu-tree`
       reports `nixarchy` last);
     - the parents: one row without `parent`.
   - Green: `menu-tree`, `menu-verbs`, `menu-keys`, `menu-actions`,
     `menu-conditions` and `menu-guards`.
4. **Docs and demo.**
   - Trigger ▸ X becomes Nixarchy ▸ X in `README.md:483,485,520-522`,
     `docs/manual/plugins.md:29,32-34,158,177,204`, `sandboxes.md:51,60`,
     `boxes.md:73,79`, `development-tools.md:360`,
     `configuration.md:181,193`, `docs/internals/flake.md:489` and
     `modules/apps.nix:3687`. Grep for every other occurrence too.
   - `modules/AGENTS.md`'s Sandboxes section records #1412 as the
     precedent for a root of our own, and why, keeping the #1329
     history.
   - `tests/demo/default.nix:319`: add a `nixarchy` frame beside
     `trigger`.
   - Verify: `doc-options` and `docs-lists` pass, and the demo
     attributes evaluate.

## Lead

- The full generated list, one at a time, plus `.#omarchy`.
- PR: `Closes #1412`, linking intent, spec and plan, merged with a
  squash (it carries no other branch).
- Edge gets it through its nightly merge of `main`. If edge's next run
  goes red on it, that run's digest names the check.

## Rollback

Revert the PR. The rows go back under Trigger, and Nixi goes back to
the root.
