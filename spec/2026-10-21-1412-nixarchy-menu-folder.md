---
status: approved
issue: 1412
intent: intent/2026-10-21-1412-nixarchy-menu-folder.md
---

# Spec: a top-level Nixarchy folder for nixarchy's panels and Nixi, after Trigger

The intent is approved with every proposal: re-parent rather than rename,
the generator places the folder, no `when` on it, Nixi moves by `parent`,
and Herdr, GitHub Actions and GitLab Pipelines move too. It reverses
#1329's "no top-level Nixarchy row".

**Verified for this spec:** nixi's installer writes
`"help": {icon, label, description, action, aliases}` and **no
`parent`** (`nixi install.py:311-313`). Override merging copies only
stated keys (`MenuModel.js` `statedKeys`), so our `parent` survives a
user's nixi row.

## Design

### 1. The folder row

`modules/apps.nix` adds `"nixarchy"` with label "Nixarchy", nixarchy's
snowflake glyph as the icon (the one the menu button wears, #1053), and a
description of "nixarchy's own panels and help". It has no `action`, no
`when` and no alias.

It is emitted only when at least one child row is emitted, which is
decided at Nix evaluation. With no children there is no empty root.
Visibility at runtime is upstream's: `isVisible` hides a menu row whose
children are all hidden (`MenuModel.js:270-287`; 4.0.6 `:265`).

### 2. The rows move by `parent`, and keep their ids

`parent = "nixarchy";` is added to these rows, in this order:

| row | id | `modules/apps.nix` |
|---|---|---|
| Dev environments | `trigger.devenv` | :775 |
| Podman | `trigger.podman` | :793 |
| Boxes | `trigger.box` | :813 |
| Sandbox | `trigger.vm` / `trigger.vm-list` | :829, :842 |
| Herdr | `trigger.herdr` | :421 |
| GitHub Actions | `trigger.github-actions` | :442 |
| GitLab Pipelines | `trigger.gitlab-pipelines` | :464 |
| Nixi | `help` | :377 |

The ids stay, which is the `system.recovery` shape
(`modules/AGENTS.md#backup-and-recovery-one-menu-542`), so these keep
working:
- `menu.extraEntries` overrides;
- `omarchy menu summon trigger.devenv`;
- the Super+Alt keys (they call `nixarchy-plugin`);
- the `tests/options.nix` id lookups.

Children render in the order the rows are written. The generator writes
them in the table's order, and the `learn.*` rows stay in Learn.
`trigger.hardware.hybrid-gpu` stays under Trigger.

### 3. The generator places the folder after Trigger

At `modules/apps.nix:1233`, `full = dict(upstream); full.update(out)`
becomes: build `full` as today, then reinsert the `nixarchy` key
directly after `trigger`. Python dicts keep insertion order, so rebuild
the dict once:

```text
upstream roots in order, with the nixarchy entry inserted after trigger,
then everything else
```

If `trigger` is missing from upstream, the build fails and names it.
There is no order key; upstream reads none.

### 4. Checks

- **`tests/menu-tree.py`:**
  - the root order from the generated file is
    `…, trigger, nixarchy, style|appearance, …`, the root after
    `nixarchy` being whichever upstream ships (4.0.6 `style`, 4.5
    `appearance`);
  - the eight rows have `parent == "nixarchy"`;
  - `help`'s expected parent changes from `help` (:22) to `nixarchy`.
- **`tests/options.nix`:** extend the existing id lookups
  (:1647-1659, :1686, :2696) to assert the `parent`, and add one
  both-states assertion that the folder exists with defaults on and is
  absent when every child is off (Mode A).
- Every other menu check (`menu-verbs`, `menu-keys`, `menu-actions`,
  `menu-conditions`, `menu-guards`) must stay green.

### 5. Docs

Every "Trigger ▸ <panel>" for these eight rows becomes "Nixarchy ▸ …".
The intent lists the lines:
- `README.md`;
- `docs/manual/{plugins,sandboxes,boxes,development-tools,configuration}.md`;
- `docs/internals/flake.md:489`;
- `modules/apps.nix:3687`, the devenv help text.

`modules/AGENTS.md`'s Sandboxes section said "no precedent here for a root
of our own". It now records #1412 as that precedent and why, and keeps the
#1329 history. The demo's `trigger` frame (`tests/demo/default.nix:319`)
loses those rows. A `nixarchy` frame is added beside it, so the demo shows
the folder.

## Alternatives rejected

- **Renaming to `nixarchy.*`:** every override, summon, test and doc
  changes, for cleaner ids only (intent decision 2).
- **An order or after key:** upstream ignores it.
- **Writing the folder into the user's extension file:** a user's file
  cannot move a root, and the file is theirs (#210).
- **A `when` on the folder:** it hides working children
  (`modules/AGENTS.md`, "Hidden children are hidden individually").

## Risks

- **`nixarchy-menu` (the alternative menu plugin,
  `menu.default = "nixarchy"`)** may order roots differently. It reads the
  same defaults file. If its order differs, that is its own issue; this
  spec covers the stock menu. Checked at implementation by reading its
  merge code, and recorded either way.
- **Edge (quattro) and stable (4.5.0-rc1) share this code**, so
  `appearance` sits after `nixarchy` on both. The order assertion names
  `trigger` only before `nixarchy`, so it holds on both.
- **Users whose own extension overrides one of these ids** keep their
  keys, but our `parent` applies unless they state one. That is the
  intended merge.

## Verification (§1)

| change | red | green |
|---|---|---|
| order | the generator without the reinsertion: `menu-tree` reports `nixarchy` last | after `trigger` |
| parents | one row without `parent`: `menu-tree` names it | all eight |
| folder only with children | `options` with every child off and the row emitted unconditionally: the absent-state assertion fails | conditional |
| everything | — | the full generated list on stable, then edge's next promotion (the shared code reaches edge through its merge of main) |
