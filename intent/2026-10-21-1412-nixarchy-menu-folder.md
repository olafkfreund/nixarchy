---
status: draft
issue: 1412
author: olafkfreund
---

# Intent: a top-level Nixarchy folder for nixarchy's panels and Nixi, after Trigger

## Problem

nixarchy's own panels are scattered through upstream's menu. Dev environments,
Podman, Boxes and Sandbox sit in Trigger among Omarchy's rows (Emoji, Capture,
Share...): `trigger.devenv`, `trigger.podman`, `trigger.box`, `trigger.vm` and
`trigger.vm-list` (`modules/apps.nix:775,793,813,829,842`). Nixi is a lone
top-level row, id `help` (`modules/apps.nix:377`). The generator builds the
defaults as `full = dict(upstream); full.update(out)`
(`modules/apps.nix:1233-1234`), so a new id goes on the end, and the menu
renders in first-definition order (`MenuModel.js` `mergeMenuSources`, `:87,105`
in 4.5.0-rc1). So Nixi lands after About and System, the last roots in
upstream's file (`omarchy-menu.jsonc:24-33`: apps, learn, trigger, style,
setup, install, remove, update, about, system).

Nobody can see what nixarchy adds, and nothing says which rows are ours.

This reverses an earlier decision. #1329's spec turned down "a new top-level
Nixarchy row" because it "needs its own icon, label and root position, when
Trigger already holds nixarchy's panels"
(`spec/2026-10-18-1329-edge-menu-parents.md:83-84`). Its intent had wanted "a
nixarchy-owned submenu"
(`intent/2026-10-18-1329-edge-menu-parents.md`, Proposed outcome).

## Proposed outcome

- The root menu has a **Nixarchy** row directly after Trigger and before Style,
  on 4.5 and on 4.0.x. Both list the roots in the same order.
- It holds Dev environments, Podman, Boxes, Sandbox (or its terminal fallback)
  and Nixi, and opens like any other submenu.
- When none of its rows apply, the Nixarchy row is not shown.
- Rows that replace Omarchy's own stay where they are: Install (Edit app
  selection, Search, Packages), Update › Channel, Setup, and System › Backup
  and recovery.
- Search and the Super+Alt keys work as before. The keys call
  `nixarchy-plugin` directly, not a menu id (#1329 intent, Proposed outcome).
- The docs that name a path say Nixarchy ▸ … instead of Trigger ▸ …

## Affected users and systems

- `modules/apps.nix`: the five rows, the `help` row, a new root row, and the
  ordering step in the generator (`:1233`). The Devenv help text at `:3687`
  says "Trigger > Dev environments".
- `tests/options.nix:1647-1659,1686,2696` read these ids. `tests/menu-tree.py:22`
  expects `help` → `help`. The other menu checks (`menu-verbs`, `menu-keys`,
  `menu-actions`, `menu-conditions`, `menu-guards`) run over the generated
  file and have to stay green.
- Docs that say Trigger ▸ for these panels: `README.md:483,485,520-522`,
  `docs/manual/plugins.md:29,32-34,158,177,204`, `sandboxes.md:51,60`,
  `boxes.md:73,79`, `development-tools.md:360`, `configuration.md:181,193`,
  `docs/internals/flake.md:489`, `modules/AGENTS.md:1097,1835-1837,1939-1975`.
  The last one is the Sandboxes-group reasoning, which says "no precedent here
  for a root of our own".
- `tests/demo/default.nix:319` records the `trigger` screen, and its frame gate
  will see fewer rows.
- Users: everyone on the stock Omarchy menu. Users with Nixi installed: nixi's
  `install.py` writes a `help` row into
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` (`modules/apps.nix:366-371`).

## Constraints

- Keep the `help` id. Renaming it gives every machine that ran nixi's installer
  two Nixi rows (`modules/apps.nix:366-371`). Moving it with `parent` is safe:
  an override copies only the keys it states (`MenuModel.js:67` `statedKeys`,
  `:91-93`). So nixi's row, which states no `parent`, keeps ours. Check this
  against nixi's real row before relying on it.
- Do not put a `when` on the folder. `isVisible` already hides a menu row whose
  children are all hidden (`MenuModel.js:270-287`; same on 4.0.6 `:265`). A
  `when` on the parent is the mistake "Hidden children are hidden individually"
  warns about (`modules/AGENTS.md:1849-1858`).
- Order comes from the generator, never from the user's file. The user's file
  adds ids after the defaults and cannot move a root.
- Mode A: these rows already sit inside `config = lib.mkIf cfg.enable`
  (`modules/AGENTS.md:1951-1955`). Keep it that way.
- Emit the folder row only when at least one child is emitted at build time.
  That way an evaluation with no panels has no empty root row.
- §1: every new or changed check has to fail on the break first: the order
  assertion, and the folder hiding when it is empty.

## Open questions

1. **How is the position set?** Proposal: the generator rebuilds `full` and
   puts nixarchy's root ids right after `trigger`. The list of ids to place is
   explicit, and the build fails if `trigger` is missing. A `checks.options` or
   `menu-tree` assertion checks the root order. The rejected option is an
   `order`/`after` key, which upstream does not read.
2. **Rename the ids or re-parent them?** Proposal: keep `trigger.*` and add
   `parent = "nixarchy"`, the shape `system.recovery` already uses for rows
   whose id prefix is not their parent (`modules/AGENTS.md:1859-1870`). This
   keeps `menu.extraEntries` overrides and any `summon trigger.devenv` working,
   and keeps the diff to the tests small. The cost is ids that misname their
   folder. The other option is `nixarchy.devenv` etc., renamed with no alias
   the way #542 did it (`modules/AGENTS.md:1872-1890`): cleaner ids, but every
   test and override has to change.
3. **The folder's id and label?** Proposal: `nixarchy`, label "Nixarchy", plus
   an icon of our own, with no alias "nixarchy". Search for "nixarchy" then
   finds the row by its label. Check that no id or alias already takes it.
4. **What hides the folder?** Proposal: upstream's own `isVisible` recursion,
   with no `when`. Note that `nixarchy-vm --check` always exits 0
   (`modules/AGENTS.md:1957-1961`), so Sandbox or its fallback is always there
   and the folder will show on every machine. The hiding rule only applies to
   an evaluation with no rows.
5. **Does Nixi's `help` row move?** Proposal: yes, by `parent`, under the
   constraint above. It goes last in the folder.
6. **Do Herdr, GitHub Actions and GitLab Pipelines move as well?** They are
   nixarchy's own panels under Trigger too (`modules/apps.nix:421,442,464`,
   `configuration.md:192-194`). The issue names only four. Proposal: move them
   too, or the folder is "some of nixarchy" and its premise does not hold. Rows
   with a matching `learn.*` id stay in Learn.
7. **Does `trigger.hardware.hybrid-gpu` (`:882`) move?** Proposal: no. It is a
   hardware action under upstream's Hardware group, not a panel.
