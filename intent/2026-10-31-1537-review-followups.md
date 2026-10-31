---
status: approved
issue: 1537
author: olafkfreund
---

# Intent: follow-ups from the 2026-10-31 review

## Problem

A review of #1526, #1534 and #1535 and of the day's runs found four problems.
Each was checked against the code or a run log. The review used a Claude
workflow, with an adversarial verifier on each finding, plus Codex
(gpt-6-sol) and agy (model not reported).

1. **One broken package throws away every bump.** `update.yml` runs
   `nix run .#update` under `bash -e`. That app exits 1 when any updater
   fails, and the build step is a single `nix build` over every attribute.
   On 2026-10-31 owe 0.2.13 failed its `postPatch` (run 41171151925), and
   nine other packages' bumps were discarded. No pull request was opened.
   The red run is the only signal, and it is the signal AGENTS.md §4 says
   stalls for good.
2. **Edge's README holds a number that main cannot compute.**
   `readme-counts.sh` derives "**N of 558 scripts**" from the pinned Omarchy
   tree. `omarchy-edge.yml` never runs it, so when quattro moved,
   `sync/133-edge` went red and a human hand-edited edge's README to 41
   (#1528). Main's tag pin computes 40. The next edge→main merge carries 41
   onto main, and the required `omarchy` check goes red. This is the trap
   §8 already names: edge carries must hold under both pins.
3. **owe 0.2.13 can kill its own late-starting renderer.** Upstream replaced
   the 1 s start wait we carried at 30 s (#1153, #1437). It now waits 7 s,
   then lets a slow renderer start late. During that late window
   `owed_supervisor_send` refuses every command (supervisor.c:236). A failed
   park makes `process_shell_handoff` call `owed_supervisor_stop`
   (main.c:309-324), so a video set within the 2 s park window, or an intro
   prepared at login, kills a renderer that was about to come up. Only a
   renderer slower than 7 s is affected. CI's software-GL VMs take about
   11 s, and so do slow boards; a normal GPU starts in under a second.
   `checks.coexist` passed on 0.2.13 at attempt 15 of 24, with owed
   repeatedly logging "shell background enable/disable failed".
4. **The keyring note promises more than it delivers (#1526).**
   - The lock screen opens only the keyring collection named `login`.
   - On a fresh autologin install, an app such as Chromium that runs before
     the first lock makes the user create a separate default keyring. The
     lock screen never opens that keyring, so the prompt returns on every
     boot.
   - `passwd` has no pam_gnome_keyring, so after a password change the
     keyring keeps the old password.
   - The timing comment at `tests/coexist.nix:183` is also stale. It says
     tries 10–11 and "~2x headroom"; recent runs land at 9–16 of 24.

## Proposed outcome

- A failing updater or build in `update.yml` still opens the pull request
  for the packages that did build. The pull request names the broken
  package, and the run still ends red.
- Edge's README counts are always what edge's own pin computes, written by
  edge's workflow, never by hand. An edge→main merge can't carry a count
  that main doesn't compute.
- owe gives a slow renderer the time it needs before anything can stop it,
  as it did before #1535. On a normal GPU nothing changes.
- The security manual says when the lock screen unlocks the keyring and when
  it doesn't, and what to do in each case. The coexist comment states the
  timings measured now.

## Affected users and systems

- `.github/workflows/update.yml` and `.github/workflows/omarchy-edge.yml`:
  CI gates, so a human merges these (§11).
- `pkgs/apps/owe.nix`: every machine with video backgrounds, and
  `checks.session` and `checks.coexist`.
- `docs/manual/security.md` and `tests/coexist.nix`: a comment only.
- No host deploys.

## Constraints

- Workflow edits are CI-gate changes. They are proposed in a pull request
  and merged by a human, never by an agent (§11).
- owe stays at upstream source. A fix uses upstream's own `#ifndef` hooks
  (`RENDER_START_MS`) rather than a `substituteInPlace`, so it can't
  silently stop matching on the next bump, which is what broke 0.2.13.
- Nothing is filed upstream (omacom/owe) without the owner asking (§11).
- Each group is its own pull request, so one blocked group doesn't hold the
  rest. #1537 closes only when all four have merged (§12).
- Every check that is changed or added must be shown failing first (§1).

## Open questions

1. **update.yml policy.** Opening a pull request that contains a known-broken
   bump changes what the job is willing to propose. Alternatives:
   - Keep the bumps that built, and revert the broken package's file before
     the pull request is opened.
   - Open the pull request with everything and list the failures in it.

   Reverting is safer for users but more code. Which do you want?
2. **owe.** Choose one:
   - Restore the 30 s blocking wait with
     `NIX_CFLAGS_COMPILE = "-DRENDER_START_MS=30000"`. This is the old
     behaviour, carried with no source patch.
   - Leave upstream as is and accept the CI-only risk.

   Do you want the bug reported upstream as well? That needs your go-ahead.
3. **Edge counts.** Choose one:
   - Run `readme-counts.sh --fix` in `omarchy-edge.yml`. This is the smallest
     change and mirrors `omarchy.yml`.
   - Round the Omarchy-derived figures in the README so they hold under
     both pins. That would need `readme-counts.sh` to stop checking them.
