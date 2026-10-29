---
status: approved
issue: 1506
intent: intent/2026-10-29-1506-qemu-gl-exit-crash.md
---

# Spec: stopping a GPU microvm does not crash qemu

## Measured first (2026-10-29, p620)

**Setup:**
- Host: p620, one AMD GPU (`renderD128`, vendor `0x1002`), Mesa 26.2.4,
  qemu-host-cpu-only 11.1.2.
- Guest: the `hyprland-ai-mirror` template, so each run could be checked
  end to end over MCP.
- Each run: boot, grant control, `launch`, type, `screenshot`, then stop
  qemu. Afterwards I counted new qemu entries in `coredumpctl`.

| Variant | qemu args | Guest works | Core dumps on exit |
|---|---|---|---|
| Today (`graphics.backend = "headless"`) | `-display egl-headless -device virtio-gpu-gl` | Yes | 1 per exit. 16 on 2026-10-29, from SIGTERM, `vm stop` (QMP) and a failed start |
| Today + `GALLIUM_THREAD=0` | same | Yes | **1.** Mesa's threaded context is not the cause |
| `rendernode=` | n/a | n/a | Not tried. p620 has a single render node, so it is already the one used |
| **No GL:** `graphics.enable = false` + `-device virtio-gpu-pci` | `-nographic -device virtio-gpu-pci` | **Yes** (2 runs). Grant at 6.3 s, `launch foot`, typing and screenshot all work. Hyprland renders with Mesa's software renderer in the guest | **0** (3 runs, all SIGTERM) |

On the no-GL guest, Chromium with `--ozone-platform=wayland` renders a
page, and `a11y_find` returns its button, so the template's purpose
(#821: desktop automation, accessibility-forced Chromium) is kept.

**Found on the way, not caused by this change.** On **both** variants,
`chromium` started with no flags opens no window within 80 s. It defaults
to X11, and the guest has neither Xwayland nor `NIXOS_OZONE_WL`. This is a
separate defect in the `hyprland` template. Separate issue proposed.

## Design

In `modules/microvm/templates/hyprland.nix`, replace

```nix
graphics.enable = true;
graphics.backend = "headless";
```

with a virtio GPU that has no host GL behind it:

```nix
# A DRM device for aquamarine, and no host GL behind it: ... (#1506)
qemu.extraArgs = [ "-device" "virtio-gpu-pci" ];
```

- **`graphics.enable` falls back to microvm.nix's default, `false`.** The
  runner then passes `-nographic`. That opens no window and keeps the
  serial console on stdio, as the template already relies on (`guest.nix`).
  It also drops the USB tablet and keyboard, which nothing uses: input
  reaches the guest through Wayland virtual devices (ai-mirror, wtype).
- **PCI stays on.** `requirePci` is already true because the guest has a 9p
  share (`lib/runners/qemu.nix:61-65`).
- **The guest side is unchanged:** `hardware.graphics.enable`, seatd, the
  `video`/`render`/`seat` groups and the a11y settings all stay. aquamarine
  still opens `/dev/dri/card0` (virtio_gpu KMS), and GBM still has a Mesa
  driver.
- **The header comment is rewritten** to say why there is no GL: the
  radeonsi teardown crash, and that the guest renders in software. The
  comment block that explained `graphics.backend = "headless"` goes away.
- **`hyprland-ai-mirror` inherits the change** through
  `imports = [ ./hyprland.nix ]`. No edit there.

**Upstream report.** I draft a bug report for Mesa (radeonsi:
`si_delete_shader_selector` during `_mesa_make_current` at qemu's
egl-headless teardown) with the backtrace and versions. Filing it on
gitlab.freedesktop.org is outward-facing, so I file it only with your
OK. Its link is recorded in the template comment.

## Alternatives rejected

- **`GALLIUM_THREAD=0`.** Measured: it still crashes.
- **Suppressing the core dump** with `LimitCORE=0` on the runner, or
  filtering notifications. It would hide a real crash while a VM runs. The
  intent rules it out.
- **`-display dbus,gl=on` or another GL display.** It still tears down a
  host GL context through the same radeonsi path, and it needs a D-Bus
  consumer. Not worth measuring while a no-GL option works.
- **Waiting for a Mesa or qemu fix.** The notifications happen today. The
  no-GL guest can be switched back once upstream fixes the crash.

## Risks

- **Rendering cost moves to guest CPU.** Software rendering at 1920x1080 in
  a 1-vCPU guest. Measured: grant, launch and typing were as fast or faster
  (grant 6.3 s vs 8.7–19 s), and Chromium rendered. A GL-heavy app under
  test (WebGL, games) would be slow. The note says so.
- **Hosts other than p620.** A non-GL virtio GPU needs no host GPU at all,
  so this also removes the host-GL dependency on Intel, NVIDIA and
  GPU-less hosts. That is likely an improvement, but unmeasured there.
- **`-tcg` runner:** unchanged in kind. Software rendering under TCG is
  slow either way.
- **Hyprland shows a ".conf format will be removed in 0.57" warning**
  toast in the guest. That is the template's config format, unrelated to
  this change, and it gets a separate note.

## Verification

- `nix build .#checks.x86_64-linux.microvm-template` passes, KVM and TCG.
- Both runners have `virtio-gpu-pci` and no `egl-headless` or
  `virtio-gpu-gl`: grep the built `microvm-run`.
- **Live, on p620, through the branch's `nixarchy vm`:**
  - `vm create`, `vm run --detach`, then the MCP probe:
    - grant, launch foot, typed text in the screenshot;
    - Chromium with `--ozone-platform=wayland` is found by `a11y_find`.
  - Then `nixarchy vm stop`, the QMP path. Run this twice: **0** new qemu
    core dumps.
