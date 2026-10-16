---
status: approved
issue: 1285
author: olafkfreund
---

# Intent: fprintd survives suspend, and the boot splash re-centres for a late display

## Problem

Omarchy `quattro` carries two hardware fixes that nixarchy has no equivalent
for. Both matter on stable machines today, not only on edge.

1. **The fingerprint reader can be dead after suspend.** Suspend can wedge
   fprintd's claim on the device
   ([fprintd#173](https://gitlab.freedesktop.org/libfprint/fprintd/-/issues/173)),
   and a stale handle can make fprintd ignore SIGTERM. quattro works around
   both:
   - a system-sleep hook that restarts fprintd after resume, without
     waiting;
   - a `TimeoutStopSec=3s` drop-in for `fprintd.service`.

   It installs them at runtime from `omarchy-apply-lock`, into
   `/usr/lib/systemd/system-sleep` and `/etc/systemd/system`. Neither
   location can be written on NixOS. On edge that write is also one of the
   two reasons `apply-lock` is a named `/usr` exception (#1280).
2. **The boot splash is off-centre when a display arrives late.**
   nixarchy's own `pkgs/omarchy/nixarchy-plymouth.script` positions the logo
   and the password field once. A Thunderbolt monitor whose DisplayPort
   tunnel comes up after plymouthd starts grows the window, and everything
   stays where it was. quattro's `omarchy.script` re-runs a `layout()` when
   the window size changes. The edge seeding only acknowledged that change
   (a hash bump); this ports it.

## Proposed outcome

- **The reader keeps working after resume.** On any nixarchy machine with
  `services.fprintd.enable`, fprintd is restarted after resume and stops
  within 3 s. It is declared, not installed at runtime, so it survives a
  rebuild and needs no enrolment step to appear.
- **On edge**, `omarchy-apply-lock` no longer tries to write those two
  files, and the fingerprint resume hook drops off #1280's list.
- **nixarchy's boot splash re-centres** when the display grows, as
  upstream's does.

## Affected users and systems

- **Machines:** those with a fingerprint reader and `services.fprintd.enable`,
  and machines whose display comes up after the splash starts (Thunderbolt
  docks, some eGPUs).
- **Code:**
  - `modules/nixos.nix`: fprintd, inside `mkIf cfg.enable` and the existing
    fprintd gate (~:1751);
  - `pkgs/omarchy/nixarchy-plymouth.script`;
  - its hash guard in `pkgs/omarchy/default.nix`, if the script's checks
    reference it;
  - an edge carry for `apply-lock`;
  - tests.

## Constraints

- **Mode A is untouched.** Nothing is set when nixarchy is off, and the
  fprintd parts apply only where `services.fprintd.enable` is already on.
  nixarchy does not turn fprintd on.
- **Priorities.** `mkDefault` on `TimeoutStopSec`, so a machine's own value
  wins. The resume action is additive.
- **No sleep hook under /usr.** Use NixOS' own resume mechanism
  (`powerManagement.resumeCommands`, or a unit ordered after
  `suspend.target` and its siblings).
- **The splash port keeps nixarchy's own layout.** The logo, password field
  and progress bar keep their offsets. Only re-run them on a size change,
  and do no work on frames where the size has not changed.
- **Every check is proven to fail first** (§1). Real suspend-and-resume and
  a late display cannot be produced in a VM, so the spec must say which
  part is held by evaluation and which by reading the script, and record
  the hardware-only gap per §3.

## Open questions

1. **`powerManagement.resumeCommands` or a dedicated unit.**
   `resumeCommands` run in `post-resume.service`, after every sleep type. A
   unit gives finer ordering. Resolve in the spec.
2. **How to check the splash change.** No VM resizes plymouth's window
   mid-boot. Candidates:
   - a static check that `refresh_callback` calls the layout function on a
     size change;
   - running the script's layout in plymouth's script interpreter, if one
     can be driven headless.

   Resolve in the spec.
