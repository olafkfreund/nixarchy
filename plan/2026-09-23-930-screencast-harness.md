---
status: draft
issue: 930
spec: spec/2026-09-23-930-screencast-harness.md
---

# Plan: recording a desktop becomes a script, not an afternoon

This plan is self-contained: it carries every approved spec decision, and the
four corrections that came out of a cross-model review of the approved spec
(OpenAI `gpt-5.6-luna` via codex, and Google via agy, model not reported —
2026-09-23). The review's findings are carried here on the owner's instruction
rather than by re-opening the spec.

## Decisions

From the spec:

- **Four commands** under `tests/demo/screencast/`, `writeShellApplication`,
  exposed as flake apps beside `demo-record`.
- **The shot list is data** (`shots.nix`), driven with `hyprctl dispatch exec`
  and `omarchy-menu summon`, the two verbs `tests/demo/default.nix` already
  uses.
- **Capture** with `gpu-screen-recorder` to MKV; **edit** with scripted ffmpeg
  `filter_complex`, never kdenlive.
- **Two cuts from one master**: the clean one has no audio stream at all; the
  social one takes its captions from the same `shots.nix` that drove the
  recording, so captions cannot drift from beats.
- **Full tour, twelve plugins, 60s**; record on razer over SSH; end card claims
  only what is true (an agent drove it, not that a nixarchy plugin did).
- **Front page**: `<video>` with `poster` and `preload="metadata"`. No autoplay
  until the owner has seen it.

**The twelve-plugin accounting, stated because the spec left it implicit** and
a reviewer consequently miscounted it as nine:

| in a named beat | in the montage |
|---|---|
| `pkg` (Search, 0:16), `plugin-browser` (0:22), `rebuild` (Apply, 0:10) | `microvm`, `podman`, `distrobox`, `devenv`, `github-actions`, `gitlab-pipelines`, `herdr`, `flatsnap`, `ai-mirror` |

Three plus nine. `shots.nix` carries this table as a comment, and step 9
asserts the count mechanically so it cannot rot.

### The four corrections

**A. The gate runs on the raw master, and partitions OCR per beat.**
Two defects, both verified in the tree rather than taken on trust:

- `verify-frames.sh:137` builds **one aggregated `ocr.txt`** and greps each
  `--expect` against the whole of it. An expectation therefore proves the text
  appeared *somewhere*, not in its beat. Carried over unchanged, a recording
  that never opened the Plugin Browser would still pass because the words are
  on screen at 0:22's caption or in the menu earlier.
- If the gate ran after editing, the `drawtext` **caption itself satisfies the
  expectation**. The check would be verifying its own subtitle.

**B. Restore covers everything prep touched — so prep touches less.**
`prep` as specified also sets the theme, runs `stay-awake`, dismisses
notifications and **closes every window**, and none of that is in the snapshot.
Closing somebody's windows is not recoverable at any price, so the fix is to
narrow prep rather than to grow restore. Enabling a plugin also writes
`~/.local/state/nixarchy/enabled-once/<id>` (`modules/home.nix:1764`), outside
the snapshot.

**C. Restore goes through the same IPC prep uses.** Prep correctly avoids
writing `shell.json` because the shell rewrites it from memory and watches it.
Restore was specified as "puts the file back", which the running shell can
overwrite — the asymmetry is a bug.

**D. `SIGHUP`, and a recovery path.** An SSH drop sends `SIGHUP`, which
`trap … EXIT INT TERM` does not catch, so the spec's claim that a dropped
connection still restores was false. And `SIGKILL`/OOM/power loss cannot be
trapped at all, which is what the recovery path is for.

## Steps

**1. `screencast-prep`, narrowed.** It may change only what it can put back:
plugin enablement, the theme, and idle inhibition. It **does not close
windows** — it refuses to start if any window is open, and names them, so the
operator closes their own work deliberately. It **does not dismiss
notifications**; it refuses if any are pending.

→ verify: run it with a window open and confirm it refuses, naming the window.

**2. The snapshot covers every mutation, not one file.** `shell.json`, the
current theme, the idle-inhibit state, and the `enabled-once` marker set —
recorded as a manifest with a SHA-256 per entry, written `0600`, and refusing
to start when a stale manifest exists.

→ verify: `prep`, then diff the manifest against a hand-collected list of what
prep changed. Anything prep touches that is not in the manifest is a bug.

