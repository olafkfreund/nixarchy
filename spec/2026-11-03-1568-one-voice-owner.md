---
status: draft
issue: 1568
intent: intent/2026-11-03-1568-one-voice-owner.md
---

# Spec: one voice owner, one speaker at a time

Line numbers below refer to the pinned commits: nixoarchy-snowflake at
`/nix/store/i8fqg72s…-source` (`app/server.py`) and nixarchy-voice at
`0231774e` (`src/omarchy_voice/`). The plan re-reads them at each product's
head before editing.

## Design

### The floor: one lock file, two jobs

Both products use one file, `$XDG_RUNTIME_DIR/nixarchy-voice-floor.lock`, with
a kernel `flock`. Whoever holds it **has the floor**. That one fact answers both
questions in the intent:

- **Who may speak.** A speaker takes `LOCK_EX`, blocking, before its first
  sound, and keeps it until its reply and that reply's tail are over. A second
  speaker blocks in the same call, so it waits its turn, with no timeout
  (intent decision 3).
- **Whether to believe the microphone.** A listener asks
  `floor_taken_by_other()`. That opens the file on a fresh descriptor, tries
  `LOCK_SH | LOCK_NB`, and releases at once. If the try fails and this process
  is not the holder, someone else has the floor, and the listener throws away
  what it heard (intent decision 4).

Why `flock` and not a pid file: the kernel releases the lock when the holder's
descriptor closes, crash included. Nothing has an expiry, and no stale state
can be left behind.

The two traps this has to avoid:

- **Don't leak the descriptor to a player.** Python opens descriptors
  non-inheritable (PEP 446), and `subprocess.Popen` defaults to
  `close_fds=True`, so a long-lived `paplay`/`pw-cat` cannot keep the floor.
  The plan asserts this in a test rather than trusting it.
- **Don't take the probe for a hold.** `flock` belongs to the open file
  description. A process that holds `LOCK_EX` on one descriptor fails its own
  `LOCK_SH | LOCK_NB` probe on another, so each product keeps a "held by me"
  flag and checks that first.

Each product carries its own ~30-line helper with the same file name and the
same semantics. There is no shared library: the products share no code today,
and a package dependency for 30 lines is the coupling the intent rules out.
Each product's `doctor` names the file path in its output, so a reader can
check the two agree.

### Nixi companion (nixoarchy-snowflake)

- **Speaking, server path.** In `Speaker._player_loop` (`server.py:2277`), take
  the floor where it detects "it had gone quiet: restart the clock" (line 2301),
  before the first `_write` of a reply. The take blocks the player thread only.
  Keep it until the follow-up window closes: `Wake.follow_until`, set by
  `talking_until` (line 1546). So Nixi holds the floor for its reply plus
  `follow_up` seconds (default 4, line 177). That is the window in which Nixi
  accepts speech without its wake word, and Oma must not speak into it. A
  one-shot timer releases at `follow_until`. `Wake.hush()` and
  `Speaker.stop()` (a cut-off) release at once.
- **Speaking, page path.** `/api/tts` (`server.py:3461-3488`) returns audio that
  `app/static/index.html:1277` plays when `voice_out` is `"page"`. The handler
  takes the floor before returning the clip, and releases after the clip's
  duration plus `follow_up`. The server is a `ThreadingHTTPServer` (line 4061),
  so a blocked handler blocks only that request.
- **Hearing.** At the top of `Wake.check` (line 1658): if
  `floor_taken_by_other()`, return before `MicAuto.learn` and before
  transcribing. That covers the wake word, the follow-up window and barge-in,
  and it also stops Oma's voice from retuning Nixi's mic level. `Wake.should_run`
  (line 1571) also returns `False` while another holds the floor, so the
  recorder closes and no speech-to-text runs. The push-to-talk `Listen` session
  is left alone: the user started it on purpose.
