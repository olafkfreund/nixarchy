---
status: approved
issue: 1329
spec: spec/2026-10-18-1329-edge-menu-parents.md
---

# Plan: on quattro, every nixarchy menu row can be reached by browsing

## Approved decisions, carried over

1. **Guarded parent:** an upstream `remove.*` row that has children (some
   upstream id starts with `<row>.`) and whose own `when` matches `PKG_GUARD`.
   On v4.0.4 and v4.0.5 there are none (measured). On quattro 386176a the only
   one is `remove.dictation`.
2. The three Remove rules in `menuDefaults` (`modules/apps.nix` ~1092
   pkg-present, ~1115 Install-sibling, ~1144 hide-unported) **skip** a guarded
   parent. A new rule after them gives it only a `when`, derived from its
   direct children's final `when`s:
   - all `"false"` → `"false"`;
   - any child with an empty `when` → `"true"`;
   - otherwise the visible ones joined as `( a ) || ( b )`.

   It gets no action, so it stays a submenu.
3. The five panel rows move from `apps.*` to `trigger.*` on both channels, with
   every field unchanged: `gitlab-pipelines`, `github-actions`, `herdr`,
   `devenv`, `podman`. No `trigger.<these>` id exists upstream (measured).
4. "Apps ▸ X" becomes "Trigger ▸ X" in the docs. The stale-extension advice in
   `configuration.md` keeps the old ids and gains one sentence.
5. No exemption in `menu-verbs`, and no edge-only code. Done means `edge`
   contains the head.

## Who does what

The coder (Sonnet) does steps 1–3, one `SendMessage` per step. The lead does
0, 4 and 5, plus every commit and push.

## Steps

### 0. [lead] Stable baseline

On this branch before any edit, copy the menu `checks.menu-actions` reads (its
derivation's `menu` env, the `reference` machine extended with boxes and
devenv, and so with podman) to `/mnt/data/vmtest/1329-menu-before.jsonc`.
`reference` alone has no `apps.devenv`, and has `apps.podman` only when podman
is on, so it could show three of the five renames at most (review finding 3).
Compare the files' contents, not drvPaths (§5).

### 1. [coder] `modules/apps.nix`, the generator (~lines 1086–1150)

- After `PKG_GUARD` (~1087), add:
  ```python
  # A Remove row upstream made a submenu is browsed into, so no rule gives it an action (#1329).
  def guarded_parent(row_id, row):
      return (row_id.startswith("remove.") and PKG_GUARD.search(str(row.get("when", "")))
              and any(k.startswith(row_id + ".") for k in upstream))
  ```
- In each of the three rules, skip a guarded parent with the same `continue`
  or condition the rule already uses for `row_id in overrides`.
- After rule 3, add the parent rule (decision 2). It begins with
  `if row_id in overrides: sys.exit(f"guarded parent {row_id} was given an override by an earlier rule")`,
  so a rule that loses its skip fails the build rather than being silently
  overwritten (review finding 1). Direct children only, meaning no further
  `.` after the parent's prefix. A child's `when` is
  `overrides[k]["when"]` if set, else `upstream[k].get("when", "")`. Set
  `overrides[row_id] = {"when": …}`.
- Verify: `nix fmt`, `git diff --stat` (only `modules/apps.nix`), `git add -A`,
  then `menu-guards` and `menu-actions` green under the flock.

Traps:
- This is Python inside a Nix `''…''` string. `${` must not appear unescaped,
  and Python strings use **double quotes only**: an empty `''` ends the Nix
  string (`apps.nix:1162` already uses `""`). The indentation must match the
  block. No heredoc (§5).
- An agent hook may reformat with `nixpkgs-fmt`. `nix fmt` reverts it (§5).

### 2. [coder] The five rows, and what names them

- `modules/apps.nix`: rename the keys at ~421, 442, 464, 753, 771 to
  `trigger.*`. Change nothing else in them. Line ~3638 "Apps > Dev
  environments" becomes "Trigger > Dev environments".
- `tests/options.nix:1635-1636` `"apps.devenv"` → `"trigger.devenv"`;
  `:2684` `"apps.podman"` → `"trigger.podman"`. The `:1633` comment "The Apps
  row exists exactly where the panel does." becomes "The Trigger row …".
- `grep -rnE 'apps\.(devenv|github-actions|gitlab-pipelines|herdr|podman)\b'`
  over `modules tests pkgs data .github` must now match nothing except
  `cfg.apps.*` and `programs.nixarchy.apps.*` option paths. Also grep
  `tests/demo/` (§4).
- Verify: `nix fmt`, `menu-guards` green.

### 3. [coder] Docs

- "Apps ▸ <one of the five>" becomes "Trigger ▸ <same>" in:
  - `docs/manual/plugins.md` (29, 30, 31, 34, 35, 204);
  - `configuration.md` (181, 186, 193, 199);
  - `per-project-environments.md:27`, wrapped across lines;
  - `boxes.md:73`, wrapped;
  - `development-tools.md:360`;
  - `docs/internals/flake.md:489`;
  - `README.md` (483, 485, 497, 498, 499, 522);
  - `modules/AGENTS.md:1093`, "The Apps ▸ Podman row uses the same gate"
    (review finding 4).

  Rewrap only the paragraph you touched.
