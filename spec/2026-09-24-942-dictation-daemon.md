---
status: draft
issue: 942
intent: intent/2026-09-24-942-dictation-daemon.md
---

# Spec: dictation, wired through the module that already exists

## Design

Five changes. Four are wiring; one is the unrelated `binary` bug the intent
found, fixed here for the reason given below.

### 1. `dictation` becomes an `option` app

`data/apps.nix:429`. Today it is `attr = "voxtype"`, which is why enabling it
puts a binary on PATH and nothing else. It becomes:

```nix
dictation = {
  menuId = "install.ai.dictation";
  label = "Dictation";
  category = "AI";
  option = [ "programs" "nixarchy" "dictation" ];
  arch = "voxtype-bin";
  binary = "voxtype";
  note = ''…names the ~150 MB model download…'';
};
```

`attr` goes, because the file's own header forbids both and gives exactly our
reason: *"An app with an `option` must NOT also set `attr`: the module owns
installing its own package."* The Home Manager module does precisely that.

`menuId` and `arch` stay, so the Install and Remove rows keep working.

### 2. `programs.nixarchy.dictation.enable`, bridged

A NixOS option beside `voice.enable` (`modules/nixos.nix:272`), read through
`osConfig` in `modules/home.nix` the way `omarchy-voice` is at `:1848`. That
bridge exists because `modules/apps.nix` is a **NixOS** module while voxtype's
is a **Home Manager** one — the mismatch #774's spec records discovering the
hard way, with `error: The option 'programs.omarchy-voice' does not exist`.

The home side sets `services.voxtype.enable`, `loadModels` and
`wayland.display`, and **leaves `settings` unset**.

### 3. The config is seeded, not managed

`settings` stays unset deliberately. The module writes the config through
`xdg.configFile` — a read-only store symlink — and our own
`pkgs/omarchy/nix-bin/omarchy-voxtype-config`, which the bar's Dictation
indicator runs on click, calls `voxtype configure` against that path. So does
`voxtype config set`. A symlink breaks both.

`xdg.configFile` there is `mkIf (cfg.settings != { })`, so leaving it unset
writes nothing, and `seed_file` (`modules/home.nix:912`) supplies upstream's
`default/voxtype/config.toml` from the already-seeded tree — one call beside
the existing ones, no new mechanism. Its contract is already the one we want:
*"Seed, don't manage… Existing files are never overwritten."*

### 4. `appBinary` reads `binary`

`modules/apps.nix:25-36`. Today it derives from `attr or name`, asks
`meta.mainProgram`, and falls back to the app's name. `binary` is read nowhere.

```nix
appBinary = name: app:
  if app ? binary then app.binary else <existing derivation>;
```

**Fixed here rather than split out**, on the intent's question 2, for three
reasons: dictation needs it (an `option` app has no `attr`, so the fallback is
the literal string `dictation`, and `command -v dictation` can never match); it
is three lines; and it is contained — only an app that *sets* `binary` changes
behaviour, which today is `android-tools` alone, where the change is the fix its
own comment asks for.

### 5. Ordering after the audio stack

The module sets `Install.WantedBy = [ "default.target" ]` and orders only after
its model loader. We add `After = [ "pipewire.service" ]` on the home side.

**Stated honestly: `After` is ordering, not readiness.** PipeWire is socket
activated and a source can still be unavailable when the daemon starts. This
makes the common case right and does not make the race impossible. The
alternative — a restart loop — is not added until a real machine shows it is
needed, because a restart loop hides the failure it is papering over.

## Alternatives rejected

**Write our own systemd unit.** The intent's first constraint. A unit we write
is a unit we maintain, upstream's already orders the model loader correctly,
and this is how the issue's own reporter got `.voxtype-wrapped` into an
`ExecStart`.

**Ship the model as a fixed-output derivation.** On the intent's question 1,
and this is the closest call in the spec.

For: reproducible, offline-installable, and `enable = true` would mean the
feature works rather than "works once the network cooperates". An independent
review argued it, on the grounds that a first-run fetch "recreates the current
defect in a more polite form".

Against, and decisive here: **nothing in this tree fetches an ML model as a
FOD**, and both features that carry models avoid it deliberately —
`modules/local-ai.nix:341` pulls Ollama weights at runtime because they are
"multi-gigabyte mutable blobs", and `omarchy-voice` keeps 6.7 GiB behind an
opt-in row. Adding ~150 MB to every enabled closure would also be the first
third-party weights URL and hash this repository maintains, and **the weights'
redistribution licence is not voxtype's MIT licence** — which has to be settled
before anything reaches a public cache. `loadModels` is what the module is for
and it is neither silent nor in the store: a failed download is a failed unit,
visible in `systemctl --user status`.

This is reversible. If the download proves unreliable, a FOD is a later change
and this spec is where the reasoning is recorded.

**Seed the config with an activation script of our own.** `seed_file` already
exists and already has the semantics; a second mechanism would be the thing
§7 warns about.

## Risks

**A daemon that reports `active` while dictation does not work.** This is the
issue's own failure in a new costume, and it is the main risk. Causes: no
microphone, the user not in `input`, PipeWire without a usable source, Wayland
text injection blocked. **None of these is reachable by a check in a sandbox**,
and the verification section says so rather than implying coverage.

**The model download fails and the feature is silently inert again.** Mitigated
rather than removed: a failed `voxtype-model-loader.service` is visible, unlike
today's nothing. Not mitigated for a machine installed offline.

**`appBinary` changes a generated menu.** Contained to apps that set `binary`,
which is `android-tools` alone. The check that compares generated rows will say
if it is wider than that.

**Mode A.** Everything is behind `dictation.enable`. `tests/options.nix`
asserts every option in both states, and the off state is the one a refactor
breaks quietly.

## Verification

| | |
|---|---|
| `checks.options`, dictation off | no `voxtype` unit, no package, no model — and **red with the bridge line removed** (§1) |
| `checks.options`, dictation on | `services.voxtype.enable`, the unit exists, `ExecStart` is a stable package path and not `.voxtype-wrapped` |
| `appBinary` with `binary` set | returns `voxtype` / `adb`, **red before the fix** |
| `nix fmt -- --ci`, statix, deadnix | clean |
| real hardware | `systemctl --user is-active voxtype` → `active`; hold F9 and dictate; `voxtype configure` still writes the config |

**What no check here can reach**, to be written into `tests/AGENTS.md` as a
documented hole (§3): a real microphone, `input` group membership, PipeWire
providing a usable source, Wayland text injection, whether the unit survives an
upgrade and a garbage collection, and whether the model download works from a
given network. **A VM seeing the unit `active` is not evidence that dictation
works**, and this spec does not pretend otherwise.