**3. `screencast-restore` goes through IPC.** Plugin state is restored with
`omarchy plugin enable/disable`, not by writing `shell.json`. After restoring,
it waits for the shell to settle and **re-reads the live state**, comparing
against the manifest — a disk write that the shell then overwrote must fail.

→ verify: restore while the shell is running, then read `shell.json` back
**after a settle delay** and compare. A check that reads immediately would pass
on the bug this step exists to prevent.

**4. `SIGHUP` in the trap, and `screencast-recover`.** The trap becomes
`EXIT INT TERM HUP`. Because `SIGKILL` and power loss cannot be trapped, a
fourth command restores from the manifest with no prep session running, and
`prep`'s refusal message names it.

→ verify: `kill -9` the driver mid-take, confirm the desktop is dirty, then
`screencast-recover` and confirm the manifest verifies.

**5. `screencast-drive`** reads `shots.nix` and exports the four environment
variables `tests/demo/default.nix`'s `user()` documents — `XDG_RUNTIME_DIR`,
`WAYLAND_DISPLAY`, `HYPRLAND_INSTANCE_SIGNATURE` and the one that is easy to
miss, `DBUS_SESSION_BUS_ADDRESS`. Without it `omarchy-shell shell ping` answers
"not running" against a shell that is running.

→ verify: a ten-second take that opens one panel over SSH.

**6. `screencast-record`** wraps `gpu-screen-recorder`, writing MKV, and
records the wall-clock at which each beat fired to `beats.json` beside it. The
gate uses **those observed times**, not the scripted ones, so compositor lag
shifts the sample window rather than failing it.

→ verify: `beats.json` timestamps are monotonic and within a second of the
scripted `at` values.

**7. The gate: `verify-beats`.** A new mode on `verify-frames.sh`, not a
loosened one — the GIF path is untouched.

- samples **N frames across each beat's window** (`observed_at + settle` to
  `observed_at + hold`), not one frame at a point;
- OCRs each beat's frames into **its own** text file, so an expectation can
  only be satisfied within its beat;
- runs on the **raw master**, and refuses a file that has a caption track or
  more than one video stream, so it cannot be pointed at the edited cut;
- `--forbid` per beat as well as globally.

→ verify: **step 10's break.**

**8. `screencast-edit`** produces both cuts from the master and `shots.nix`.

→ verify: both play; the clean one has no audio stream (`ffprobe` shows none).

**9. The twelve-plugin count is asserted.** A check compares the plugin ids
named in `shots.nix` against `defaultPluginSet` in `modules/home.nix` and fails
if any shipped plugin is unnamed. This is the same shape as `build.yml`'s
"every default plugin has a row in the manual".

→ verify: remove one from `shots.nix`; the check names it.

**10. Prove the gate fails.** Re-time one beat so its panel never opens, and
run `verify-beats` against that master. It must fail **naming that beat**. Then
the caption test: run it against the *edited* cut and confirm it refuses rather
than passing on its own subtitles.

→ both failures captured for the PR.

**11. Docs.** `docs/AGENTS.md` gains the scripted path and the 16:9 departure;
`tests/AGENTS.md` gains what the gate can and cannot see in video, and that
nothing in CI builds any of this (AGENTS.md §4).

**12. The recording itself**, then the owner watches both cuts in full before
anything is published.

## Tests

| Command | Expected |
|---|---|
| `prep` with a window open | refuses, names the window |
| `prep` → `restore`, shell running, read back after settle | manifest verifies |
| `kill -9` mid-take → `screencast-recover` | desktop restored, manifest verifies |
| `verify-beats` on a good master | green |
| `verify-beats` on a master with one beat removed | **red, naming that beat** |
| `verify-beats` on the edited cut | **refuses** — captions must not satisfy it |
| `verify-frames.sh` on the existing scene GIFs | unchanged and green |
| `ffprobe` the clean cut | no audio stream |
| the plugin-count check with one id removed | names the missing plugin |

## Rollback

Everything new is under `tests/demo/screencast/` plus one new mode on
`verify-frames.sh` and three documentation sections. Nothing enters a system
closure, no option is added, and no default changes — a user cannot observe
this work at all. Reverting the commit removes the harness; the recorded video
files are artefacts, not code, and are deleted separately if unwanted.

The one irreversible thing in the whole plan is a published video, which is why
step 12 is a human watching it and not a check.
