---
status: draft
issue: 1223
spec: spec/2026-10-09-1223-service-template-scenes.md
---

# Plan: the two demo scenes #816 never landed

Branch `docs/1223-service-template-scenes`, worktree `/mnt/data/vmtest/wt-1223`.
The old code to port is the local branch `old/816-pass-b` (`cd43ef7f`); read it
with `git show cd43ef7f -- tests/demo/default.nix`. One commit per step.

## Approved decisions, copied so this file stands alone

- **Two scenes, `services` and `microvm-templates`**, recorded on the VM
  recorder: `nix run .#demo-record -- <scene>`, from the repo root. It writes
  `docs/img/features/<scene>.gif` and leaves sampled verify frames beside the
  build result. Look at those frames. The gate is a floor, not a reviewer.
- **No package scene.** `install.gif` and `pkg.gif` already record it.
- **The template scene stops at the choice.** It does not create a VM;
  `microvm.gif` already films that.
- **Honest gates.** `expects` names text that is on screen only when the flow
  ran. `minDistinct` is 4 and is never lowered.
- **Gates are read off the encoded GIF** (900 px, 96 colours), not guessed.
  The `pkg` scene's comment (`tests/demo/default.nix`, in `sceneDefs.pkg`)
  records the trap: "1 change queued" OCRs as "1 change queved" at 900 px,
  while "enabled bitwarden" reads back exactly.
- **Steps are chosen for repaint**: a tab switch or a list redraw, not a
  cursor moving one row.
- **Base node first.** The spec says no `panelExtras`. `sceneDefs.pkg` uses
  `extraNode = panelExtras; online = true;` and does not say why. If
  `services` cannot load the package manager on the base node, take pkg's
  settings and record that change here, in the same commit (deviation rule).
- **Demo data only**, named `demo-*`.
- **Fix `docs/manual/sandboxes.md:19`**, whose caption describes a CLI session
  that `microvm.gif` does not contain.

## Steps

1. **`tests/demo/default.nix`: the `services` scene.**
   - Add `segments.services` after `segments.pkg` (it starts at line 749 and
     ends before `plugin = ''` at line 811). Port the body from `cd43ef7f`:
     toggle `nixarchy.pkg` by IPC, `shot`, press `l` once (Apps → Services,
     `PkgModel.qml:28`), `shot`, press `j` `j` then `spc`, hold `shot` for 6,
     then `esc`.
   - Add `sceneDefs.services` after `sceneDefs.pkg` (line 998), with
     `minDistinct = 4;` and `extraNode = { };`. Its `expects` is
     `"Services"` plus a placeholder.
   - First recording: run it, open the verify dump, and read the line that
     appears only after the tick (most likely `enabled <id>`, as in pkg). Set
     the second `expects` to that line, as a regex that does not name the
     service: the row the cursor lands on is a fact about catalogue order.
   → Verify: the recording passes. Then remove the `spc` line, re-record, and
   confirm it is refused **on `expects`**, not on diversity. Capture that
   output, restore the line, and re-record green.
   Traps: §5 `git checkout -- <path>` restores the index, not the commit —
   restore the break with `git checkout HEAD -- tests/demo/default.nix`.
   §1: prove the break landed (`git diff`) before reading a green result.
   §5: a heredoc in an indented Nix string reindents the file, so use none.
   Run `nix fmt` and read `git diff --stat` afterwards, because the
   `nixpkgs-fmt` hook can rewrite the file.

2. **`tests/demo/default.nix`: the `microvm-templates` scene.**
   - Add `segments.microvm-templates` after `segments.services`, ported from
     `cd43ef7f`:
     - assert `/dev/kvm` in the guest, and fail loudly without it;
     - open the create form with
       `omarchy-shell shell toggle nixarchy.microvm '{"create":true}'`;
     - `shot`, then three rounds of `down` + `shot`, then `esc`.
   - Fix the old comment's "carries eight": there are nine templates now, and
     the picker shows the first six (`CreateForm.qml:73`).
   - Add `sceneDefs.microvm-templates` with `minDistinct = 4;` and
     `extraNode.virtualisation.qemu.options = [ "-cpu host" ];`. Take the two
     `expects` names (old: `python`, `node`) from the first verify dump; they
     must not be substrings of each other.
   - Check that the MicroVM panel is visible on the base node at all. If it
     is gated on a service, enable that service in `extraNode` and note it
     here.
   → Verify, red-first twice. First, remove the `down` presses: the second
   name never appears, so `expects` refuses. Second, remove `-cpu host`: the
   scene's own assert fails with its message. Capture both, restore, and
   re-record green.
   Traps: the same as step 1.

3. **`docs/`: publish and correct.**
   - `docs/manual/plugins.md`: under Package manager (near line 59), add
     `services.gif`. Under MicroVMs (near line 158), add
     `microvm-templates.gif`. Each needs alt text that says only what its
     frames show; check it against a contact sheet
     (`magick <gif> -coalesce f-%02d.png`, then `magick montage`).
   - `docs/manual/sandboxes.md:19`: rewrite the alt text to describe what
     `microvm.gif` shows, which is the MicroVMs panel streaming the
     `demo-shell` build until it runs in the background, and nothing else.
   → Verify: each GIF is under 1 MB (`ls -l`); every image path resolves;
   `nix fmt -- --ci`, `statix check .` and `deadnix --fail .` are clean.

4. **PR.** It closes #1223 (`Closes #1223`). It links all three artifacts,
   carries each red-then-green output and the GIF sizes, and says which steps
   the `coder` agent did, if any.

## Tests

| Command | Expected |
| --- | --- |
| `nix run .#demo-record -- services` | under 1 MB; both `expects` lines found; diversity ≥ 4 |
| … with `spc` removed | refused on `expects` |
| `nix run .#demo-record -- microvm-templates` | under 1 MB; both names found; diversity ≥ 4 |
| … with the `down` presses removed | refused on `expects` |
| … without `-cpu host` | the scene's `/dev/kvm` assert fails |
| `nix fmt -- --ci`, statix, deadnix | clean |

Every recording is a VM check under the §6 tiers. It starts only when
`gh run list --limit 8 --json status -q '[.[]|select(.status!="completed")]|length'`
prints `0`, and only one recording runs at a time. A recording that sits at
0% CPU past its timeout is wedged: kill it by PID, never by process name.

## Rollback

Before merge, drop the branch. After merge, revert the squash commit, which
removes the two scenes, both GIFs and the caption fix together. No check
depends on these scenes.
