---
status: approved
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

## Deviation — 2026-09-24: a migration step the plan did not have

Found while establishing step 9's preconditions on razer, before any rebuild.

**The fix as planned would have broken the machines it was written for.**

razer carries a **real file** at `~/.config/systemd/user/voxtype.service`,
active and enabled:

```
-rw-r--r-- 1 olafkfreund users 424 …/.config/systemd/user/voxtype.service
ExecStart=/nix/store/hf9lrj7…-voxtype-1.0.1/bin/.voxtype-wrapped daemon
WantedBy=graphical-session.target
```

That is what `voxtype setup systemd` writes, and it is the state of anyone who
followed Omarchy's own install instructions — which is precisely the population
this issue exists for. Home Manager writes its user units into the same
directory, and `checkLinkTargets` refuses to replace a real file it does not
own. So `dictation.enable = true` would not have fixed dictation on those
machines; it would have failed `home-manager-<user>.service`.

`modules/AGENTS.md:1459` records the identical collision from nixi 0.9 → 0.10
and says outright that any module making the same move needs the same step.
This is that step.

### What was added

`home.activation.nixarchyVoxtypeUnitMigration` in `modules/home.nix`, anchored
`entryBefore [ "checkLinkTargets" ]` — every other activation in this file is
`entryAfter [ "writeBoundary" ]`, which is far too late, and `checkLinkTargets`
is itself `entryBefore [ "writeBoundary" ]`.

**Narrow three ways, because the failure mode here is deleting something that
is not ours:**

1. It runs only when dictation is being turned **on**. A machine that leaves it
   off keeps whatever unit its owner wrote — we are not taking the name over.
2. It removes only a real **file**, never a symlink, which is what Home
   Manager's own unit would be.
3. It matches on `.voxtype-wrapped`, the signature of `voxtype setup systemd`.
   A unit somebody wrote by hand for their own reasons contains no wrapped
   store path and is left alone.

It also removes any `*.wants/voxtype.service` enable symlinks, or systemd is
left pointing at a unit that no longer exists and says so on every reload.

### Proved against all four shapes, with the guard lifted verbatim

```
a  hand-written (.voxtype-wrapped)  acted=yes  unit=gone     wants=0
b  someone's own unit               acted=no   unit=present  wants=0
c  Home Manager's symlink           acted=no   unit=present  wants=0
d  nothing there                    acted=no   unit=gone     wants=0
```

Row **b** is the one that matters: a guard that removed that file would be
destroying a user's own configuration to install ours.

And the gating, measured on the real module: the activation is present with
dictation on and absent with it off.

### Step 9's other preconditions, checked on razer

All green, so the hardware test is not blocked on anything else: the user is in
`input`, PipeWire offers a capture source, voxtype 1.0.1 is present, and the
142 MB model is **already downloaded** — so `loadModels` has nothing to fetch
there and that risk is not exercised by this particular test. A machine without
the model is still untested.

## Step 9 — the hardware result, 2026-09-24

razer, switched to this branch with `--override-input`, `dictation.enable` was
already true in `~/.config/nixarchy/apps.nix` (since 21 Sep — which is how the
bug was found in the first place).

**The migration fired on its first real machine, and it was needed.** Before:

```
-rw-r--r-- ~/.config/systemd/user/voxtype.service    (a real file)
ExecStart=/nix/store/hf9lrj7…/bin/.voxtype-wrapped daemon
```

After:

```
~/.config/systemd/user/voxtype.service -> /nix/store/…-home-manager-files/…
ExecStart=/nix/store/hf9lrj7…/bin/voxtype daemon
After=graphical-session.target
After=pipewire.service
voxtype: active          voxtype-model-loader: active
voxtype status: idle
~/.config/voxtype/config.toml   -rw-r--r--  mtime 11:10  (untouched)
```

Without the migration this switch would have failed at `checkLinkTargets`, so
the deviation above is not hypothetical — it was the difference between the fix
working and the rebuild erroring on the machine the issue was filed from.

The model loader found the existing weights rather than re-downloading:
`✓ Model ready: base.en (141 MB)`.

**What this run did NOT prove**, and it is the honest half:

- **Dictation itself.** Holding F9 and speaking is the owner's to do. The
  daemon answers `idle`, which is the wiring and not the feature.
- **The download path.** razer already had the 142 MB model, so `loadModels`
  fetched nothing. A machine without it is still untested.
- **Survival across an upgrade and a GC**, which is the failure that produced
  the issue.

### An unrelated blocker found on the way, now #947

Current `main` imports `nix-snapd`'s module itself, and razer's own flake
imports it too, so evaluation failed before anything could be tested:

```
error: The option `services.snap.enable' … is already declared in …
```

Both halves name the **same store path** — one module imported as two values,
which the module system cannot dedupe. razer's pin (`3ed0dea`) does not
reference nix-snapd; `main` does. So it is triggered by the pin bump alone and
has nothing to do with dictation. Filed as #947; razer's flake was edited
temporarily to test, and reverted afterwards.
