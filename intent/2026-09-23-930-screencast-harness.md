---
status: approved
issue: 930
author: olafkfreund
---

# Intent: recording a desktop becomes a script, not an afternoon

## Problem

Every moving picture on this site was made one of two ways, and both are wrong
for what we now need.

**The VM way is automated and produces the wrong artefact.** `tests/demo/` is
genuinely good: twelve segments, ten scenes, a frame gate that OCRs samples and
refuses a recording with too little movement, and a flake attr per scene created
by construction so the list cannot fail open. It captures qemu screendumps at
1280x800 and encodes 900px GIFs at 4 fps, under 1 MB. That is exactly right for
a manual page and cannot be a front page hero or a Reddit post.

**The real-desktop way is not automated at all.** `docs/AGENTS.md` prescribes
`wl-screenrec -g "<x>,<y> 2304x1440"`, composition onto
`docs/screenshots/00-desktop.jpg`, and the same frame gate afterwards — as
prose. There is no script. `flatsnap.gif`, `plugin-browser.gif`,
`github-actions.gif`, `nixi.gif` and `devenv-bound.gif` were each made by a
person doing it by hand, once, and none of them can be reproduced by running
anything.

So the cost of a new recording is an afternoon and the owner's attention, and
the cost of *re-doing* one after a UI change is the same afternoon again. That
is why `docs/img/features/` drifts: `AGENTS.md` §4 records a scene that went on
publishing a GIF of a command that had been deleted, with `main` green.

**And nixarchy has no video at all.** Not on the front page, not anywhere. The
one video that exists is an ai-mirror recording hosted on someone else's release
page and linked, not embedded.

## Proposed outcome

Recording a real nixarchy desktop is a command, and the desktop it borrowed is
provably given back.

Observable:

- a maintainer runs one command on a machine with a live session and gets a
  master recording, without typing into that session by hand;
- the shot list is **data in the repository**, so a beat can be added, removed
  or re-timed by editing a file rather than by re-performing a take;
- after any take — including one that crashed halfway — the machine's
  `~/.config/omarchy/shell.json` is byte-identical to what it was before, and
  something *checked* that rather than assumed it;
- the existing frame gate accepts the result, so a recording that shows nothing
  is refused exactly as a GIF is today;
- the first output is a 60-second promo in two cuts: silent for the front page,
  captioned with a music bed for social.

The measure of success is the **second** recording, not the first: if the next
demo still takes an afternoon, this failed.

## Affected users and systems

- **Whoever records next.** Today that is one person with the tacit knowledge.
- **`tests/demo/`** — the new work sits beside it and should borrow its
  vocabulary (`shot`, `user`, `terminal`) rather than invent a second one.
- **`tests/demo/verify-frames.sh`** — the gate, which takes a GIF today.
- **`docs/`** — the Pages site. It has never embedded HTML5 video; every image
  is Jekyll-markdown. A hero video is a house-style change, not just a file.
- **A real machine with a live session**, whose bar and plugin enablement are
  temporarily rearranged. This is the part that can do harm.
- **Nobody's installed machine.** Nothing here ships in a closure or changes a
  default. If a user can observe this change, it has gone wrong.

## Constraints

- **The desktop must come back exactly.** Not "restored on the happy path" —
  after an interrupt, a failed beat, or a dropped SSH connection. A harness
  that leaves somebody's bar rearranged has cost more than it saved.
- **A recording must not leak.** `docs/AGENTS.md` is explicit and was written
  from an incident: translucent windows show what is behind them, and #764
  caught an email verification code that way. The Herdr panel lists real
  session names. This is a correctness requirement, not a tidiness one.
- **Nothing in CI builds `tests/demo/`** (AGENTS.md §4). Whatever is added
  inherits that, and must say so rather than read as covered.
- **The gate must stay honest.** Relaxing `verify-frames.sh` so a video passes
  would be the §1 failure — a check retargeted to agree with its subject.
- **No false claims in the artefact.** A promo that says something the software
  does not do is worse than no promo.
- **The house style exists and is argued for.** `docs/AGENTS.md`: whole desktop
  at 16:10, full container width, panels at 64–80% of frame because smaller
  ones fail the OCR gate honestly. A video departs from 16:10 by being 16:9,
  and that departure should be stated rather than slipped in.

## Open questions

1. **Does the gate belong on video at all?** `verify-frames.sh` samples frames,
   measures RMSE between consecutive samples and OCRs them. A 60 fps video has
   far more frames and far smaller differences between neighbours, so the
   2% RMSE floor — measured against a *terminal holding still* — may be the
   wrong threshold in a medium where everything moves slightly. Either the
   sampler works on time rather than frame index, or the gate is honestly
   declared GIF-only and the video gets a different check.

2. **How much of the harness is nixarchy's business?** Prepping a desktop for
   the camera — enabling panels, hiding third-party widgets, stay-awake,
   dismissing notifications — is useful far beyond recording. It could be a
   `screencast-prep`, or it could be the honest name for something more general
   like a presentation mode that users would also want. The second is a
   feature; the first is a tool. I have specified the first.

3. **Does a hero video belong on the front page, or a poster that links to it?**
   Autoplaying video is the modern pattern and it is also the thing people turn
   off. The site is currently text and stills that load instantly.

4. **Which machine is the reference desktop?** The one available has a single
   1920x1080 panel, which is below the 2304x1440 the house style prescribes for
   recording, and its nixarchy is behind `main`. Recording there is possible
   today; recording something that matches the site's other imagery is not.
