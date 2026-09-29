---
status: approved
issue: 1069
spec: spec/2026-09-29-1069-menu-modelpath.md
---

# Plan: Super+Space opens a menu on every nixarchy install

## Approved decisions

- Add `environment.pathsToLink = [ "/share/omarchy" ]` under `mkIf cfg.enable`.
- `checks.session` asserts that `omarchy-menu summon install` opens an
  `omarchy-menu` layer: parsed in Python, closed with Escape, and the message
  names #1069.
- The nixarchy-menu `$OMARCHY_PATH` change is a follow-up issue.

## Steps

1. **`modules/nixos.nix`:** add `pathsToLink` beside `systemPackages`, with a
   one-line comment. Then `nix fmt` and `git diff --stat`.
2. **`tests/session.nix`:** add the probe after the Hyprforge block, using
   `on_desktop`.
3. **Baseline commit, then red and green:**
   - `demo-scene-menus` with the fix is green, against red on main.
   - `checks.session` with the pathsToLink line removed fails naming #1069
     (local, CI idle).
   - CI runs `session` green on the PR.
4. **File the nixarchy-menu follow-up issue, then open the PR.** Merge when
   green: the owner authorised merging hotfixes when green.

## Tests

| Command | Expected |
| --- | --- |
| `nix build .#demo-scene-menus` | green, and frames show the palette |
| `checks.session` with the break | the probe fails, naming #1069 |
| `checks.session` on the PR (CI) | green |

## Rollback

Revert the squash commit.
