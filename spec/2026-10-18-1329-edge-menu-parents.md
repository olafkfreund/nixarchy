---
status: draft
issue: 1329
intent: intent/2026-10-18-1329-edge-menu-parents.md
---

# Spec: on quattro, every nixarchy menu row can be reached by browsing

## Design

### 1. The Remove generator leaves a submenu parent without an action

`modules/apps.nix`'s `menuDefaults` script has three rules for upstream
`remove.*` rows: pkg-present at ~1092, Install-sibling at ~1115, and hide
unported at ~1144. A fourth rule is added, and the first three skip one kind of
row: a **guarded parent**. That is a `remove.*` row upstream gives children
(some id starts with `<row>.`), whose own `when` carries an `omarchy-pkg-*`
guard.

- Rules 1–3 `continue` on a guarded parent, so none of them gives it an action,
  a description or `when = "false"`.
- The new rule runs after rule 3, once every child's override is final. It
  sets the parent's `when` from its direct children:
  - every child hidden (`when == "false"`) → `{"when": "false"}`;
  - otherwise the `||` of the visible children's `when`s, each in `( … )`;
  - a child with no `when` makes the parent `when = "true"`.

  The parent has no action, so it stays a submenu. `merged` copies the other
  keys (label, icon) from upstream, and the guard on upstream's `when` is
  replaced, not carried.
- This also fixes agy's second finding, that rule 1 reads only the first
  package of an `||` guard. The parent's `when` now follows its children,
  whichever package comes first.

What it produces:

| release | guarded parents | effect |
|---|---|---|
| v4.0.4, v4.0.5 (stable) | none (measured: no `remove.*` row with a pkg guard and no action) | the generated menu is byte-identical |
| quattro 386176a | `remove.dictation` | no action. `when` is Voxtype's `grep … dictation\.enable …`. Superwhisper stays `false` |

### 2. The five panel rows move from Apps to Trigger, on both channels

In `modules/apps.nix`:
- `apps.gitlab-pipelines` (421) → `trigger.gitlab-pipelines`;
- `apps.github-actions` (442) → `trigger.github-actions`;
- `apps.herdr` (464) → `trigger.herdr`;
- `apps.devenv` (753) → `trigger.devenv`;
- `apps.podman` (771) → `trigger.podman`.

Each row keeps its label, icon, action, `when`, aliases and description.
Trigger already holds nixarchy's other panels, `trigger.box` and `trigger.vm`
(791, 807). It has no action on v4.0.4, v4.0.5 or quattro, and none of the
five new ids exists upstream on any of them (measured).

Everything that names the old ids or the "Apps ▸" path moves too:

| file | what |
|---|---|
| `tests/options.nix:1635-1636, 2684` | `"apps.devenv"` and `"apps.podman"` become `trigger.*` |
| `modules/apps.nix:3638` | "Apps > Dev environments" in a message |
| `docs/manual/plugins.md` (6), `configuration.md` (4), `per-project-environments.md`, `boxes.md`, `development-tools.md`, `docs/internals/flake.md`, `README.md` (6) | "Apps ▸ X" becomes "Trigger ▸ X": 20 places, two of them wrapped across lines |
| `docs/manual/configuration.md:189,195` | the stale-extension-file advice names `apps.gitlab-pipelines` and `apps.github-actions`. It keeps the old ids, because those are what an old `register` wrote; it gains one sentence saying the rows now live under Trigger |

The keybindings (Super+Alt+E/A/P/H/O) call `nixarchy-plugin` directly and do
not change. Search matches labels and aliases, which do not change either.

### 3. Edge

Edge gets no code of its own. Once this merges, `edge-candidate` is
`origin/edge-candidate` merged with main, plus #1325's carry. It is pushed as a
fast-forward and dispatched with `from_candidate=true`. Done means
`git merge-base --is-ancestor <head> origin/edge`.

## Alternatives rejected

- **Drop quattro's `action` from `apps` on edge.** It fights upstream's new
  dock launcher, and setting a key to `""` in an override blanks it rather than
  removing it (`merged` copies only non-empty keys).
- **Move the rows on quattro only.** It needs channel branching in
  `modules/apps.nix` and the tests, then a second move when quattro becomes
  stable.
- **A new top-level "Nixarchy" row.** It needs its own icon, label and root
  position, when Trigger already holds nixarchy's panels.
- **Let rules 1 and 2 just skip parents.** Rule 3 would then hide the whole
  Dictation submenu (agy's review).
- **Exempt the rows in `menu-verbs`.** That hides the bug. The intent rules it
  out.

## Risks

- **A user's own extension file** with `apps.gitlab-pipelines` or
  `apps.github-actions`, written by a panel's `register` before nixarchy
  managed it, keeps an old row under Apps. On quattro that row cannot be
  browsed to. The docs already say to delete those keys, and the new sentence
  says where the rows are now.
- **Muscle memory:** five rows move. They show up in the release notes as a
  changed menu location, with the keybindings unchanged.
- **The new rule on stable:** none of the measured rows is a guarded parent, so
  nothing changes. A future upstream release that adds one gets the behaviour
  above, which is the point.

## Verification

- **Stable, unchanged:** build `menuDefaults` on main before and after, in the
  same tree (§5). The JSON diff is exactly the five renames. Nothing else
  moves, and the generator rule changes no row.
- **Edge:** on `edge-candidate` merged with this branch, `menu-verbs` is green.
  `remove.dictation` has no action, and `trigger.*` holds the five rows.
- **§1 breaks, on the edge tree:**
  - B1: remove the parent skip from rule 1. `menu-verbs` reports
    `under an action: remove.dictation.voxtype`.
  - B2: rename one row back to `apps.herdr`. `menu-verbs` reports
    `under an action: apps.herdr`.
  - B3: remove the new rule. `remove.dictation` reads `when = "false"` (rule 3
    hides it). This is asserted with a `jq` on the generated menu, and is the
    case agy found.
- **Also:** `menu-guards`, `menu-actions`, `bin-ledger` and `nix fmt -- --ci`
  on main. `options` and `session` run in CI.
- **Done:** an edge run promotes, and `edge` contains the head.