- **Barge-in while waiting (agy's finding).** While Nixi waits for the floor,
  `Speaker.idle()` is `False`, so `Wake.speaking()` is `True` and barge-in
  would listen. But `Wake.check` now drops everything while the other holds
  the floor, so "thanks" in Oma's reply cannot cancel Nixi's queued answer.

### Oma (nixarchy-voice)

- **Speaking, one choke point.** `Feedback._speak_now` (`feedback.py:288`) is
  the single implementation behind the daemon, `say` and `ask` (the daemon
  calls it at `local_engine.py:453`/`463`). It takes the floor if this process
  does not already hold it, and gives it back when it returns. That covers
  `omarchy-voice ask` and `say` as one-shot processes.
- **Speaking, one hold per reply (agy's finding).** In `_speech_loop`
  (`local_engine.py:437`), take the floor when a line is taken from an empty
  queue, and release when the queue is empty again (where `_voice_until` is set,
  line 474), after Oma's existing echo tail (#114). Because the daemon already
  holds the floor, the per-line take in `_speak_now` is a no-op, so another
  speaker can't slip in between sentences. Scheduled `announce` messages
  (`cli.py:723`) arrive through the daemon's speech queue and are covered.
- **Hearing.** In `_hear` (`local_engine.py:679`), the one place both the wake
  turn (line 652) and active turns transcribe: if `floor_taken_by_other()`,
  return no text, which both callers already treat as "nothing said". Also skip
  `_wake_turn`'s recording while the floor is taken, so the idle listener costs
  nothing during Nixi's turn.
- **Oma's active session is not a hold.** After her reply, Oma's microphone
  stays open for up to `idle_stop_seconds` (600 s). Holding the floor through
  that would silence Nixi for ten minutes, so Oma releases after the echo tail
  only. Nixi holds through its 4-second follow-up because that window is short
  and bounded. During it, Oma's `_hear` throws away what it hears.

### nixarchy

- **A warning, in `modules/home.nix`** beside the existing nixi/voice wiring,
  when `services.nixi.companion.enable` is on and
  `programs.omarchy-voice.settings.ears.wake_word` is non-empty. It names the
  cost: two idle microphones, each with its own speech-to-text model (intent
  decision 1). Nixi's wake word lives in its mutable `config.json`, not in a
  Nix option, so the warning keys on Oma's side only and says Nixi listens by
  default.
- **A line in `docs/manual/ai.md`** showing the two options together and what
  the floor does (intent decision 2).
- **Pin bumps:** `nixarchy-voice` (a commit URL in `flake.nix`) and
  `nixi-companion` (`flake.lock`), once both products have merged.

## Coexistence

nixarchy adds no option and sets nothing a user also sets. The warning reads
two options and writes none. `checks.coexistence` needs no fixture, because
there is nothing to collide. The lock file sits in the user's runtime
directory, which no NixOS option manages.

## Alternatives rejected

- **`programs.nixarchy.voiceOwner`:** rejected in the intent (decision 1).
- **Each product commanding the other** (`omarchy-voice listen stop/start`):
  not a pause, not restored afterwards, and stuck if the caller crashes (intent
  premise 2).
- **A shared speech daemon, or a D-Bus name:** ruled out by the intent's
  constraints. Either would also need both products to adopt a new process.
- **A PipeWire-level solution** (ducking, or one exclusive sink): it would stop
  the overlap but not the hearing, because the other product's open mic still
  transcribes the speaker.
- **A lock per sentence:** sentences from the two products would interleave.
- **A pid file or timestamp file:** it needs expiry logic, and a crash leaves
  it stale. `flock` has neither problem.
- **A shared Python package for the helper:** a dependency between two repos
  for 30 lines. Instead, the file name is the contract, and both doctors print
  it.

## Risks

- **Nixi holds the floor through its follow-up window,** so Oma's reply can wait
  up to `follow_up` seconds (4 by default) after Nixi stops. That delay is the
  point. If it feels slow on p620, `follow_up` is already a Nixi setting.
- **A holder that hangs without crashing,** for example a wedged `pw-cat`,
  keeps the floor, and the other product never speaks. Both products already
  bound playback (Nixi kills a dead player at `_player`, line 2235; Oma's
  `player.wait()` returns when `pw-cat` exits). The plan adds a test that a
  killed player releases the floor. A floor the tests show can be held forever
  stays a risk to document, not to paper over with a timeout.
- **Version skew:** a nixarchy bump that carries only one product's change
  does no harm. The other product neither takes the floor nor probes it, so
  behaviour is today's behaviour, never a deadlock. Merge order does not matter.
- **The page path's duration is estimated** from the clip length. A page that
  plays the clip late could speak past the release. That is low-risk: the page
  plays as soon as it receives the clip.
- **No CI in nixoarchy-snowflake** (`flake.nix` comment), so its tests are run
  by hand. The plan runs them and quotes the output.

## Verification

- **nixarchy-voice, unit tests** (`tests/test_local_engine.py`, the existing
  suite run by its CI), with a temporary `XDG_RUNTIME_DIR`:
  - with a child process holding `LOCK_EX`, `_hear` returns no text and
    `_speak_now` blocks until the child exits;
  - killing the child (`SIGKILL`) releases the floor;
  - a `Popen` started while the floor is held does not inherit the descriptor
    (read `/proc/<pid>/fd`);
  - two lines queued back to back are spoken under one hold.

  §1: each test is shown failing with its hook removed, then passing.
- **nixoarchy-snowflake, unit tests** (`tests/`, the same four, for `Wake.check`
  and `Speaker`), run by hand and quoted in its PR, with the §1 failing
  output.
- **nixarchy:** a `tests/options.nix` case for the warning in both states (it
  fires with the companion on and `ears.wake_word = "oma"`, and stays silent
  with either off). Shown failing first.
- **Real hardware (§2, by the owner on p620):** both products on, Oma's wake
  word on, speakers rather than headphones. Ask Nixi something, then say "Oma,
  what time is it" during Nixi's answer. Expected: Nixi finishes, Oma does not
  act on Nixi's speech, then Oma answers. Run once with the companion killed
  mid-reply: Oma speaks within a second. Measure the echo tail here too
  (intent decision 4) and record it in the plan.
- **`pkgs/verify.sh`:** a line under the voice section that, when both products
  are on, prints the floor file path and whether it is held. It is a readable
  probe, not a pass/fail, because holding the floor is legitimate.
