---
name: nixos-gpu
description: >
  REQUIRED for GPU compute and driver setup on this NixOS machine — NVIDIA/CUDA,
  AMD/ROCm, Intel, and VA-API video acceleration. Use when asked to install CUDA,
  install ROCm, set up a GPU for machine learning, get PyTorch or llama.cpp to see
  the GPU, enable nvidia-smi or rocminfo, pass a GPU into Docker or Podman, fix a
  black screen or Hyprland failing to start after a driver change, or configure a
  hybrid/Optimus laptop. Triggers: cuda, cudaSupport, nvidia, nvidia-smi, ROCm,
  rocminfo, HSA_OVERRIDE_GFX_VERSION, amdgpu, hardware.graphics, OpenCL, Vulkan,
  VA-API, nvidia-container-toolkit, PRIME, offload, "GPU not detected".
  For running models on that GPU use `nixos-ai`; for thermals, power and
  throttling use `nixos-performance`.
---

# NixOS GPU Skill

Getting a GPU working on NixOS is **three separate layers**, and almost every
failure is someone doing one of them and expecting the other two.

| Layer | What it is | Set by |
|---|---|---|
| 1. Kernel driver | The GPU shows up at all | `services.xserver.videoDrivers` / `hardware.amdgpu.*` |
| 2. Userspace runtime | `nvidia-smi`, `rocminfo`, OpenCL, Vulkan work | `hardware.graphics.*`, `hardware.nvidia.*` |
| 3. Application build | PyTorch/llama.cpp compiled *with* GPU support | `nixpkgs.config.cudaSupport` or a `-cuda`/`-rocm` package |

A CUDA-less PyTorch on a perfect driver stack still runs on the CPU. That is
layer 3 missing, not a driver problem.

**All of this is route 2 in the `nixos` skill: edit the flake, then rebuild.**
There is no `nixarchy-app-enable` for a GPU stack.

## First: What Hardware Is This?

Never guess. Ask the machine.

```bash
lspci -nn | grep -Ei 'vga|3d|display'      # which GPU(s), and the PCI IDs
nix eval --raw /etc/nixos#nixosConfigurations.$(hostname).config.system.stateVersion 2>/dev/null
lsmod | grep -E 'nvidia|amdgpu|i915|xe'    # which driver is actually loaded now
```

A laptop that lists **both** an Intel/AMD iGPU and an NVIDIA dGPU is a hybrid
(Optimus) machine and needs the PRIME section below, not the plain desktop config.

## NVIDIA and CUDA

### The driver (layers 1 and 2)

```nix
{ config, pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;         # the NVIDIA driver is unfree

  hardware.graphics = {
    enable = true;
    enable32Bit = true;                      # Steam, Wine; harmless otherwise
  };

  services.xserver.videoDrivers = [ "nvidia" ];   # also correct on Wayland/Hyprland

  hardware.nvidia = {
    modesetting.enable = true;               # required for Wayland. Not optional here.
    open = true;                             # see below — must be set explicitly
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = false;          # experimental; enable only to fix suspend
  };
}
```

Notes that matter:

- **`services.xserver.videoDrivers` is not X11-only.** The name is a historical
  wart. On a Wayland compositor like Hyprland it is still the option that loads
  the NVIDIA kernel module and pulls in the userspace libraries. Leaving it out
  because "we don't use X" is a common and confusing failure.
- **`hardware.nvidia.open` has no default** — it is `null or boolean` and the
  build warns until you choose. `true` (the open kernel modules) is right for
  Turing (RTX 20-series) and newer. Set `false` for Maxwell/Pascal/Volta —
  GTX 900/1000-series — where the open modules are unsupported.
- **`modesetting.enable = true` is mandatory for Wayland.** Without it Hyprland
  typically starts to a black screen or refuses the DRM device.
- Driver branches: `nvidiaPackages.stable`, `.beta`, `.production`,
  `.legacy_470`, `.legacy_390`. Very old cards need a legacy branch *and* an
  older kernel; check <https://www.nvidia.com/Download/Find.aspx> for which
  branch supports the card before spending a rebuild.

Verify after `nixos-rebuild switch` **and a reboot** (a kernel module change does
not take effect on `switch` alone):

```bash
nvidia-smi                     # driver + CUDA runtime version, and it lists the GPU
```

### CUDA for development (layer 3)

For a *shell* to build or run CUDA code — the right answer most of the time,
because a CUDA toolchain is huge and rarely needs to be system-wide:

```nix
# flake.nix devShell, or shell.nix
pkgs.mkShell {
  buildInputs = with pkgs.cudaPackages; [ cudatoolkit cudnn ];
  # Many binaries dlopen the driver at runtime rather than linking it:
  LD_LIBRARY_PATH = "/run/opengl-driver/lib";
}
```

`/run/opengl-driver/lib` is where NixOS puts the driver's `libcuda.so`. It is
kept at that path for exactly this reason, despite the OpenGL-era name. A
"cannot find libcuda.so.1" error is nearly always this line missing.

For CUDA-enabled *packages* from nixpkgs (PyTorch, llama.cpp, blender):

```nix
nixpkgs.config.cudaSupport = true;
```

**Be deliberate about this flag.** It changes the build inputs of a large part of
nixpkgs, so most of what you use gets rebuilt from source — hours of compiling,
tens of gigabytes. Prefer a single package override when only one thing needs it:

```nix
environment.systemPackages = [
  (pkgs.llama-cpp.override { cudaSupport = true; })
];
```

or use a package that ships the variant already, e.g. `pkgs.ollama-cuda`.

To limit the compile to your own card and cut build time dramatically:

```nix
nixpkgs.config.cudaCapabilities = [ "8.9" ];   # e.g. RTX 4090; check your card's SM version
```

