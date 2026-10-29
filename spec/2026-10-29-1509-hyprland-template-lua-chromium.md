---
status: approved
issue: 1509
intent: intent/2026-10-29-1509-hyprland-template-lua-chromium.md
---

# Spec: the hyprland template uses Lua config and start-hyprland, and its Chromium opens a window

Covers #1509 and #1510. All changes are in `modules/microvm/templates/hyprland.nix`
and a check; `hyprland-ai-mirror` inherits them by importing it.

## Design

### 1. Lua config (#1510)

Replace `environment.etc."hypr/hyprland.conf"` with
`environment.etc."hypr/hyprland.lua"`. It carries the same four settings, in
the API the host desktop already uses (Omarchy's `monitors.lua` and
`looknfeel.lua`):

```lua
hl.monitor({ output = "Virtual-1", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.config({
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true },
  debug = { disable_logs = false, enable_stdout_logs = true },
})
```

The existing comments move with their settings: why the monitor rule names
the connector, and why logs go to stdout. Hyprland picks the Lua parser from
the `.lua` extension of `--config`; the host passes `--config …/hyprland.lua`
the same way (`modules/nixos.nix:135`).

Measured on 2026-10-29 with the guest's Hyprland 0.56.2: `Hyprland
--verify-config --config <file>.lua` prints `config ok` for the file above.
With one key misspelt, it prints `unknown config key
'misc.disable_splash_renderingX'`. (Corrected while implementing: it exits 1 on the bad file; the "exit 0" reading was a pipe's status. See the plan's Deviations.) A check must
match the text, not the status.

### 2. start-hyprland (#1510, the owner's decision)

```
ExecStart = "${pkgs.hyprland}/bin/start-hyprland -- --config /etc/hypr/hyprland.lua";
```

`start-hyprland` is a watchdog: it runs `Hyprland --watchdog-fd <n>`, which
is what stops the "started without start-hyprland" warning. Under
`Restart = "no"` the unit still does not restart, **but start-hyprland itself
does**: its strings include `Hyprland exit not-cleanly, restarting` and
`--safe-mode`. So a compositor that crashes is restarted once by the watchdog,
possibly in safe mode, which loads a minimal config and would drop the
`Virtual-1` rule. That trades against the existing comment's "a failure that
stays failed is discoverable". The trade is the owner's choice. The comment is
rewritten to say what now happens: a crash shows as a restart in
`journalctl --user -u hyprland`, and a safe-mode run shows as the wrong output
size. The live boot measures this once, by crashing the compositor (step
"Verification" 4).

### 3. Chromium opens a Wayland window (#1509)

Add `--ozone-platform=wayland` to the existing override:

```nix
(chromium.override { commandLineArgs = "--force-renderer-accessibility --ozone-platform=wayland"; })
```

This is the wrapper, not an environment variable, so it reaches every way of
starting Chromium: ai-mirror's `launch` from a systemd user service with no
login, a terminal, or a script. `NIXOS_OZONE_WL` is rejected below. The
template's `note` in `data/microvm-templates.nix` already calls this override
opinionated; it gains "and Wayland".

### 4. The host desktop

The intent asked to find the host path that shows the start-hyprland warning.
Findings:

- `omarchy.desktop` (`modules/nixos.nix:133`) already runs
  `uwsm … start-hyprland -- --config …`.
- `checks.coexist` (`tests/coexist.nix:139-153`) already fails if the journal
  of a booted session contains `without start-hyprland`.
- On p620 on 2026-10-29, the running session had `--watchdog-fd 4`, and neither
  its Hyprland log nor the user journal held the warning.
- The stock `hyprland.desktop` and `hyprland-uwsm.desktop` both go through
  `start-hyprland` too.

So nothing here changes the host. The owner's warning is most likely the
in-guest toast (#1510's screenshot) or an older generation. If it appears on
the host again, a screenshot plus `journalctl --user -b -g start-hyprland`
reopens it as its own issue; this spec does not guess at a fix.

### 5. The check

Extend `tests/microvm-ai-mirror.nix`, which already evaluates
`hyprland-ai-mirror` (and so `hyprland.nix`) as values. It boots nothing:

- **(d) The Lua config parses.** Write the evaluated
  `environment.etc."hypr/hyprland.lua".text` to a file, and run
  `${pkgs.hyprland}/bin/Hyprland --verify-config --config` on it, with `HOME`
  and `XDG_RUNTIME_DIR` set to a temporary directory. Require `config ok` in
  the output, and require each of `Virtual-1`, `1920x1080`,
  `disable_splash_rendering` and `enable_stdout_logs` in the text. Fail if
  `environment.etc` still has `hypr/hyprland.conf`.
- **(e) Wiring, as values.** The hyprland unit's `ExecStart` contains
  `/bin/start-hyprland -- --config /etc/hypr/hyprland.lua`. The Chromium in
  `environment.systemPackages` carries `--ozone-platform=wayland` and
  `--force-renderer-accessibility`. Read it from the wrapper's text with
  `unsafeDiscardStringContext`, so no Chromium is built. The plan picks the
  exact attribute after reading the wrapper.

§1 breaks, each of which must turn the check red:

- (i) Misspell one Lua key.
- (ii) Put `hyprland.conf` back.
- (iii) Change ExecStart back to `bin/Hyprland`.
- (iv) Drop `--ozone-platform=wayland`.

The name `microvm-ai-mirror` stays. It already reads the `hyprland` half, and
a second check would evaluate the same guest again.

## Alternatives rejected

- **`NIXOS_OZONE_WL=1` as a session variable.** It reaches a login shell
  through `/etc/set-environment`, and nixpkgs' Chromium wrapper reads it.
  But ai-mirror's listener is a systemd user service in a lingering manager
  with no login, which is #1509's own open question, and a session variable
  is the thing that does not reach there. The wrapper flag has no such gap.
- **Keep `Hyprland` and silence the warning.** The owner chose start-hyprland.
- **Keep `.conf` until 0.57 lands.** The first symptom would be a silent
  change of output size, which every capture depends on.
- **A separate check for the hyprland template.** It would evaluate the same
  guest a second time for the same values.

## Risks

- **Watchdog restart and safe mode** (Design 2): a crash no longer stays
  failed. This is measured once in the live boot, and the comment says how a
  caller sees it.
- **`--verify-config` may need more than HOME and XDG_RUNTIME_DIR in the
  build sandbox.** If it does, the plan records what it needed. It must not
  fall back to text-matching only, because the parse is the point.
- **Wayland-only Chromium:** a caller that wanted X11 has no Xwayland in this
  guest anyway, so nothing that worked before stops working.
- **Mode A and coexistence (§14):** none. The template is opt-in and guest-only.
- **#1513** imports neither file's config, and its owner confirmed there is no
  textual overlap. Its step 1 pins `hyprland-ai-mirror`'s toplevel; this
  change moves that toplevel, which is expected.

## Verification

- `checks.microvm-ai-mirror` is green, and red under each of breaks (i)–(iv).
- `test-registration`, `grep-q-pipefail`, statix, deadnix and `nix fmt -- --ci`
  pass.
- **Live on p620**, with nothing running in CI, using a fresh `hyprland-ai-mirror`
  VM built from the branch:
  1. A screenshot shows no `.conf` toast and no start-hyprland toast.
  2. `hyprctl monitors` reports `Virtual-1` at 1920x1080.
  3. `launch chromium` with no flags gives a window in `windows` within 30 s,
     and `a11y_find` returns its controls.
  4. `kill -SEGV` the compositor once. Record what `start-hyprland` does: the
     restart, whether it ran in safe mode, and the output size afterwards.
     That result goes into the comment.
- The owner's `ai-mirror` VM is left running throughout.
