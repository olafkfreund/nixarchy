---
status: draft
issue: 1329
author: olafkfreund
---

# Intent: on quattro, every nixarchy menu row can be reached by browsing, so edge promotes again

## Problem

Edge has not promoted since 7e40ba7. Every edge run since #1307 fails
`menu-verbs` in `prepare`, which flags a row that sits under a row with its own
action: choosing the parent runs that action, so the child can only be reached
by search. On quattro (edge-candidate, 386176a, merged with main 4ff4e62e)
it names seven rows:

| rows | parent | why the parent has an action |
|---|---|---|
| `apps.{devenv,github-actions,gitlab-pipelines,herdr,podman}` | `apps` | quattro gave Apps `"action": "omarchy-shell omarchy.dock apps"`; on v4.0.4 and v4.0.5 it has only `"provider": "apps"` |
| `remove.dictation.{voxtype,superwhisper}` | `remove.dictation` | **ours**: quattro made it a submenu parent with no action, and `modules/apps.nix`'s Remove-row generator gave it `nixarchy-app-disable dictation`, because its `when` names `omarchy-pkg-present voxtype-bin` (the rule at ~line 1115). The Install-sibling rule after it would do the same |

So edge is stuck without #1313's fix, and everything merged since: #1306,
#1320, #1327 and #1328. #1326, which CI filed, stays open until it promotes.

## Proposed outcome

- `menu-verbs` is green on the edge tree, and an edge run promotes.
- Dictation: Remove › Dictation on quattro is a submenu again. Voxtype under it
  removes the app from the selection, as now; Superwhisper stays hidden.
  On stable, `remove.dictation` is a leaf and is unchanged.
- Apps: nixarchy's five rows (Dev environments, GitHub Actions, GitLab
  Pipelines, Herdr, Podman) can be browsed to on both channels. They move to a
  nixarchy-owned submenu of their own, the direction the owner approved
  in the session on 2026-10-18, rather than overriding quattro's Apps action.
- Search finds each of the five, and the Super+Alt keybindings are unchanged.
  They call `nixarchy-plugin` directly, not the menu id.

## Affected users and systems

- `modules/apps.nix`: the Remove-row generator, and the five `apps.*` rows
  (lines 421, 442, 464, 775, 793).
- Every Omarchy session on both channels: the five rows move out of Apps.
- Docs that say "Apps › Podman" and so on, the manual and the plugin pages.
- Checks that name these ids: `menu-verbs`, `menu-guards`, `options`, the
  session check's menu probes, and `tests/demo/` scenes (§4).

Found in review (agy): if the generator just skips a parent row, a third rule
(`modules/apps.nix:1147`, `PKG_GUARD`) sets `when = "false"` on any Remove row
guarded by `omarchy-pkg-present`, and that would hide the whole Dictation
submenu. So the parent's `when` still has to be rewritten. The pkg-present
rule also reads only the first package in an `||` guard.

## Constraints

- Stable and Mode A must not regress. `checks.options` asserts every option in
  both states.
- No fix on edge that hides the problem from `menu-verbs`, for example by
  exempting the rows.
- Done means `edge` contains the fix (`git merge-base --is-ancestor`), not
  just `edge-candidate`, as #1325's plan decided.
- The generator fix goes on main, because the generator is shared. The edge
  carry is only the merge.

## Open questions

1. Where the five rows go. Two candidates:
   - **Trigger** (`trigger.*`), my recommendation, from agy's review. It is
     where nixarchy already puts its other two panels, Boxes and Sandbox
     (`trigger.box` and `trigger.vm`, `modules/apps.nix:791,807`). Trigger has
     no action on v4.0.5 or on quattro, so no new top-level row is needed.
   - A new top-level **Nixarchy** row, which needs its own label and icon, and
     a place in the root menu.
2. Both channels, or quattro only? I recommend both. Quattro becomes stable,
   one code path is simpler, and stable's Apps provider list does not need our
   rows mixed in.
