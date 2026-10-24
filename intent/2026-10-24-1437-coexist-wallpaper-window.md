---
status: draft
issue: 1437
author: olafkfreund
---

# Intent: coexist waits as long as the desktop needs to draw, and owe stops killing a renderer that is about to start

## Problem

`checks.coexist` failed on `main` 6d02d181 (run 40081835769):

    AssertionError: the Omarchy session came up but never looked like its wallpaper (delta 304 after 60s)

The commit only bumped `owe`, and the same pattern predates that bump.

**The check has no margin.** `tests/coexist.nix:180` starts comparing the
screen to the wallpaper right after the session starts. It does 12 tries,
5 s apart. In every one of 12 runs over four days, the wallpaper first showed
on try 10 or 11, and the failure missed by one. `checks.session` has the same
loop (`tests/session.nix:2242`), but it runs late in its script and passes on
try 0.

**Why the desktop takes that long in the VM.** owe draws the wallpaper through
a hand-off. Here is the timeline from the passing run, in guest uptime:

| time | event |
|---|---|
| 36.5 s | `owed` starts |
| 38.6 s | it asks the Omarchy shell to draw the still, and the shell is not up yet |
| 38.6–47.5 s | `owed` starts its own renderer instead, under llvmpipe |
| 47.5 s | the renderer reports ready, but the screen stays black |
| 74 s | the shell accepts the hand-off |
| ~85 s | the wallpaper appears |

The failing run went worse:

| time | event |
|---|---|
| 53.81 s | the renderer has taken 10.6 s. `owed` logs `owe-render socket never appeared` and kills it |
| 53.88 s | the renderer logs "ready", 70 ms too late |
| 80 s | the shell hand-off fails again: "omarchy-shell is not responding" |
| ~98 s | the check ends with the screen still black |

**Our own carried patch made that kill possible, and its reason is out of
date.** `pkgs/apps/owe.nix:93` (#1153) raises owe's renderer wait from 1 s to
10 s. Its comment says start-up under llvmpipe "takes about 1.3 s". It now
takes 8.9 s (passing run) and 10.6 s (failing run). The wait also counts only
its own sleeps, not elapsed time.

## Proposed outcome

- `checks.coexist` waits long enough for the desktop to draw in this VM, with
  stated headroom. It still fails on a black desktop.
- owe no longer kills a renderer that is still starting, at the start-up times
  measured here.
- Upstream owe has a report of the timeout and the black-fallback renderer,
  if you approve filing it.

## Affected users and systems

- `tests/coexist.nix`, and the CI `system-checks` job that runs it.
- `pkgs/apps/owe.nix`: owe's renderer wait. This affects every nixarchy
  machine with owe on, which is the default. It only matters on a machine
  where the renderer starts slowly: software GL, or a cold first start.
- Upstream `omacom/owe`. It is not ours, and filing there needs your go-ahead
  (§11).

## Constraints

- The check keeps testing pixels, not owe's log lines or the shell's IPC.
  Both reviewers agree on this.
- No retry-until-green (§10). The new window comes from the measurement and
  is said in the code.
- §1: the wider loop still has to be seen failing on a black desktop.
- A change to a carried patch says what it measured and drops when upstream
  fixes it. That is the same rule as the patch's existing comment.

## Open questions

1. **coexist window.** I recommend 24 tries (120 s), about twice what the
   slowest passing run needed. Fix the "after 60s" message to match.
   - Codex and agy both said this.
   - It costs nothing when the check passes, because the loop stops at the
     first match.
2. **The carried owe wait.** Should it go from 10 s to 30 s, with the comment
   giving the new measurement?
   - **Recommendation: yes.** It is our patch, its stated reason no longer
     holds, and the failing run is the measured case.
   - On a real machine with a GPU, the renderer starts in about a second, so
     this only changes slow starts.
   - agy recommended this. Codex said it needs its own decision, which is
     this question.
3. **Report upstream?** One `omacom/owe` issue would cover two things: the
   wait counts sleeps rather than wall time, and the renderer paints black
   under llvmpipe while it reports ready.
   - **Recommendation: yes, but only with your go-ahead.** I would draft it
     here, and you file it or tell me to.
