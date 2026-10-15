---
status: draft
issue: 1285
intent: intent/2026-10-15-1285-quattro-hardware-ports.md
---

# Spec: fprintd survives suspend, and the boot splash re-centres for a late display

## Design

### 1. fprintd after resume

In `modules/nixos.nix`, inside `mkIf cfg.enable`, beside the existing
fprintd block (~:1751, `lib.optionalAttrs config.services.fprintd.enable`):

```nix
powerManagement.resumeCommands = lib.mkIf config.services.fprintd.enable ''
  # Suspend can wedge fprintd's device claim (fprintd#173, carried by Omarchy).
  ${config.systemd.package}/bin/systemctl --no-block try-restart fprintd.service || true
'';
systemd.services.fprintd.serviceConfig.TimeoutStopSec = lib.mkIf config.services.fprintd.enable (lib.mkDefault "3s");
```

- **`resumeCommands` rather than a unit.** NixOS runs these from
  `post-resume.service` after every sleep kind: suspend, hibernate, hybrid
  and suspend-then-hibernate. That is what upstream's `post` sleep hook
  covers. It is a `lines` option that merges with a machine's own resume
  commands, so it takes a plain assignment (§7). A dedicated unit would
  have to list each sleep target to match it, for nothing more.
- **`--no-block`, as upstream:** `user.slice` stays frozen until resume
  handling returns, so the restart is enqueued, not awaited.
  `try-restart` does nothing when fprintd is not running, since it is
  D-Bus activated.
- **`TimeoutStopSec` at `mkDefault`,** so a machine's own value wins.
- **Mode A is untouched.** Both settings sit inside `mkIf cfg.enable`, and
  each is gated on `services.fprintd.enable`, which nixarchy does not turn
  on.

On **edge**, `omarchy-apply-lock` still tries to install
`/usr/lib/systemd/system-sleep/fprintd-resume` and the drop-in at runtime.
A carry commit makes those two installs no-ops, since the configuration
now provides both. The `apply-lock` entry then leaves #1280's list.
`remove-security-fingerprint`'s `rm` of that path is harmless and stays.
The carry follows edge's merge of `main`; it is not part of this PR, which
touches `main` only.

### 2. The splash re-centres

`pkgs/omarchy/nixarchy-plymouth.script` positions the following once, at
load, from `Window.GetWidth()` and `Window.GetHeight()`:

- the animation frames (:30-31);
- the logo (:40-41);
- the password entry and lock (~:173-188);
- the progress box and bar (~:259-270).

Bullets are positioned from `entry.x`/`entry.y` as they are created.

Port upstream's shape, keeping nixarchy's own offsets:

- **A `layout()` function** holds every one of those positioning statements,
  unchanged, and records `global.layout_width` and `global.layout_height`.
- **The positioning statements at load** are removed from the top level, and
  `layout()` is called once after the sprites exist.
- **`refresh_callback()`**, nixarchy's, at :68, begins with upstream's
  guard: if the window size differs from the recorded one, call
  `layout()`. That is two integer comparisons per frame and nothing else
  when nothing changed.
- **Bullets that already exist** are re-positioned in `layout()`, through a
  `position_bullet(index)` helper as upstream has. Their creation calls it
  too, so a password typed before the display arrived stays aligned.

The upstream hash guard in `pkgs/omarchy/default.nix` (~:1718) is for
*upstream's* script and does not change on `main`, whose `v4.0.4` predates
the change. On edge, it was acknowledged in the seed.

### The checks

- **`checks.options`:**
  - with nixarchy and fprintd on, `powerManagement.resumeCommands` contains
    the `try-restart fprintd.service` line and `TimeoutStopSec` is `"3s"`;
  - with fprintd off, or with nixarchy off (Mode A), neither is set;
  - a machine's own `TimeoutStopSec` wins.

  This follows the file's both-states pattern.
- **`checks.plymouth-layout` (new, `runCommand`).** No VM can resize
  plymouth's window mid-boot, so this asserts the script's structure, so
  the property cannot silently regress:
  1. no `SetX`/`SetY`/`SetPosition` on a positioned sprite at top level,
     outside `layout()` and `position_bullet()`;
  2. `layout()` is called once at top level;
  3. `refresh_callback` compares `Window.GetWidth()`/`GetHeight()` with the
     recorded size and calls `layout()` on a difference.

  It reads the script by brace depth, not by line ranges.

  **Red proofs:** move one `SetPosition` back to top level, or drop the
  guard from `refresh_callback`. Each must fail.

### The hardware-only part, recorded (§3)

These have no layer in this repo that can show them:

- that fprintd recovers after a real suspend with a real reader;
- that the splash re-centres for a real late display.

So:

- `tests/AGENTS.md` gains a short section naming both as hardware-only;
- `pkgs/verify.sh` gains a line for the fingerprint case, if it has a
  fingerprint section; otherwise the AGENTS.md note says it has none;
- `tests/install-matrix.py` is left alone (it is about installs).

### Docs

- **No manual change.** Both are fixes to behaviour the manual already
  promises: the fingerprint lock, and the boot splash.
- `modules/AGENTS.md`'s fprintd lock note (beside ~:1751) gains one line
  for the resume restart.

### Coexistence

`powerManagement.resumeCommands` merges as lines, so a user's own resume
commands are kept alongside ours. `TimeoutStopSec` is `mkDefault`, so a
user's value wins. No collision can fail a build or shadow a file, so
there is no fixture (§14), for the same reason as before.

## Alternatives rejected

- **Installing upstream's sleep-hook file through
  `environment.etc."systemd/system-sleep/…"`.** NixOS' systemd reads sleep
  hooks from the store's lib dir, not `/etc`, so it would never run.
  `resumeCommands` is the supported mechanism.
- **A dedicated `fprintd-resume.service`, `after` every sleep target.** It
  duplicates what `post-resume.service` already does, with more surface to
  get wrong.
- **Leaving the splash script alone, since a late display is rare.** The
  owner asked for it, and it is a small, contained port.
- **Replacing nixarchy's splash script with upstream's.** nixarchy's is its
  own branding and layout (the snowflake logo, its own assets). Only the
  re-layout behaviour is ported.

## Risks

- **`try-restart` during resume while the lock screen is asking for a
  fingerprint:**
  - a restart in flight may drop that first attempt;
  - pam_fprintd then retries, or the password path is still there.

  This matches upstream, which accepted the same trade.
- **The splash refactor could shift a sprite** if a positioning statement
  depended on something computed after it at top level.
  - Move statements in their existing order.
  - The composited `preview-unlock.png` (`pkgs/omarchy/default.nix` ~:1744)
    is computed from the assets, not from the script, so it does not
    check the script.
  - Mitigation: read the diff carefully. `checks.plymouth-layout` holds
    the structure; it does not hold the pixels.
- **Plymouth script quirks.** It is not JavaScript: functions see globals
  only through `global.`, and a missing sprite is silent. Follow upstream's
  `global.layout_width` shape exactly.

## Verification

| Check | Proves | Fails when |
|---|---|---|
| `checks.options` | resume restart and stop timeout only where nixarchy and fprintd are both on; a user's timeout wins; Mode A has neither | the gate or the priority is wrong |
| `checks.plymouth-layout` | positioning lives only in `layout()`/`position_bullet()`, and `refresh_callback` re-runs it on a size change | a `SetPosition` returns to top level, or the guard is dropped |
| `checks.omarchy` (the package) | the script still installs as the theme's `omarchy.script` | — |
| hardware | fprintd after a real suspend; the splash with a late Thunderbolt display | recorded in `tests/AGENTS.md`, not automated |
