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
  listens on its toggle key, or on the "oma" wake word if that is turned on, and
  speaks replies when `speak = true`.

When both are on, they can speak over each other. With Oma's wake word on too,
two microphone listeners and two speech-to-text models run at once. This was
seen on p620, where both are on.

Checked against the pinned sources, the issue's premises need three corrections:

1. **Upstream's defaults are safe.** Oma's `speak` defaults to `false`
   (`src/omarchy_voice/config.py:483`). Its wake word also starts off
   (nixarchy-voice#19/#21, restated in `flake.nix`). So the clash only happens
   once somebody opts into both products and Oma's speech. That opt-in is
   exactly the setup on p620.
2. **The companion's package is already set in nixarchy.** The issue says
   "`services.nixi.companion.enable = true` fails without an explicit package".
   That is false inside nixarchy, because `modules/home.nix:882` sets
   `companion.package` with `mkDefault`. It is true only for someone using
   nixi-nixarchy on its own, so it belongs to that repo, not here.
3. **Pausing Oma already has a command.** `omarchy-voice listen stop` / `start`
   exist (`cli.py:22`), so the companion can quiet Oma's listening without any
   new interface.

## Proposed outcome

With both products enabled:

- Only one of them speaks at a time. If one starts while the other is
  speaking, it waits its turn. It does not interrupt, and it does not drop
  its reply.
- While the companion takes a turn, Oma is not also listening. Oma resumes
  afterwards, in the state it was in before.
- A machine with only one of the two products behaves exactly as it does today.

## Affected users and systems

- **People who enable both products** (p620 today). Nobody else is affected,
  because both are opt-in.
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
  expiry logic.
- **Mode A:** nothing changes for a configuration that enables neither product
  or only one.
- **Fixes belong in each product's repo, not as a nixarchy patch.** This is
  CLAUDE.md §11's upstream rule applied to our own forks: nixarchy only bumps
  the pins.
- **Probe (§2):** "both speak at once" was found by ear. The fix needs a check
  that can fail. The cheapest candidate is a test in each repo that holds the
  lock and asserts the other side waits.

## Open questions

1. **Does `voiceOwner` earn its keep?** The issue proposes
   `programs.nixarchy.voiceOwner = "companion" | "oma" | "none"`, which would
   decide who gets wake listening and speech by default. My recommendation is
   to **drop it** for now. The speaking lock plus the pause during a companion
   turn removes the clash itself. Who uses a wake word is already one existing
   option in each product, and a third option that overrides both is a second
   place to change the same setting. We can revisit it if two always-on
   listeners turn out to be a real cost on p620 with the lock in place.
2. **Do we want presets?** The issue proposes four one-line presets (nixi only;
   nixi + companion; voice only; all four). Their stated reason, the missing
   package, does not hold in nixarchy (premise 2). My recommendation is to
   **drop them**, plus a line in `docs/manual/ai.md` showing the
   two-option combination.
3. **What should a speaker do when the lock is held?** Wait, or skip speaking
   and show the text only? I recommend waiting, with a bound: if the other
   speaker is still going after about 30 s, show the text instead.
4. **Should the companion pause Oma at all,** or is the speaking lock enough?
   Pausing means the companion has to call `omarchy-voice`. That couples the
   two products slightly, but only through a command that already exists.
