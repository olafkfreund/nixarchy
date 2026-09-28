---
status: draft
issue: 1037
author: Olaf Freund
---

# Intent: rebuilding from the flake checkout refuses a branch nobody chose to deploy

## Problem

nixarchy's rebuild paths build `NIXARCHY_FLAKE` (by default `/etc/nixos`)
from **whatever branch that checkout has checked out**. When coding agents
share the config checkout, one of them leaving a feature branch checked out
turns the next "Apply" into a deploy of unmerged, unpushed work to a live
desktop. That happened: olafkfreund/nixos_config#2052, where p620 was switched
twice from an agent's branch. nixos_config now guards its own deploy recipes
(#2056), but nixarchy's paths don't go through them.

The premise was checked by searching for the behaviour, not a spelling (§12).
**No rebuild path looks at the branch today**, and there are three paths from
the checkout to a switched system:

1. **`nixarchy-apply`** (`modules/apps.nix`, `nh os switch "$flake"`). This
   is what a menu pick runs. The bar's rebuild action starts the
   `nixarchy-rebuild` unit through `apply --detach`, and
   `omarchy-default-agent` `exec`s `apply`, so both go through it.
2. **`omarchy-update`** (`pkgs/omarchy/nix-bin`, the menu's *Update* row):
   `nh os switch --update … "$flake"`.
3. **`programs.nixarchy.autoUpdate`** (`modules/auto-update.nix`). Its
   `flake` defaults to `programs.nixarchy.flake`, the same checkout. It
   refuses a dirty tree but not another branch, so on its daily timer it
   would update `nixpkgs` in the lock and switch, **unattended, from
   whatever branch is checked out.** #1037 doesn't name this one, and it's
   the quietest of the three.

Out of scope, checked: `nixarchy-rollback` switches to an existing
generation, not the checkout. The plymouth, sddm and sudo scripts only print
a command. `fleet` pulls a remote flake URL. `nixarchy-try` and
`nixarchy-preview` build without switching.

## Proposed outcome

When the checkout is on a branch other than its default one, or on a
detached HEAD that isn't the default branch's tip, all three paths refuse
before building. The message names the branch and says how to proceed on
purpose. For someone who keeps one checkout and switches branches
deliberately, today's behaviour is one override away. A checkout that isn't
a git repository at all behaves exactly as today.

## Affected users and systems

Every nixarchy machine whose `programs.nixarchy.flake` is a git checkout, in
practice all installer-managed machines. It matters most where several agents
or people share one checkout, as on p620.

## Constraints

- **Mode A** (`modules/AGENTS.md`): a machine that doesn't use these
  commands must be untouched. The guard lives in the commands, not in
  activation.
- **The unattended path cannot ask.** `autoUpdate` must refuse *and be seen
  refusing*: the unit fails, rather than skipping silently. The module
  already fails loudly on a dirty tree, and a machine that has quietly
  stopped updating is the failure it exists to prevent.
- **One definition of "the default branch"**, shared by all three, so they
  can't disagree. It should match nixos_config's #2056 rule, where a
  worktree detached exactly at `origin/main` counts as main, so the same
  checkout gets the same answer from both repos' tools.
- **Offline must still work.** Deciding the default branch can't require a
  network fetch, because apply runs on machines that are often offline.
- AGENTS.md §2: this was found by using the thing, so a check has to see it,
  one that makes a checkout on a feature branch and watches each path refuse.

## Open questions

1. **What is the override?** #1037 suggests an environment variable, or
   `apply`'s existing `--yes`. `--yes` today means "don't ask me to confirm
   the switch", a different question from "yes, deploy this branch".
   Reusing it would make every scripted `apply --yes` bypass the guard.
   My lean is a separate variable (`NIXARCHY_ALLOW_BRANCH=1`), with the
   refusal message naming it. The spec will settle it.
2. **How is "default branch" known offline?** Candidates are
   `refs/remotes/origin/HEAD`, then `main` if that ref is missing, and
   treating a checkout with no remote as its own default. The spec will pick
   one and say what happens when none of those resolve.
