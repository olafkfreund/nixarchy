---
status: draft
issue: 930
intent: intent/2026-09-23-930-screencast-harness.md
---

# Spec: recording a desktop becomes a script, not an afternoon

## The intent's open questions, answered

**1. Does the frame gate belong on video?** *Half of it does, and the half that
does not would have passed silently.*

`verify-frames.sh` says what it is for in its own header:

> diversity distinguishes "frozen" from "alive", and nothing more -- which is
> why the second check exists.

Its thresholds were measured on GIFs: a static-wallpaper recording still scored
5 of 11 transitions above 2% RMSE, and a *good* recording only 2 of 11. At
60 fps nearly every frame differs slightly from its neighbour, so **diversity
passes trivially on any video** — including one where the shot list never
advanced past beat two. Carrying it over would be a check that cannot fail,
which is §1's definition of a green light.

The **content** check is medium-agnostic and is the one that would have caught
the incident the gate was written for. It stays.

So video gets a gate with the same intent and a different mechanism:
**beat verification**. The shot list already knows when each beat starts. The
gate samples one frame per beat *at that timestamp*, OCRs it, and requires that
beat's `expect` string. A recording where the Plugin Browser never opened fails
naming **that beat**, not "insufficient diversity".

That is strictly stronger than what GIFs get: it checks the recording matches
the script, rather than that something moved.

**2. How much of this is nixarchy's business?** *A tool, not a feature.* The
prep step is scoped to recording and lives in `tests/`. A user-facing
presentation mode is a plausible future feature and is explicitly not this.

**3. Hero video, or a poster that links to one?** *Poster that plays in place.*
`<video>` with `preload="metadata"` and a `poster` — the page stays as fast as
it is today, nothing downloads until play, and `autoplay muted loop playsinline`
is added only if the owner wants it after seeing it. The front page's current
virtue is that it loads instantly, and that is not worth trading blind.

**4. Which machine?** *razer, with its limits stated.* Single 1920x1080 against
the house style's 2304x1440, and a nixarchy behind `main`. Recording there is
possible today; the alternative is blocked on a rebuild that is #915's caveat.
The spec records this as a known gap rather than pretending the frame matches
the site's stills.

## Design

Four commands under `tests/demo/screencast/`, each a `writeShellApplication`,
exposed as flake apps beside `demo-record`.

### `screencast-prep` and `screencast-restore` — the part that can do harm

The whole design of this pair is that **restore is not optional and not
trusted**.

- `prep` copies `~/.config/omarchy/shell.json` to
  `~/.local/state/nixarchy/screencast-restore.json` **and refuses to run if
  that file already exists** — a stale restore file means a previous take died,
  and overwriting it would destroy the only copy of the real desktop.
- It records a **SHA-256 of the original** beside it. `restore` puts the file
  back and re-hashes; a mismatch is a hard failure, not a warning.
- `restore` is idempotent and safe to run when nothing was prepped.
- The driver installs `trap screencast-restore EXIT INT TERM`, so an interrupt,
  a failed beat or a dropped SSH connection still restores.

Prep then: enables the twelve nixarchy plugins through
`omarchy plugin enable <id>` (the shell's own IPC writer — **never** by writing
`shell.json`, for the reason `modules/AGENTS.md` gives: the shell rewrites that
file from memory and watches it, so a second writer loses updates in both
directions); disables third-party bar widgets the same way; sets the default
theme; runs `omarchy-toggle-idle stay-awake`; dismisses pending notifications;
and closes every window.

### `screencast-drive` — the shot list as data

`tests/demo/screencast/shots.nix` is a list of
`{ label, at, action, expect, hold }`. `action` is one of the two things the
existing demo segments already use — `hyprctl dispatch exec` and
`omarchy-menu summon <route>` — so there is no second vocabulary.

The environment is the part that bites. `omarchy-shell shell ping` reports
"not running" over SSH against a shell that is plainly running, because
`DBUS_SESSION_BUS_ADDRESS` is missing. `tests/demo/default.nix`'s `user()`
helper already names the full set, and the driver exports the same four.

### `screencast-record` and `screencast-edit`

Capture with `gpu-screen-recorder` (chosen over `wl-screenrec` for explicit
cursor, CFR and quality control), to MKV, at the monitor's native rate.

Edit with scripted ffmpeg `filter_complex`, not kdenlive: repeatable, diffable,
and re-runnable after a re-take. One master produces both cuts — the clean one
has **no audio stream at all**, the social one carries `drawtext` captions timed
from the same `shots.nix` that drove the recording, so captions cannot drift
from beats.

## Alternatives rejected

- **Extending `tests/demo/`'s VM path to 1080p60.** The obvious reuse, and
  wrong: it captures qemu screendumps, which is why `docs/AGENTS.md` says
  *"grim cannot help here, as nothing consumes the frames and it blocks
  forever"*. A screendump-per-frame pipeline at 60 fps is not a video recorder.
- **Relaxing `verify-frames.sh` until a video passes.** The §1 failure exactly:
  a check retargeted to agree with its subject.
- **Driving with `ai-mirror`.** It reaches a different host than the one being
  recorded. It is also the more interesting answer long-term and should be
  revisited when the recording host and the ai-mirror host are the same.
- **kdenlive.** Not scriptable, so the second recording costs the same as the
  first — which is the thing this issue exists to fix.
- **Writing `shell.json` directly in prep.** Faster and silently wrong; see
  above.

## Risks

- **Nothing in CI builds `tests/demo/`** (AGENTS.md §4), and these scripts
  inherit it. The PR says so rather than implying coverage, and
  `tests/AGENTS.md` gains the hole.
- **A leak in the recording is permanent once published.** Prep closes windows
  and the beat gate can `--forbid`, but neither can see a translucent window
  showing something behind it (#764). **A human watches both cuts before
  anything is published**, and that is in the verification below rather than
  assumed.
- **A restore that does not run** leaves somebody's bar rearranged. Mitigated by
  the trap, the refusal-on-stale-file, and the hash check — and tested before
  it is relied on.
- **razer's desktop is behind `main`**, so the video shows a slightly older
  nixarchy. Stated, not hidden.
- **16:9 against a 16:10 house style.** A deliberate departure; `docs/AGENTS.md`
  gains a sentence rather than the rule being quietly broken.
- **Content ID can flag a permissively licensed track.** The licence page is
  saved beside the audio.

## Verification

| | how |
|---|---|
| **restore is real** | `prep` then `restore` with *no recording between*, and `sha256sum -c` on `shell.json`. **Then kill the driver mid-take and confirm the trap restored it.** A restore that has only been tested on the happy path is not a safety net |
| the env set drives panels | a 10-second throwaway take that opens one panel over SSH |
| **the beat gate can fail** | run it against a recording with one beat deliberately removed; it must fail **naming that beat**. Only then is a green run evidence (§1) |
| the gate is not relaxed | `verify-frames.sh`'s GIF behaviour is unchanged — the existing scene GIFs still pass with the same thresholds |
| both cuts play | in a browser: clean one silent and looping, social one with captions and audio at −14 LUFS |
| **nothing leaked** | the owner watches both cuts in full before publication |

The first and third rows are the ones that matter. Everything else says the
work was done; those two say it was done safely and that the check protecting
it is real.
