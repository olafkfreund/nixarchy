---
status: draft
issue: 1223
author: olafkfreund
---

# Intent: the two demo scenes #816 never landed

## Problem

The site's feature recordings (`docs/img/features/`, sixteen GIFs) show no
service being enabled and no choice between MicroVM templates. Both were in
#816's scope. #816 closed with them named as unverified, and asked for a
smaller issue if they still mattered.

They were started. #816's "pass B" plan (`plan/2026-09-20-816-pass-b-flows.md`,
approved 2026-09-20) and the code for both scenes were committed on a branch
that was never pushed, never recorded and never opened as a PR. GitHub could
not see it, so nothing said the work was missing (the #1098 pattern, AGENTS.md
§12). The work is recovered from a backup bundle as `old/816-pass-b`
(`cd43ef7f`).

## Proposed outcome

- `docs/img/features/services.gif` shows the package manager's Services tab: a
  service ticked, and the line that it writes.
- `docs/img/features/microvm-templates.gif` shows the MicroVM panel's template
  list. It moves across several templates and then creates one.
- Both pass the recorder's own gates (`expects` and frame diversity) on the
  encoded GIF. Each gate is shown refusing a broken recording before it is
  trusted (§1).
- Both GIFs are under 1 MB and referenced from `docs/manual/plugins.md`.

## Affected users and systems

- Readers of the site and manual.
- `tests/demo/default.nix`, which gains two scenes, and the flake's
  `demo-record` attributes that are derived from it.
- `docs/manual/plugins.md` and `docs/img/features/`.
- No module, package or installed system changes.
- p620, where recordings run: each one boots a VM.

## Constraints

- Recording a scene boots a VM, so per §6 it runs only when CI has nothing in
  flight.
- Gates must be honest. `expects` names text that is on screen only when the
  flow really ran, and `minDistinct` is never lowered to let a still picture
  through.
- Demo data only, named `demo-*`.
- The scene file has moved on since 2026-09-20, and there are now nine
  templates rather than eight. So the old commit is a starting point to port,
  not something to cherry-pick blind.
- `demo-record` scenes are `packages`, not `checks`, and no workflow runs them
  (§4). This task does not change that.

## Open questions

1. **Reuse the approved pass-B plan?** Its decisions (two scenes, base node,
   gates against the encoded GIF, a `/dev/kvm` assert for the template scene)
   still hold as far as I can see. I propose the spec carries them over
   unchanged and records only what has moved since: nine templates, and the
   current shape of the scene file. A fresh design is the alternative.
2. **Where the GIFs appear:** in `plugins.md` only, as the old plan said, or
   also on the front page if they earn a place there?
