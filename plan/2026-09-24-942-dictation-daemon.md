---
status: draft
issue: 942
spec: spec/2026-09-24-942-dictation-daemon.md
---

# Plan: dictation, wired through the module that already exists

Self-contained. The approved decisions, so this can be implemented without
opening the intent or the spec:

- **Do not write a unit.** Home Manager at our pin ships
  `modules/services/voxtype.nix`, which provides `systemd.user.services.voxtype`
  with `ExecStart = "${getExe cfg.package} daemon"` — a stable path — plus a
  `voxtype-model-loader.service` and `wtype`/`wl-clipboard`.
- **Leave `services.voxtype.settings` unset.** It writes the config through
  `xdg.configFile`, a read-only store symlink, and `voxtype configure` (which
  the bar's Dictation indicator runs) writes that same path. It is
  `mkIf (settings != { })`, so unset means no symlink.
- **Seed the config** with the existing `seed_file` (`modules/home.nix:912`).
  Upstream's `default/voxtype/config.toml` is confirmed present in the seeded
  tree.
- **`loadModels = [ "base.en" ]`**, not a fixed-output derivation. Nothing here
  fetches an ML model as a FOD and both model-bearing features avoid it.
- **Fix `appBinary` to read `binary`** — dictation needs it, and it is the fix
  `android-tools`' own comment asks for.
- **`After = [ "pipewire.service" ]`**, with the caveat that `After` is
  ordering and not readiness.

## Steps

1. **`modules/apps.nix:25`** — `appBinary` returns `app.binary` when the entry
   sets one, otherwise the existing `meta.mainProgram` derivation. Three lines.
   → verify per §1 **before** anything else depends on it: with `binary`
   ignored, `android-tools` resolves to `android-tools`; with the fix, to
   `adb`. A one-line `nix eval` of the generated menu row, red then green.

2. **`data/apps.nix:429`** — `dictation` drops `attr`, gains
   `option = [ "programs" "nixarchy" "dictation" ]` and `binary = "voxtype"`,
   keeps `menuId` and `arch`, and gains a `note` naming the ~150 MB model
   download so the template says so before anyone enables it.
   → verify: the generated menu still has `install.ai.dictation` and
   `remove.dictation`, and its `disabled` test now names `voxtype`.

3. **`modules/nixos.nix`**, beside `voice.enable` (`:271`) — declare
   `dictation.enable = lib.mkEnableOption` with a description naming the model
   download and its size, in the register the neighbouring option uses.
   → verify: `checks.options` evaluates; the option appears in both states.

4. **`modules/home.nix`** — the bridge. Note the shape difference from voice:
   `omarchy-voice` is a `programs.*` option and nests in the existing
   `programs = { }` block at `:1847`; `voxtype` is a **`services.*`** option and
   does not. Set `services.voxtype`:
   - `enable = lib.mkDefault (osConfig.programs.nixarchy.dictation.enable or false)`
   - `loadModels = [ "base.en" ]`
   - `wayland.display` — so the module pulls in `wtype` and `wl-clipboard`
   - **`settings` left unset**
   - `After` extended with `pipewire.service`

   **Priorities (§7):** `mkDefault` on the scalar `enable`; **plain assignment**
   on `loadModels` and on any list — `mkDefault` on a merging type silently
   drops the whole contribution the moment a user adds an element.
   → verify: with dictation on, the unit exists and `ExecStart` contains
   `/bin/voxtype daemon` and not `.voxtype-wrapped`; with it off, neither
   `voxtype` nor `voxtype-model-loader` is present.

5. **`modules/home.nix`**, beside the existing calls at `:943` — seed
   `${omarchyPath}/default/voxtype/config.toml` to
   `${config.xdg.configHome}/voxtype/config.toml` with `seed_file`.
   → verify: the activation script names the path; the seeded file is writable
   (`--no-preserve=mode` is why) and a modified one is not overwritten.

6. **`tests/options.nix`** — an on/off pair modelled on `voiceIsNotADefault`
   (`:1066`), which already asserts `(h.systemd.user.services or { }) ? …`. At
   least: the unit is absent when off and present when on; `ExecStart` is a
   stable path; `settings` produced no `xdg.configFile` entry for
   `voxtype/config.toml` (the indicator regression this spec exists to avoid).
   → verify per §1: each case **red with its own line reverted**, captured for
   the PR.

7. **`tests/AGENTS.md`** — the documented hole. No check here reaches a
   microphone, `input` group membership, a usable PipeWire source, Wayland text
   injection, an upgrade-and-GC cycle, or the model download. State that **a VM
   seeing the unit `active` is not evidence that dictation works**, with the
   by-hand repro.

8. **`docs/manual/`** — the model download, its size, and that the config is
   the user's to edit.

9. **On real hardware**, and it is the only step that can confirm the issue is
   fixed: `systemctl --user is-active voxtype` → `active`; hold F9 and dictate;
   `voxtype configure` still writes the config; the Dictation indicator responds
   to a click.

## Tests

| command | expected |
|---|---|
| `appBinary` for `android-tools` | `adb` — **`android-tools` before step 1** |
| `nix build .#checks.x86_64-linux.options` | green; **red with any step-6 case's line reverted** |
| generated menu rows | `install.ai.dictation` and `remove.dictation` still present |
| `nix fmt -- --ci`, statix, deadnix | clean |
| real hardware (step 9) | the unit active, dictation dictates |

`checks.options` is ~8 minutes and peaks near 12 GB, and must not be built
locally while an install job is in flight (§6). Check
`gh run list --limit 8 --json status` first.

## Rollback

Reverting the commit restores today's behaviour exactly: `dictation` goes back
to `attr = "voxtype"`, the option and bridge disappear, `appBinary` stops
reading `binary`, and the seeded config is left where it is — it is the user's
file and removing it is not this change's business. Nothing enters a system
closure for a machine with dictation off, and no default changes.

## What this plan does not claim

That dictation will work on a given machine. It claims the daemon runs from a
stable path with a config the user owns and a model that is fetched visibly.
The failure this issue is really about — a feature that looks installed and
does nothing — has a second form this cannot rule out: a daemon reporting
`active` with no microphone, no `input` membership, or no usable PipeWire
source. Step 9 is the only thing that tests for it, and step 7 says so in the
tree rather than leaving it implied.
