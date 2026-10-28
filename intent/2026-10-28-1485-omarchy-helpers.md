---
status: approved
issue: 1485
author: olafkfreund
---

# Intent: package Omarchy's two compiled helpers, the speed test client and the native screensaver

## Problem

Omarchy has started shipping parts of the desktop as separate compiled
programs. Arch installs them as their own packages under `/usr/lib`, and
nixarchy has none of them.

- **The network speed test** (`main` and edge). v4.5.0-rc2 added Trigger
  > Tests > Network Speed Test. Its script, `omarchy-network-speedtest`,
  execs `${OMARCHY_SPEEDTEST_BINARY:-/usr/lib/omarchy/speedtest}`, the client
  from [omacom/omarchy-speedtest](https://github.com/omacom/omarchy-speedtest)
  (Go 1.27, MIT, v0.2.1). #1480 shipped rc2 with that row dimmed ("Not
  available on NixOS yet") and the script listed as a `/usr` exception in
  `checks.session`, and filed #1481.
- **The screensaver** (edge only, for now). quattro 79dcccf rewrote
  `omarchy-launch-screensaver` as one line: `exec
  /usr/lib/omarchy-screensaver/omarchy-screensaver "$@"`. That is a native
  Wayland overlay,
  [omacom/omarchy-screensaver](https://github.com/omacom/omarchy-screensaver)
  (Rust, MIT, v1.3.1, built on the `ttfx` crate). quattro also removed
  `bin/omarchy-screensaver` and the three terminal screensaver configs.
  `checks.session`'s `/usr` scan failed on it, so edge run 40677049412 was
  not promoted. That is the second blocker on #1475, after the initramfs
  file #1480 fixed.

The screensaver cannot be handled the speed test's way. It starts on idle
and from Super + Esc, with no menu row to dim. A scan exception would ship
edge with a screensaver that silently never appears, and the next stable
release would inherit it.

## Proposed outcome

- **Network Speed Test works on `main`.** The row is no longer dimmed, the
  panel runs a packaged client, and `omarchy-network-speedtest` is off the
  `/usr` exception list, so the scan proves the path is gone.
- **The screensaver works on edge's quattro.** Idle and Super + Esc start
  the packaged overlay, edge's `verify` passes with no new exception, and
  edge publishes again. That closes #1475.
- Both helpers are pinned to an upstream release tag. Each has an update
  script, the way `pkgs/apps/ttfx.nix` has, so a bump is one command.
- When an Omarchy release includes the native screensaver, it reaches
  `main` through the next edge merge, as rc2's carries did in #1480.
- CI passes on every pull request in the task, and on `main` and edge
  afterwards.
- **Codex and agy work as team members** (owner, 2026-10-28). Both
  implement plan steps through the `handoff` skill, and both review the plan
  and every pull request's diff read-only through the `second-opinion`
  skill. Neither can build here: Codex's sandbox has no nix daemon, and
  headless agy runs no commands. So every build, check and §1 proof is run
  in this session, and their findings are answered in the pull requests.

## Affected users and systems

- `main` and anyone following it or an RC tag: the speed test.
- Edge (`edge`, `edge-candidate`, `omarchy-edge.yml`'s promotion): the
  screensaver.
- `pkgs/apps/` (two new packages), `pkgs/omarchy/default.nix` (launcher
  paths), `flake.nix` (overlay entries), `modules/apps.nix` (the dimmed
  row), `tests/session.nix` (the exception), `data/bin-ledger.nix` (if a
  launcher changes class).
- The public binary cache, only if a helper is added to
  `cache-allowlist.sh`, inside its 2.5 GB budget.

## Constraints

- **Package from source, from the tag**, in nixarchy's own tree. These are
  Omarchy-adjacent programs nixpkgs lacks, like `ttfx`. No prebuilt
  binaries.
- **The scan keeps its teeth.** No `/usr` exception for either helper, and
  the speed test's #1480 exception is removed, not kept "just in case".
- **Mode A unchanged.** Both helpers are runtime dependencies of the
  Omarchy package, not new options. A machine with nixarchy off gains
  nothing.
- **§1 for each probe.** The session check must go red with a helper's path
  pointed back at `/usr/lib`, and green with the package.
- **§2.** A probe goes at the highest layer that can see each helper. The
  screensaver needs a compositor with layer-shell, which `checks.session`
  has, so that is where its probe lives.
- **Edge's carries land through edge's process** (`edge-candidate`, then
  promotion), never by pushing to `edge` directly. §8: no squash merge of
  anything that merges a long-lived branch.
- **§6 build tiers.** Both are package-tier builds, behind
  `vm-host-free.sh`. VM checks run in CI only.

## Open questions

1. **Where each change lands.**
   - **(a)** The speed test as a pull request to `main`. It reaches edge
     through edge's next `main` merge. The screensaver as an edge carry on
     `edge-candidate`, because rc2's launcher has no line for a
     `--replace-fail` to match.
   - **(b)** Both packages on `main` now, the screensaver inert until an
     Omarchy release ships its launcher, and only the screensaver's
     `--replace-fail` on edge.

   I propose **(b)**. One pull request reviews both packages the same way,
   and the edge carry shrinks to one substitution and a probe. The
   screensaver package on `main` costs one unused derivation until the next
   Omarchy release.
2. **Network.** The speed test client talks to `speed.omarchy.org`, as it
   does on Arch, and only when the user opens the panel. I propose keeping
   it as upstream ships it, with no option.

## Decisions (owner, 2026-10-28)

1. **(b)**: both packages on `main`; only the screensaver's `--replace-fail`
   and its probe are an edge carry.
2. **No option**: the speed test client talks to `speed.omarchy.org` only when
   the panel is opened, as upstream ships it.
