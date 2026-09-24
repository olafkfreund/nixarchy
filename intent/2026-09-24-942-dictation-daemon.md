---
status: draft
issue: 942
author: olafkfreund
---

# Intent: dictation should start a daemon, not just put a binary on PATH

## Problem

`programs.nixarchy.apps.dictation` installs `voxtype` and does nothing else.
There is no daemon, no config file and no model, so F9 and Super+Ctrl+X fire
into nothing and the bar's Dictation indicator sits idle. Found on razer and
p620 on 2026-09-24, both with `voxtype` 1.0.1 on PATH.

On Arch, `omarchy-voxtype-install` copies a config, downloads a whisper model
and writes a user unit. nixarchy does none of the three, and running the third
by hand is not a fix: it generated an `ExecStart` pointing at
`.voxtype-wrapped` inside a store path, which breaks at the next upgrade or
garbage collection.

**The issue proposes writing a unit, seeding a config, and shipping the model
as a fixed-output derivation. Most of that already exists and should not be
written again.**

Home Manager at our pinned revision ships `modules/services/voxtype.nix` —
verified present, 203 lines — which already provides:

| | |
|---|---|
| `systemd.user.services.voxtype` | `ExecStart = "${getExe cfg.package} daemon"`, the **stable** path rather than the `.voxtype-wrapped` the issue warns about |
| `voxtype-model-loader.service` | `setup --download --model …`, gated on `loadModels != [ ]` |
| `home.packages` | the package, plus `wtype` and `wl-clipboard` |

And #774 already built, shipped and tested the bridge for exactly this shape: a
nixarchy NixOS option read through `osConfig` into a Home Manager module
(`modules/nixos.nix:272`, `modules/home.nix:1848`).

So the gap is narrower than the issue implies. What is missing is the wiring,
not the machinery.

## A second, separate bug found while reading this

**`data/apps.nix`'s `binary` field is never read.** `appBinary`
(`modules/apps.nix:25-36`) derives a command name from `app.attr or name`, asks
for `meta.mainProgram`, and otherwise falls back to the app's own name. Nothing
anywhere reads `binary`.

It has exactly one user, `android-tools` at `data/apps.nix:510`, whose comment
states the bug it was written to prevent:

> `binary`, because the attribute is not a command. This package ships adb,
> fastboot, mkbootimg and a dozen more, so nixpkgs states no mainProgram —
> correctly — and without this the catalogue would answer "android-tools" and
> report the app missing on a machine that has it.

Measured: `android-tools.meta.mainProgram` is unset, so `appBinary` returns
`android-tools`, and the generated menu row's dim test runs
`command -v android-tools` — a command that does not exist. **The row never
dims, on a machine where adb is installed.** The field does nothing and the
comment describes behaviour the code does not have.

This is §2's "a setting the tool does not read", and it matters here because
the obvious fix for dictation was to set `binary = "voxtype"`, which would have
been equally inert.

## Proposed outcome

With `dictation` enabled:

- `systemctl --user is-active voxtype` prints `active`, from a unit whose
  `ExecStart` is a stable package path that survives an upgrade and a GC;
- the whisper model is fetched once, visibly, rather than on first use or not
  at all;
- `~/.config/voxtype/config.toml` exists, is the user's to edit, and
  `voxtype configure` — which the bar's Dictation indicator runs on click —
  still works against it;
- holding F9 dictates.

With dictation disabled, nothing above exists. Mode A is untouched.

Separately: `binary` either works or is deleted. A field that silently does
nothing is worse than no field, because its presence is read as coverage.

## Affected users and systems

- Anyone who turns on Dictation — currently everyone who does so gets a silent
  no-op.
- Anyone who installed **Android platform tools**: their Install row does not
  dim. Nothing breaks, but the catalogue misreports.
- `data/apps.nix`, `modules/nixos.nix`, `modules/home.nix`,
  `modules/apps.nix`, `tests/options.nix`, and the manual.
- razer and p620, where this was found.

## Constraints

**Must:**

- Use the Home Manager module rather than writing a second unit. A unit we
  write is a unit we maintain, and upstream's already handles the model
  ordering.
- Keep the config **writable**. The HM module writes it as `xdg.configFile` —
  a read-only store symlink — and our own `omarchy-voxtype-config` runs
  `voxtype configure` against that path. `xdg.configFile` there is
  `mkIf (cfg.settings != { })`, so leaving `settings` unset avoids it, and
  `seed_file` (`modules/home.nix:912`, "Seed, don't manage… Existing files are
  never overwritten") already does the rest.
- Assert both states. `tests/options.nix` covers every option on and off, and
  the off state is the one a refactor breaks quietly.
- Say what no check can reach, rather than implying coverage.

**Must not:**

- Ship the model as a fixed-output derivation without a decision — see the open
  question. Nothing in this tree fetches an ML model that way, and the two
  features that carry models both deliberately avoid it.
- Run `voxtype setup systemd`, `setup --download` or `setup quickshell` from an
  activation script. Imperative setup is what produced the broken `ExecStart`.
- Change anything for a machine with dictation off.

## Open questions

**1. The model: activation-time download, or fixed-output derivation?**

The issue allows either. They are genuinely different bargains and this is the
decision I most want made rather than assumed.

- **`loadModels = [ "base.en" ]`** (my recommendation). Downloaded once by the
  model-loader unit, into the user's data directory, ordered after the network.
  Matches this repository twice over: `modules/local-ai.nix:341` pulls Ollama
  weights at runtime because they are "multi-gigabyte mutable blobs", and
  `omarchy-voice` keeps 6.7 GiB of whisper and Piper models behind an opt-in
  row. Costs: not reproducible, not available offline, and a machine with no
  network gets a failed unit rather than a working feature.
- **A fixed-output derivation.** Reproducible, offline-installable, and in the
  closure. An independent review argued for this, on the grounds that a
  documented first-run fetch "recreates the current defect in a more polite
  form". Costs: ~150 MB in every enabled machine's closure, a third-party URL
  and hash to maintain, and — the part that needs checking before anything is
  cached — **the weights' redistribution licence is not the binary's MIT
  licence**, and nixarchy's cache is public.

**2. Is `binary` fixed here or split out?** It is a real bug with a live
symptom, and dictation ran into it. But it belongs to the app catalogue rather
than to dictation, and fixing it changes a generated menu for every app. Fix it
in this issue, or file it separately and have dictation work around it?

**3. Does the unit need to wait for the audio stack?** The HM module uses
`Install.WantedBy = [ "default.target" ]`, not `graphical-session.target`, and
orders only after the model loader. A daemon that starts before PipeWire has a
usable source may report `active` while dictation does not work — which is the
failure mode this issue is about, in a new costume. Worth deciding whether we
add ordering or accept upstream's.
