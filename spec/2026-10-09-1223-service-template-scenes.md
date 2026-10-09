---
status: draft
issue: 1223
intent: intent/2026-10-09-1223-service-template-scenes.md
---

# Spec: the two demo scenes #816 never landed

## Design

Two new scenes in `tests/demo/default.nix`, recorded with `nix run
.#demo-record -- <scene>` on the VM recorder, as pass A's `pkg.gif` was. They
are ported from `old/816-pass-b` (`cd43ef7f`), not cherry-picked.

### Carried over from the approved pass-B plan (2026-09-20)

- **Base node, no `panelExtras`.** Neither scene needs podman or boxes.
- **Honest gates.** `expects` names text that is on screen only when the flow
  really ran. `minDistinct` is never lowered to let a still picture through.
- **Steps are chosen for repaint**, not for count. A tab switch or a list
  redrawing clears the 2% RMSE floor; a cursor moving one row does not.
- **Gates are written against the encoded GIF** (900 px, 96-colour palette),
  not the capture. Small text that OCR reads at 1280 px comes back wrong.
- **Demo data only**, named `demo-*`, and removed by the scene.
- **No package scene.** `install.gif` and `pkg.gif` already record adding a
  package.

### Scene 1: `services`

1. Open the package manager by IPC (`omarchy-shell shell toggle nixarchy.pkg`).
2. Press `l` to move one tab to the right. The tabs are, in order: Apps,
   Services, Selection, Options, Drafts, Flakes (`PkgModel.qml:28`).
3. Move down onto a service row and press Space to tick it. Space toggles only
   rows that have two states (`Menu.qml:269`).
4. Hold on the result, then press `esc`.

`expects`:
- "Services" (the tab name), and
- one line that appears **only after the tick**.

**This line differs from the old branch.** That branch gated on
`enabled [a-z0-9-]+ in`, which is what `nixarchy-service-enable` prints. But
the panel's footer is `pkg.message`, which is set from the adapter's JSON
(`OptionForm.qml:125`, `PkgModel.qml:249`), not from the script's stdout. So
whether that text ever reaches the screen is unverified. The second `expects`
line is taken from a captured frame of the first recording, not guessed.
Pass A lost four rounds to guessed gate text.

`minDistinct`: 4.

### Scene 2: `microvm-templates`

1. Assert `/dev/kvm` exists in the guest, and fail loudly if not. Without it,
   a template cannot start, and the scene would film a list.
2. Open the create form by IPC
   (`omarchy-shell shell toggle nixarchy.microvm '{"create":true}'`), which
   `Menu.qml:16` documents.
3. Press Down three times through the template picker. `CreateForm.qml:219`
   moves `listIndex` through the list, and the picker shows the first six of
   the nine templates.

`expects`: two template names that are not substrings of each other (the old
branch used `python` and `node`; re-checked against the encoded GIF).

`minDistinct`: 4.

**It stops at the choice, and does not create a VM.** The approved intent says
"then creating one". This narrows it, deliberately. Creating a VM runs a guest
build that `microvm.gif` already films end to end, so it would be the same
duplication pass B rejected for the package scene. The template choice is the
one thing no published picture shows. If you want creation in the scene too,
say so here: it costs an online recording (`online = true`) and the microvm
scene's 8 GB node.

### Docs

- `docs/manual/plugins.md`: `services.gif` under Package manager, and
  `microvm-templates.gif` under MicroVMs, each with alt text that describes
  only what is in its frames.
- **Fix a false caption found while researching.** `docs/manual/sandboxes.md:19`
  describes `microvm.gif` as "`nixarchy vm templates` listing shell, python,
  podman and persistent; `vm create demo --template shell`; `vm list`; then
  `vm run` booting the guest". The published GIF (from #842, retouched in #900)
  shows the MicroVMs panel streaming one `demo-shell` build, and none of that.
  The caption is rewritten to match the frames. The GIF is not re-recorded.

## Alternatives rejected

- **Cherry-pick `cd43ef7f` as is.** The scene file has moved on since
  2026-09-20, and the old gate rests on an unverified footer string.
- **Record on a real desktop with `tests/demo/screencast/`.** That is
  repeatable now (#930), but every other panel GIF here comes from the VM
  recorder. A VM needs no desktop to be borrowed or restored, and it cannot
  catch a real machine's data in frame.
- **Re-record `microvm.gif` to show the templates as well.** It is published
  and correct apart from its caption. Re-recording a working picture to
  combine two claims gives a longer GIF that is harder to gate.
- **Make these scenes run in CI.** `demo-record` scenes are packages that no
  workflow runs (AGENTS.md §4). That is a standing weakness, and fixing it is
  a separate decision about CI gates (§11).

## Risks

- **Nested KVM in the recording VM.** `-cpu host` passes it through on p620.
  If it is missing, the scene's own assert stops the recording, which is the
  point of that assert.
- **Catalogue order.** Which service the cursor lands on depends on the order
  of `data/services.nix`. The gate must not name a service, or it breaks the
  day somebody adds one.
- **Templates beyond the first six** (nine exist) are not shown by the
  picker. The scene does not claim they are.
- **CI load.** Each recording boots a VM on p620, so it runs only when
  `gh run list` shows nothing in flight (§6).
- **No user-facing behaviour changes**, so there is no coexistence surface
  (§14).

## Verification

| What | Expected |
| --- | --- |
| `nix run .#demo-record -- services` | GIF under 1 MB; OCR finds both `expects` lines; diversity ≥ 4 |
| the same with the Space press removed | refused on `expects`, not on the diversity floor |
| `nix run .#demo-record -- microvm-templates` | GIF under 1 MB; OCR finds both template names; diversity ≥ 4 |
| the same with the Down presses removed | refused, because the second name never appears |
| the same with no `/dev/kvm` passed through | the scene's assert fails, loudly |
| `nix fmt -- --ci`, statix, deadnix | clean |
| the two new images in `plugins.md`, and the `sandboxes.md` caption | each describes only what its frames show; checked against a contact sheet of each GIF |

The failing output of each red proof goes in the PR (§1).