### GPUs in containers

```nix
hardware.nvidia-container-toolkit.enable = true;
```

Then `docker run --gpus all ...`, or with Podman
`podman run --device nvidia.com/gpu=all ...`. The old
`virtualisation.docker.enableNvidia` is deprecated — do not use it.

### Hybrid laptops (PRIME)

Get the bus IDs first, and note they are **decimal** in Nix while `lspci` prints
hexadecimal:

```bash
lspci | grep -E 'VGA|3D'
```

Offload mode (iGPU drives the display, dGPU used on demand — best battery life):

```nix
hardware.nvidia.prime = {
  offload.enable = true;
  offload.enableOffloadCmd = true;            # gives you `nvidia-offload <cmd>`
  intelBusId = "PCI:0:2:0";                   # or amdgpuBusId
  nvidiaBusId = "PCI:1:0:0";
};
```

Sync mode (dGPU always on, drives everything — best performance, worst battery):

```nix
hardware.nvidia.prime.sync.enable = true;     # same two bus IDs
```

Pick one; they are mutually exclusive.

## AMD and ROCm

AMD needs no proprietary driver — `amdgpu` is in the kernel. Graphics generally
just work. **ROCm is only needed for compute** (PyTorch, Ollama, OpenCL).

```nix
{ pkgs, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # OpenCL via the ROCm runtime
  hardware.amdgpu.opencl.enable = true;

  environment.systemPackages = with pkgs; [
    rocmPackages.rocminfo          # what ROCm thinks it sees
    rocmPackages.rocm-smi          # temps, clocks, utilisation
    amdgpu_top                     # live utilisation, no ROCm required
  ];

  # Compute access requires membership in these groups
  users.users.<name>.extraGroups = [ "video" "render" ];
}
```

Verify:

```bash
rocminfo | grep -i gfx        # your GPU's gfx architecture, e.g. gfx1030
rocm-smi
```

**The single biggest ROCm trap: unsupported-but-capable cards.** AMD officially
supports a short list of GPUs. A card just outside it usually works fine once you
tell ROCm to pretend it is the nearest supported architecture:

```nix
environment.variables.HSA_OVERRIDE_GFX_VERSION = "10.3.0";   # RDNA2 consumer cards
```

The value is the gfx version with dots: `gfx1030` -> `"10.3.0"`,
`gfx1010` -> `"10.1.0"`, `gfx1100` -> `"11.0.0"`. Read your real one from
`rocminfo` and round *down* to the nearest supported family. If ROCm aborts with
"HSA_STATUS_ERROR_INVALID_ISA" or a `hipErrorNoBinaryForGpu`, this is the fix.

For Ollama specifically there is a dedicated option that sets exactly this
variable for the service only — see the `nixos-ai` skill.

ROCm-enabled packages, same trade-off as CUDA:

```nix
nixpkgs.config.rocmSupport = true;            # global; expect long rebuilds
```

Prefer the prebuilt variant (`pkgs.ollama-rocm`) or a single `.override` where
one exists.

## Intel

Usually nothing to do beyond video acceleration:

```nix
hardware.graphics = {
  enable = true;
  extraPackages = with pkgs; [
    intel-media-driver        # Broadwell (2014) and newer
    vpl-gpu-rt                # QSV on newer hardware
  ];
};
```

Older than Broadwell: use `intel-vaapi-driver` and set
`environment.variables.LIBVA_DRIVER_NAME = "i965";`.

## Troubleshooting

Work down the three layers in order. Do not skip to layer 3.

```bash
# Layer 1 — is the driver loaded?
lsmod | grep -E 'nvidia|amdgpu'
journalctl -b -k | grep -Ei 'nvidia|amdgpu|drm' | tail -40

# Layer 2 — does userspace see it?
nvidia-smi          # NVIDIA
rocminfo            # AMD
vulkaninfo --summary
nix shell nixpkgs#clinfo -c clinfo | head    # OpenCL platforms

# Layer 3 — was the application built with GPU support?
python -c 'import torch; print(torch.cuda.is_available(), torch.version.cuda)'
```

| Symptom | Cause |
|---|---|
| Black screen / Hyprland won't start after enabling NVIDIA | `modesetting.enable` not set, or `open = true` on a pre-Turing card |
| `nvidia-smi` says "couldn't communicate with the driver" | Module change not rebooted into, or driver/kernel mismatch |
| `libcuda.so.1: cannot open shared object file` | `LD_LIBRARY_PATH=/run/opengl-driver/lib` missing |
| `torch.cuda.is_available()` is `False`, driver fine | Layer 3: CPU build of PyTorch. Needs `cudaSupport` or a CUDA variant |
| `rocminfo` shows nothing | User not in `render` group, or amdgpu not loaded |
| ROCm: `invalid ISA` / `no binary for gpu` | Set `HSA_OVERRIDE_GFX_VERSION` |
| Rebuild suddenly compiles for hours | You turned on `cudaSupport`/`rocmSupport` globally. Cache does not carry these |
| Unfree licence error | `nixpkgs.config.allowUnfree = true;` |

**A driver change needs a reboot, not just `switch`.** Say so before claiming a
change did not work.

## Rules

- **Identify the hardware before writing config.** `lspci` costs nothing; a wrong
  driver branch costs a rebuild and possibly a black screen.
- **Never set `cudaSupport`/`rocmSupport` globally without warning the user**
  what it costs — hours of CPU time and a lot of disk. Offer the `.override` or
  prebuilt-variant route first.
- **Use `nixos-rebuild boot` for a risky driver change**, so a bad graphics stack
  is one reboot from recovery rather than a black screen you cannot type into.
- If the screen does go black: the previous generation is in the boot menu. That
  is the fix, and it always works.
