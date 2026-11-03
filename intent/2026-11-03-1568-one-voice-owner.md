---
status: draft
issue: 1568
author: olafkfreund
---

# Intent: one voice owner, one speaker at a time

## Problem

Two products on a nixarchy desktop can listen to the microphone and talk back,
and neither knows the other exists:

- **The Nixi companion** (`services.nixi.companion`, nixoarchy-snowflake)
  listens for "hey Nixi" by default (`wake_word: True`, `app/server.py:169` at
  the pinned commit) and speaks its replies (`tts: "auto"`, line 152).
- **nixarchy-voice** (`programs.nixarchy.voice` → `programs.omarchy-voice`)
  listens on its toggle key, or on the "oma" wake word if that is turned on.
  Its daemon speaks every reply. The local engine calls `Feedback._speak_now`
  directly (`local_engine.py:447-453`), so the `speak = false` default
  (`config.py:483`) only governs the one-shot `say` path, not the daemon.

So enabling both products is enough for them to speak over each other. Two
worse effects follow, which the issue did not name:

- **Each one hears the other.** Each mutes its microphone only against its own
  voice. Nixi's `Wake.speaking()` (`server.py:1536`) knows nothing of Oma, so
  Oma's reply out of the speakers reaches Nixi's open mic. Nixi's 4-second
  follow-up window needs no wake word (`server.py:177`, `1680-1684`), so that
  speech can arrive as a request. Oma's own config warns that a fragment heard
  back has been *run* (`config.py:346-350`). Taking turns on the speaker
  without minding the other's mic hands one product's reply straight into the
  other's listening window.
- **Two listeners stay open.** With Oma's wake word on, two microphone
  listeners and two speech-to-text models transcribe every sound in the room
  before either hears its word. Oma's wake listener runs exactly while its
  listening is *off* (`config.py:388-390`).

This was seen on p620, where both are on.

Checked against the pinned sources, two of the issue's proposals rest on
premises that do not hold, and one needs care:

1. **The companion's package is already set in nixarchy.** The issue says
   "`services.nixi.companion.enable = true` fails without an explicit package".
   That is false inside nixarchy, because `modules/home.nix:882` sets
   `companion.package` with `mkDefault`. It is true only for someone using
   nixi-nixarchy on its own, so it belongs to that repo, not here.
2. **`omarchy-voice listen stop` / `start` are not a pause.** They switch the
   daemon's active session (`local_engine.py:964-966`). `stop` while Oma sits in
   wake standby changes nothing (the wake mic stays open). An unconditional
   `start` afterwards turns on a session the user never asked for. And a
   companion that crashes between the two calls leaves Oma off. Whatever quiets
   Oma has to restore the prior state and die with its holder, like the lock.
3. **Nixi has two playback paths.** `/api/say` plays through the server's
   `Speaker`. `/api/tts` returns audio that the browser page plays
   (`app/static/index.html:1277`). A lock taken only in `Speaker` misses the
   second.

## Proposed outcome

With both products enabled:

- Only one of them speaks at a time, on every playback path. If one is ready
  while the other is speaking, it waits its turn rather than interrupting.
- Neither product takes the other's speech as a request. While one speaks, and
  for its follow-up window, the other is not listening. Afterwards each
  listener is back in the state it was in, even if the speaker crashed.
- A machine with only one of the two products behaves exactly as it does today.

## Affected users and systems

- **People who enable both products** (p620 today). Both are off by default in
  nixarchy, so a machine with one or neither is unaffected.
- **Other ways Oma speaks or listens:** the one-shot `omarchy-voice ask`, and
  scheduled routines that `announce` on a timer (`hm-module.nix:436-445`). Both
  need the same rule as the daemon.
- **Repositories:** nixoarchy-snowflake (the companion) and nixarchy-voice
  (Oma) each gain the lock around playback. nixarchy changes little or nothing,
  apart from the input bumps and possibly one probe.
- **Hosts:** p620 for the real test (microphone + speakers); razer if both
  products are on there.

## Constraints

- **Keep the three gates separate:** Nixi's trust, Oma's executor gate, and the
  ai-mirror grant. No shared speech daemon, and no D-Bus service.
- **The lock dies with its holder.** A crashed speaker must not leave the other
  one mute, so use a kernel `flock` on a file under `$XDG_RUNTIME_DIR`, with no
  expiry logic. The lock's file descriptor must not leak into a long-lived
  player process (Nixi keeps one `paplay` open across sentences), or the lock
  is never released.
- **Mode A:** nothing changes for a configuration that enables neither product
  or only one.
- **Fixes belong in each product's repo, not as a nixarchy patch.** This is
  CLAUDE.md §11's upstream rule applied to our own forks: nixarchy only bumps
  the pins.
- **Probe (§2):** "both speak at once" was found by ear. The fix needs a check
  that can fail. The cheapest candidate is a test in each repo that holds the
  lock and asserts the other side neither plays nor accepts what it hears.

## Open questions

1. **Does `voiceOwner` earn its keep?** The issue proposes
   `programs.nixarchy.voiceOwner = "companion" | "oma" | "none"`, which would
   decide who gets wake listening and speech by default. The lock and the
   listening rule fix the speaking and the hearing. They do **not** close the
   two idle wake listeners: those stay open whenever the user turns both wake
   words on. My recommendation is to **drop the option** anyway. Oma's wake
   word is off unless chosen (`config.py:402`), and choosing it is already one
   existing setting. Instead, add a warning when both wake words are on, naming
   the cost. Overriding both products with a third option would be a second
   place to change the same thing.
2. **Do we want presets?** The issue proposes four one-line presets (nixi only;
   nixi + companion; voice only; all four). Their stated reason, the missing
   package, does not hold in nixarchy (premise 1). My recommendation is to
   **drop them**, plus a line in `docs/manual/ai.md` showing the
   two-option combination.
3. **What should a speaker do when the lock is held?** I recommend waiting, as
   the outcome says, with no timeout. Each reply is bounded already (Nixi caps
   it at `speak_max_chars: 600`, `server.py:155`). A timeout that falls back to
   text would quietly drop the spoken reply the outcome promises. The spec has
   to settle two interactions agy found: whether Nixi counts as "speaking"
   while it waits (its barge-in could cancel its own queued reply), and whether
   one reply holds the lock or each sentence does (otherwise sentences
   interleave).
4. **How does the listener know the other is speaking?** One mechanism would
   serve both the speaking and the hearing: a listener drops what it hears
   while the speak lock is held by someone else, and for a short tail after.
   That needs no pause command, survives a crash, and works the same in both
   directions. The alternative, each product commanding the other's daemon,
   fails three ways (premise 2). I recommend the lock-as-signal. The spec
   measures the tail on p620's speakers.
