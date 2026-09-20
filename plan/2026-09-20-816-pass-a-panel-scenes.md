---
status: approved
issue: 816
spec: spec/2026-09-20-816-walkthrough-scenes.md
---

# Plan: pass A — Podman, herdr and the package manager, on one node

Branch `docs/816-walkthrough-scenes`, already carrying the intent and the spec.
One commit per scene, each subject a full sentence (AGENTS.md §8). A deviation
updates this file in the same commit as the code.

## Approved decisions, copied so this file stands alone

- **Three scenes on one `extraNode`**: `virtualisation.podman.enable`,
  `services.boxes.enable`, `virtualisation.diskSize = 16 * 1024`, and the
  `boxes` scene's v4-only SLIRP networking inherited wholesale rather than
  rediscovered — its absence once cost 900 s of silence against a registry that
  resolved AAAA first.
- **`online = true`**: a container image pull needs the real network, so
  `demo-record` runs these drivers outside the sandbox, encoding and gating with
  the same tools as every sandboxed scene.
- **Honest gates.** `expects` must name something only on screen when the panel
  really ran, and `minDistinct` is not lowered to admit a still picture — the
  `plugin` scene's 0-of-11 failure is the precedent.
- **Demo data only**, named `demo-*`, created and removed inside the VM.
- GitHub Actions and GitLab Pipelines are **not** in this pass; the spec settles
  them as stills because a motionless "authenticate first" panel cannot clear
  the diversity floor honestly.

## Steps

1. **`tests/demo/default.nix`: the shared node.** Add `panelNode` beside the
   existing definitions — podman, boxes, 16 GB disk, DHCP on eth0, nameserver
   10.0.2.3, IPv6 off — with the comment saying which of those are inherited
   from `boxes`' hard-won networking and why.
   → verify by `nix run .#demo-record -- podman` reaching a desktop at all;
   a node that does not boot fails here rather than inside a scene.

2. **`segments.podman`, and the `podman` scene.** Create two `demo-*` containers
   and one volume in the VM, open the panel, move across the Containers /
   Images / Volumes tabs, filter, and stop one container so a row visibly
   changes state.
   `expects`: the panel's own heading and a `demo-` container name.
   `minDistinct`: 4 — the tab moves make this the most varied of the three.
   → verify red first by recording with `nixarchy.podman` disabled: the gate
   must refuse on `expects`, not merely produce a worse GIF.

3. **`segments.herdr`, and the `herdr` scene.** herdr's widget reports what each
   coding session is doing. With no agent in this pass, the scene records the
   **empty state and a session appearing**: start a `demo-` session with the
   `herdr` CLI, show the bar widget change, open the menu.
   `expects`: the widget's own text and `demo-`.
   `minDistinct`: 3.
   → verify red first by withholding the session: an unchanging widget must
   fail the floor, which is the same shape as `plugin`'s first failure and is
   the point of the floor.
   → **if the empty-to-one-session transition is not visually legible**, this
   scene becomes a still and the page says so (spec, §2's rule applied).

4. **`segments.pkg`, and the `pkg` scene.** The package manager panel: open,
   type a filter, cross the Apps / Services / Options tabs, tick one app, show
   the queue count change from "nothing queued". **Rebuild the index first** —
   today's fresh-install capture showed `index stale — R to rebuild` in the
   footer, which would be the first thing a reader sees.
   `expects`: `nothing queued` before, the queued count after, and the filter
   term.
   `minDistinct`: 4.
   → verify red first by recording without the tick: the queue text never
   changes and the `expects` for the queued state must fail.

5. **Encode and gate all three.** `tests/demo/encode-gif.sh` at 4 fps / 900 px,
   palette capped where needed, each under 1 MB. Quote each GIF's diversity
   number and OCR hits.

6. **`docs/`: publish.** The three GIFs into `docs/img/features/`, referenced
   from `docs/manual/plugins.md` and the front page. Anything shown still
   rather than moving is said so in words.

7. **PR.** Against `main`, `Refs #816` (the issue outlives pass A), linking
   intent, spec and this plan, carrying the red output for each scene and the
   measured sizes.

## Tests

| Command | Expected |
| --- | --- |
| `nix run .#demo-record -- podman` | GIF under 1 MB, OCR finds a `demo-` container, diversity ≥ 4 |
| the same with the panel disabled | gate refuses on `expects` |
| `nix run .#demo-record -- herdr` | OCR finds the widget text and `demo-`, diversity ≥ 3 |
| the same with no session started | gate refuses on the diversity floor |
| `nix run .#demo-record -- pkg` | OCR finds `nothing queued` and the queued state, diversity ≥ 4 |
| the same without the tick | gate refuses on the queued-state `expects` |
| `nix fmt -- --ci`, statix, deadnix | clean |

Every run waits for `gh run list` to report an empty queue (§6): these are VM
recordings on the box that hosts all four runners.

## Rollback

- **Before merge:** drop the branch; nothing outside it changed.
- **After merge:** revert. No check depends on these scenes — `demo-record` is
  run by hand, which the spec names as the standing weakness rather than
  pretending otherwise.
