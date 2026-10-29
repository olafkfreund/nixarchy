---
status: approved
issue: 1506
author: olafkfreund
---

# Intent: stopping a GPU microvm does not crash qemu

## Problem

Every exit of a microvm with `microvm.graphics.backend = "headless"`
(`-display egl-headless -device virtio-gpu-gl`) ends in a qemu SIGSEGV on
p620. That covers the `hyprland` template (#821) and `hyprland-ai-mirror`
(#1505). systemd-coredump catches each crash, and the desktop shows a
"Process crashed" notification. On 2026-10-29 that was 16 qemu core dumps
in a day.

The crash is in Mesa's radeonsi driver while qemu tears its GL context
down: `si_delete_shader_selector` ← `tc_flush` ← `st_glFlush` ←
`_mesa_make_current` (libgallium 26.2.4, qemu-host-cpu-only 11.1.2). Every
exit path crashes the same way:
- SIGTERM to the runner;
- `nixarchy vm stop` (a clean QMP `system_powerdown`);
- a qemu that failed to start.

The guest works while it runs. The harm is twofold:
- a crash notification on every stop, which the user has already noticed
  and asked about;
- 16 core dumps a day that bury a real crash of something else in
  `coredumpctl`.

## Proposed outcome

- Stopping a `hyprland`-family microvm, by any route, leaves no qemu core
  dump and raises no crash notification.
- The guest keeps its GPU device and everything that works today: grim, the
  accessibility tree, ai-mirror driving it, and the 1920x1080 output.
- A real qemu crash while a VM is **running** is still reported. The fix
  must not hide crashes in general.

## Affected users and systems

- Users of the `hyprland` and `hyprland-ai-mirror` templates, and anything
  else that sets `microvm.graphics.backend = "headless"`.
- Seen on p620 (AMD radeonsi). Unknown on Intel or NVIDIA hosts, so the spec
  measures what it can.
- Probably `modules/microvm/templates/hyprland.nix` (the display settings),
  or the runner and its unit in `pkgs/microvm.nix`.

## Constraints

- **No root and no rebuild** for `nixarchy vm run` (#221).
- **No window on the host desktop** (the `hyprland.nix` header): the
  backend must stay headless.
- **No global coredump or notification suppression.** `LimitCORE=0` or a
  notification filter for qemu would hide real crashes. The constraint
  above rules them out unless the spec shows the crash is exit-only and
  the limit can apply only at exit.
- **Fix at the right layer.** If it is a Mesa or qemu bug, report it
  upstream and carry the smallest workaround, recorded in the repo's
  upstream-tracking notes.

## Open questions

1. **Where to fix.** Candidates, to be measured in the spec:
   - a qemu display option (`egl-headless,rendernode=…`, or a different
     GL path such as `-display dbus` or `-display none` with
     `virtio-gpu-gl`);
   - a different Mesa or qemu version;
   - a graceful-exit order that avoids the teardown.

   Proposed: measure the cheap qemu options first, and report upstream
   either way.
2. **Should the guest keep a GL-accelerated GPU, if only a non-GL device
   avoids the crash?** Proposed: no. The template asks for a GPU because
   aquamarine's GBM needs a DRM device. If plain `virtio-gpu` (no `-gl`)
   is enough for Hyprland with software rendering, a slower but crash-free
   guest is acceptable. The spec measures that before deciding.

## Decisions (owner, 2026-10-29)

Approved with the proposed answers: 1. measure cheap qemu options first,
report upstream either way; 2. a non-GL GPU is acceptable if Hyprland runs
on it.