- `configuration.md`, after the stale-extension sentence (~190), add a sentence
  naming all five: since #1329 nixarchy's Dev environments, GitHub Actions,
  GitLab Pipelines, Herdr and Podman rows are under Trigger. So an `apps.*` key
  of theirs in your extension file, whether a panel's `register` wrote it or you
  pasted the panel's own `share/omarchy-menu.jsonc` snippet, only adds a second
  row under Apps, and on quattro that row cannot be browsed to (review
  finding 6). The plugin repos' own docs still say "under Apps". Changing them
  is outside this repo (§11) and goes in the PR as a follow-up.
- Verify: `grep -rn 'Apps ▸ \(Dev environments\|GitHub Actions\|GitLab Pipelines\|Herdr\|Podman\)' docs README.md`
  is empty, and `.github/scripts/readme-counts.sh` passes.

### 4. [lead] Verify, and the §1 breaks

- **Stable:** rebuild step 0's file into `1329-menu-after.jsonc`. Diff it as
  JSON with sorted keys (`jq -S`). The only differences allowed are the five
  `apps.*` keys becoming `trigger.*`, with identical values. Then state the
  order change, which `jq -S` hides: rows upstream does not ship come after
  upstream's, in `builtins.toJSON`'s sorted order. So Trigger reads Boxes,
  Dev environments, GitHub Actions, GitLab Pipelines, Herdr, Podman, Sandbox
  (finding 7). The `tests/demo` scenes `menu-apps` and `menu-trigger`
  summon by route and keep working, but record different contents.
- **Edge:** in `/mnt/data/vmtest/wt-1325-edge` (the #1325 carry, 22115c78), run
  `git merge` on this branch's head. Then `menu-verbs`, `menu-actions`,
  `menu-guards` and `bin-ledger` must all be green. Check with `jq` on the edge
  menu that `remove.dictation` has no `action` and its `when` is Voxtype's grep.
- **Breaks:** commit a `wip:` baseline in the edge tree first. Restore each
  break with `git checkout HEAD -- modules`.

  | break | expect |
  |---|---|
  | B1: drop the guarded-parent skip from rule 1 | the build fails: `guarded parent remove.dictation was given an override by an earlier rule` |
  | B2: rename `trigger.herdr` back to `apps.herdr` | `menu-verbs`: `under an action: apps.herdr` |
  | B3: drop rule 3's skip **and** delete the parent rule (agy's case) | the edge menu's `remove.dictation.when` is `"false"`, by `jq` |
  | B4: delete the parent rule only | `remove.dictation` keeps upstream's `omarchy-pkg-present …` guard. Record what `menu-guards` says, which the review could not verify. If it stays green, the PR names this as a case only the `jq` assertion sees |

  Then green again. Reset the scratch edge worktree to **22115c78** (the #1325
  carry, before this branch was merged in), not to the merge, so step 5's
  `origin/main` merge does not bring both the branch and its squash (finding
  8).
- On main: `nix fmt -- --ci`, `menu-actions`, `menu-guards`.

Traps:
- §5: `git checkout HEAD --`, not `git checkout --`.
- §1: prove each break landed with `git diff`.

### 5. [lead] PR, then edge

- Commit steps 1–3 as one commit after this plan's approval commit. Subject:
  `nixarchy's five panel rows move to Trigger, and a Remove row quattro made a submenu keeps no action (#1329)`.
  Then `git merge origin/main`, and check `git merge-base`.
- The PR body links all three artifacts, says the coder did steps 1–3, includes
  the B1–B3 output, and says `Refs #1329`. It is not a CI-gate change, so it is
  armed with `merge-when-green.sh` the usual way.
- After it merges:
  1. in the edge worktree, merge `origin/main` (which now contains this) on top
     of the #1325 carry;
  2. re-run `menu-verbs`, `menu-actions`, `menu-guards` and `bin-ledger`;
  3. with no edge run and no install in flight, push `HEAD:edge-candidate` as a
     fast-forward;
  4. `gh workflow run omarchy-edge.yml --ref main -f from_candidate=true`, well
     before 06:00 UTC.
- Done when `git merge-base --is-ancestor <this PR's squash commit on main> origin/edge`
  and the same for 22115c78. Then:
  - close #1329 and #1326 by hand, naming the commits;
  - tell the maintainer #1334 can now be merged;
  - once #1334 has merged, close #1325 by hand, naming both (finding 8).

## Tests

| command | expect |
|---|---|
| stable menu before/after `jq -S` diff | only the five key renames |
| `menu-verbs` on edge | green |
| `menu-actions`, `menu-guards`, `bin-ledger` on edge and main | green |
| B1–B3 | each red, as above |
| `readme-counts.sh` | passes |
| `options`, `session` | CI, green |

## Rollback

- Revert the PR on main. Edge: revert on a branch from `edge`, push to
  `edge-candidate`, and dispatch with `from_candidate=true`.
- No state: the menu is generated at build time, and a user's extension file
  is untouched.
