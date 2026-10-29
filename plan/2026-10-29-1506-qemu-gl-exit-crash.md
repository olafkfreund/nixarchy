---
status: draft
issue: 1506
spec: spec/2026-10-29-1506-qemu-gl-exit-crash.md
---

# Plan: stopping a GPU microvm does not crash qemu

## Approved decisions, carried over

- **The `hyprland` template gets a virtio GPU with no host GL behind it.**
  Delete `graphics.enable = true;` and `graphics.backend = "headless";`, and
  add `qemu.extraArgs = [ "-device" "virtio-gpu-pci" ];`. The runner then
  passes `-nographic -device virtio-gpu-pci` and no
  `-display egl-headless -device virtio-gpu-gl`.
- **Why:** measured on p620 (AMD, Mesa 26.2.4, qemu 11.1.2).
  - The GL path crashes qemu on every exit: SIGSEGV in radeonsi
    `si_delete_shader_selector` during `_mesa_make_current`.
  - `GALLIUM_THREAD=0` does not help.
  - The no-GL device gave 0 crashes in 3 runs, and the guest works: grant
    in 6.3 s, launch and typing, and Chromium with
    `--ozone-platform=wayland`, found by `a11y_find`.
- **The guest side is unchanged:** `hardware.graphics.enable`, seatd,
  groups, a11y. The guest renders with Mesa's software renderer.
- **`hyprland-ai-mirror` inherits the change** through its import. No edit
  there.
- **No core dump or notification suppression.**
- **Upstream:** a Mesa bug report is drafted, and the user files it.
- **Out of scope, as separate issues:**
  - Chromium opens no window without `--ozone-platform=wayland`. This is
    true before and after the change.
  - The template's `.conf` format is removed in Hyprland 0.57.

## Steps

1. **`modules/microvm/templates/hyprland.nix:71-79`.** Make the edit
   above.
   - Replace the comment above it (`:71-76`, "A GPU, and no window on the
     host…") with one that says:
     - the guest needs a DRM device for aquamarine/GBM, but no host GL;
     - the host-GL path (`graphics.backend = "headless"`:
       `egl-headless` + `virtio-gpu-gl`) crashed qemu in radeonsi on every
       exit on p620, and that raised a crash notification each time
       (#1506);
     - `graphics.enable` stays at microvm.nix's default `false`, which is
       `-nographic`: no host window, and the serial console on stdio;
     - the guest renders in software, so GL-heavy apps under test are slow.
   - **`:96-99`** (`hardware.graphics.enable` comment): replace "mesa ships
     virtio_gpu_dri.so, which is the driver this device wants" with the
     truth now: there is no virgl behind the device, so Mesa renders in
     software (llvmpipe) on the virtio_gpu KMS device.
   - Verify:
     - `nix build .#microvm-hyprland .#microvm-hyprland-tcg .#microvm-hyprland-ai-mirror`
       exits 0;
     - `grep -c 'egl-headless\|virtio-gpu-gl'` on each `bin/microvm-run`
       is `0`, and `grep -c 'virtio-gpu-pci'` is `1`;
     - `nix fmt -- --ci`, `statix` and `deadnix` are clean.
   - Traps:
     - An editor hook may reformat `.nix` with nixpkgs-fmt (AGENTS.md
       #897). Edit with a script, run `nix fmt`, and read
       `git diff --stat`.
     - Check `nix build`'s **exit status**, not its last line (AGENTS.md,
       #1504).

2. **`data/microvm-templates.nix:62` and the `hyprland` row in
   `docs/manual/sandboxes.md:83`:** add one sentence to each. It says the
   guest renders in software (there is no host GPU behind its virtio GPU,
   #1506), so WebGL and other GL-heavy apps are slow.
   - Verify:
     - `nix build .#checks.x86_64-linux.microvm-template --print-build-logs`
       exits 0;
     - the docs table still has 3 columns.
   - Traps: none.

3. **Live check on p620** (Opus, not the coder). Build the branch's
   `nixarchy-vm` from the pushed commit, with a scratch `XDG_STATE_HOME`.
   1. `vm create t --template hyprland-ai-mirror`, then
      `vm run --detach t`.
   2. Run the MCP probe: grant, `launch foot`, typed text in the
      screenshot.
   3. Run the Chromium probe (`--ozone-platform=wayland`): `a11y_find`
      returns the button.
   4. `nixarchy vm stop t`, the **QMP** path.
   5. Repeat 1, 2 and 4 once more.
   - Expect **0** new qemu entries in `coredumpctl` across both stops.
   - Record the results here.
   - Traps:
     - The CLI builds `github:olafkfreund/nixarchy/<rev>`, so push before
       building `nixarchy-vm`.
     - Remove both VMs afterwards.

4. **Side issues and the upstream draft** (Opus):
   - Open two nixarchy issues: Chromium needs Wayland ozone in the
     `hyprland` template, and the template's `.conf` format is removed in
     Hyprland 0.57.
   - Write the Mesa report to the scratchpad for the user to file.

## Tests

```sh
nix fmt -- --ci
nix run --inputs-from . nixpkgs#statix -- check .
nix run --inputs-from . nixpkgs#deadnix -- --fail .
nix build .#checks.x86_64-linux.microvm-template --print-build-logs
```

Expected: all green. Step 3 is the behavioural test. CI boots no guest.

## Rollback

Revert the commit. That puts back `graphics.enable = true;` and
`graphics.backend = "headless"`, and with them GL and the crash on exit.
