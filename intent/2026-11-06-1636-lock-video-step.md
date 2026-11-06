---
status: approved
issue: 1636
author: x
---

# Intent: checks.session's lock-screen video step stops failing on a slow host

## Problem

`checks.session` asserts that the locked screen holds a still rather than playing the video. On #1634 (run 42072346082) it failed: shot 0 was `#0101FB`, and shots 1 to 5 were all `#ED0C0C`. The screen changed once and then held still, which is what a still looks like, and the check read it as playback. The same commit passed locally, with spread 0.

The likely cause, read and not reproduced: `settle` accepts any saturated frame, and the video's last desktop frame is saturated too. Neither lock-status wait above it says the lock surface has drawn. So on a slow host shot 0 can measure the handoff. The host's load was about 14. Codex and agy both read the code as allowing this. Neither could confirm that the blue frame really was the desktop's.

A check that fails on a healthy machine costs a re-run, and it teaches people to re-run, which hides a real regression (§10).

## Proposed outcome

The handoff from desktop to lock surface cannot fail the playback assertion, and playback seen across one full video loop after the handoff still fails it. The step's other refusals stay: no saturated frame in time, or too few readings before the screen blanks.

## Affected users and systems

CI and anyone running `checks.session`. Nothing that ships changes.

## Constraints

- Must still fail for the regression it exists to catch (#15289, #1447). §1 requires that to be shown.
- It must not simply widen the 60 spread or drop readings by position alone without saying why: either could hide slow playback.
- `session` is a VM check, so it runs by §6's tier.
- The lock screen blanks about 5 s after locking, so waiting out the handoff spends the time a full loop needs (agy). The spec has to fit both, or wake the screen, inside the existing six-reading floor.
- The race cannot be forced on demand, but the recorded failure (`#0101FB` once, then `#ED0C0C`) and a playing sequence can both be fed to whatever decides (agy), and a build where the lock screen really plays is the §1 break.

## Open questions

None for you. The spec decides how the step recognises the end of the handoff.
