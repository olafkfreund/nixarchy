---
status: approved
issue: 1359
author: olafkfreund
---

# Intent: owe 0.2.11 with the handoff fix, instead of holding 0.2.10

## Problem

owe 0.2.11 parks the renderer in the middle of a still → video handoff when
the video is set within 2 s of returning to a still. The video never shows
(#1359, reported upstream as omacom/owe#18). #1360 holds owe at 0.2.10 to
stop it. That works, but it also gives up 0.2.11's improvement, which is no
blank frame while a video takes over.

The owner's machines run nixarchy from `main`. p620 runs owe 0.2.11 today,
because `/etc/nixos` pins nixarchy at c335cad7, and razer gets the same on
its next switch. The owner wants the fixed behaviour there, not the older
version.

## Proposed outcome

- nixarchy ships owe 0.2.11 with a one-line patch: the pending park is
  cleared when a handoff starts (`app->shell_stop_at_ms = 0;` beside
  `app->handoff_pending = true;` in `owed_app_apply_policy()`), exactly as
  proposed upstream.
- `checks.session` passes on it, including the still → video switch about
  1.5 s apart that exposed the bug.
- The patch is dropped at the first owe release that contains the fix, and
  the file says so.
- p620 and razer get it through the owner's normal `/etc/nixos` nixarchy
  bump. Deploying is the owner's step, and it is not part of this change.

## Affected users and systems

- `pkgs/apps/owe.nix` (version back to 0.2.11, plus the patch) and a new
  patch file beside it.
- Everyone with owe enabled (installer-managed machines turn it on by
  default).
- p620 and razer through `/etc/nixos`. A p620 switch restarts the CI runners
  (CLAUDE.md §6), so it is announced and timed by the owner.

## Constraints

- CLAUDE.md §11: a fix to upstream behaviour belongs upstream. This carries
  one only because the owner asked for 0.2.11's behaviour now. omacom/owe#18
  is the way out, and the patch must fail loudly once upstream has applied it
  (`patch` refusing an already-applied hunk does that).
- §1: the session check must fail on 0.2.11 without the patch and pass with
  it. The three red runs already logged are the "without", and this PR's run
  is the "with".
- Ordering with #1360: whichever merges second replaces the other. #1360 can
  merge first (0.2.10 now), and this then moves back to 0.2.11 with the patch.

## Open questions

- **Keep #1360 in the meantime?** I propose yes. It makes `main` green within
  the hour, and this follows through the gates.
- **Does the daily bump's `updateScript` keep the patch** when owe 0.2.12
  arrives? It rewrites version and hash by position, and the patch list
  survives. If 0.2.12 contains the fix, the patch fails to apply and the bump
  goes red, which is the signal to drop it.
