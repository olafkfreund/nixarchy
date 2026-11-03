---
status: approved
issue: 1577
intent: intent/2026-11-03-1577-omarchy-local-ai.md
---

# Spec: Omarchy's local model runner on nixarchy, on AMD and NVIDIA

## What upstream supports, measured

Read from omarchy-local-ai v0.4.0 (`agent_local.py`, `best.toml`, `recipes/`,
`runtimes/`), not assumed:

- **GPU detection.** `amd_gpus()` reads `/sys/class/kfd/kfd/topology/nodes`, so
  any AMD GPU that ROCm's kernel driver exposes is found, discrete or APU.
  NVIDIA is found **only** when `omarchy-hw-platform` says `aarch64-gb10` or
  `aarch64-n1x`, both unified-memory boards. **An x86_64 machine with a
  discrete NVIDIA GPU has no GPU as far as the engine is concerned**, and
  `use` stops with "No supported GPU found on this machine".
- **The catalog.** Three recipes, measured on two classes: `amd-strix-halo` at
  128 GB, and `nvidia-n1x` at 128 GB. `use best` needs an exact class
  match, and `use <recipe>` refuses an unmeasured class unless it gets
  `--unqualified`.
- **What a model container gets.** Each runtime asks for devices from a fixed
  allowlist. The gufo runtime (AMD) asks for `render`, `kfd`,
  `GroupAdd=keep-groups` and `Ulimit=memlock=-1:-1`. The tensorfold runtime
  (NVIDIA) asks for `AddDevice=nvidia.com/gpu=all`, which is a CDI device, and
  for the same memlock. `preflight()` checks that `/dev/*` devices are
  readable and writable by the user, and that `/etc/subuid` and `/etc/subgid`
  have a range for them.

The owner's machines, measured on 2026-11-03:

| host | GPU | engine sees | plumbing today |
|---|---|---|---|
| p620 | Radeon RX 7900 (`gfx1100`): 19 GiB VRAM + 125 GiB GTT, 251 GB RAM | `amd-gfx1100`, 256 GB class: no recipe | `/dev/kfd` and the render node reachable, user in `render`, memlock unlimited, Podman on |
| razer | RTX 3080 Mobile, **8 GB**, on x86_64, 62 GB RAM | no GPU | no `nvidia-ctk`, no CDI spec, memlock hard limit 8 MB, user not in `render` |

The recipes' GPU memory needs: `qwen3.8-27b-gufo` 38–40 GiB,
`nemotron-3.5-bolt-tensorfold` 54 GiB, `qwen3.8-flash-next-gufo` 89–92 GiB.
**No recipe in v0.4.0 fits an 8 GB card**, so razer stays out of reach even if
upstream starts detecting x86_64 NVIDIA. The engine counts AMD memory as VRAM
plus GTT, so p620's 144 GiB passes the 38 GiB fit check, but roughly half of
that model would live in GTT (system RAM over PCIe) and run slowly.

**nixarchy already runs local models on both owners' GPUs**, through
`programs.nixarchy.localAi` (`modules/local-ai.nix`): Ollama, with
`acceleration` picking CUDA on NVIDIA and ROCm on AMD. That path takes models
sized for the card (`qwen3:8b` is 5.2 GB, which fits razer). This spec does not
replace it. It adds the containerised engine Omarchy ships, whose catalog
targets large unified-memory machines.

So "AMD and NVIDIA in Podman" is two separate problems. **This port can make
both vendors' GPUs reachable from rootless Podman.** Which models actually run
on which GPU is decided by upstream's catalog and detection, and today neither
of the owner's machines is in it.

## Design

### 1. The engine as a package

`pkgs/apps/omarchy-local-ai.nix`, exported as `nixarchy-apps.omarchy-local-ai`:

- `fetchFromGitHub` at tag `v0.4.0`. The tree (`agent_local.py`,
  `catalog.toml`, `best.toml`, `recipes/`, `runtimes/`, `reviews/`,
  `measurements/`, `docs/`) goes to `$out/share/omarchy-local-ai`, as Arch
  installs it to `/usr/share/omarchy-local-ai`. `bench/` and `tools/` are left
  out, as upstream's README allows.
- `$out/bin/omarchy-local-ai` is a symlink to the entry script, whose shebang
  is patched to nixpkgs' `python3` (3.11 or newer). The engine resolves its
  catalog by following that symlink, so no environment variable is needed.
- **PATH is not wrapped with podman or systemctl.** Rootless Podman needs the
  system's setuid `newuidmap`, and `systemctl --user` must talk to the user's
  own manager, so both have to be the system's. `omarchy-hw-platform` and
  `omarchy-pkg-*` come from Omarchy's own `bin/`, already on PATH in the
  session.
- `checkPhase` runs upstream's `tests/engine-test.sh` (temporary home, no
  containers) and `omarchy-local-ai validate .`.
- `passthru.updateScript` (nix-update), plus a row in `pkgs/review.sh`'s pin
  list and `tests/review-pins.nix`, so the nightly review reports a new tag.
- A `data/apps.nix` row with `preinstall = true` and `arch =
  "omarchy-local-ai"`, so it ships with `programs.nixarchy.omarchyApps.enable`
  like Hype and the rest (#1572).

### 2. `programs.nixarchy.agentLocal.enable`: Podman with the GPU reachable

A new NixOS option in `modules/services/agent-local.nix`, default `false`
(Mode A). It is named after upstream's `omarchy agent local`, because
`programs.nixarchy.localAi` is already the Ollama option, and the two are
different engines that can run side by side. It does the system half:
rootless Podman, both GPU vendors, the memlock limit, and the engine package
itself, so it works whether or not `omarchyApps.enable` is on.

**Common, every vendor:**

- `virtualisation.podman.enable = lib.mkDefault true`, the same line as
  `modules/services/boxes.nix:86`. NixOS's Podman uses crun, which
  `GroupAdd=keep-groups` needs, and installs `podman-user-generator`. The
  generator was measured on p620: a unit with `/dev/kfd`,
  `nvidia.com/gpu=all`, `keep-groups`, memlock and a read-only root becomes
  the matching `podman run` flags.
- **Memlock.** Both runtimes set `Ulimit=memlock=-1:-1`, and rootless Podman
  cannot raise a limit above its parent's hard limit. On razer the user
  manager's `DefaultLimitMEMLOCK` is 8 MB, so every model container would
  fail to start. The reviews disagreed on the mechanism (see *Review*), so the
  design sets both, scoped to the one user:
  - `security.pam.loginLimits` with `{ domain = cfg.user; item = "memlock";
    type = "-"; value = "unlimited"; }`. `pam_limits` runs as root, so it can
    raise the hard limit. It covers the user manager, which logs in through
    PAM as `systemd-user`, and login or SSH shells, where the verify steps
    run.
  - `systemd.services."user@".serviceConfig.LimitMEMLOCK = "infinity"`, in
    case `systemd-user`'s PAM stack applies no limits.

  Which of the two does the work is measured, not argued: a VM check reads
  `systemctl --user show -P DefaultLimitMEMLOCK` and `ulimit -Hl` in a login
  shell, for the configured user. If one of them proves unnecessary, the plan
  drops it. A global `DefaultLimitMEMLOCK` stays rejected.
- `/etc/subuid` and `/etc/subgid`: NixOS writes ranges for normal users
  (`autoSubUidGidRange`), so nothing to add. The check asserts it.

**Both vendors, always:** `users.users.${cfg.user}.extraGroups = [ "render"
"video" ]`, a plain list so it merges with the user's own groups (§7). AMD
needs it for `/dev/kfd` and the render node (`root:render`), and NVIDIA's CDI
spec also hands the container `/dev/dri` nodes. It costs nothing, so it does
not wait on detection. `GroupAdd=keep-groups` passes the groups through to the
container.

**AMD needs nothing else.** The container image carries its own ROCm
userspace, so the host needs no ROCm packages, and `amdgpu` loads by modalias
whether or not `videoDrivers` names it. So there is no AMD detection to get
wrong. Both reviews noted that `videoDrivers` misses a Wayland-only AMD host.

**NVIDIA** turns on under exactly the condition nixpkgs' own module asserts:
`"nvidia"` in `services.xserver.videoDrivers`, or
`hardware.nvidia.datacenter.enable`. Then:

- `hardware.nvidia-container-toolkit.enable = lib.mkDefault true`. Its
  `nvidia-container-toolkit-cdi-generator` service writes
  `/var/run/cdi/nvidia-container-toolkit.json` at boot, with the Nix store
  driver mounts and `--ldconfig-path`, and that file is where
  `nvidia.com/gpu=all` resolves. Podman reads `/var/run/cdi` with no further
  configuration.
- `nvidia_uvm`, which CUDA needs and `nvidia-smi` does not, is loaded by
  nixpkgs' NVIDIA module: a `softdep nvidia post: nvidia-uvm` for the
  proprietary module, and `kernelModules` for the open one
  (`nixos/modules/hardware/video/nvidia.nix`). The verify step proves the
  device reaches the container.
- On a laptop with PRIME offload, like razer, the CDI spec covers the dGPU
  whether or not it drives the display.

**No `gpu` override enum.** The draft had one, and both reviews showed that
forcing NVIDIA without a declared driver aborts evaluation in nixpkgs'
assertion. Following the same condition as nixpkgs leaves nothing to
override. A machine with both vendors gets both, because the AMD side has no
condition.

### 3. Upstream's install-on-first-use, on NixOS

`bin/omarchy-agent-local` runs `omarchy-pkg-add podman crun` (plus
`nvidia-container-toolkit` on NVIDIA) on `use`. On NixOS that installs
nothing. The carry replaces that block with checks that run **before** the engine
downloads anything (weights are tens of GiB). Podman being present is not
enough, because `services.boxes` also turns Podman on. So `use` stops with a
message naming `programs.nixarchy.agentLocal.enable` when:

- `podman` is missing;
- the user manager's memlock limit is not `infinity`
  (`systemctl --user show -P DefaultLimitMEMLOCK`);
- on an NVIDIA machine, `/var/run/cdi` has no `nvidia.com/gpu`, which also
  catches the first switch before the boot-time generator has run.

The check for "on an NVIDIA machine" is `/proc/driver/nvidia` existing. This
patch goes in `pkgs/omarchy/`, carried on edge, because the script exists
only on quattro.

### 4. What this port does not do: models on the owner's GPUs

Neither p620 nor razer is in upstream's catalog, and razer is not detected at
all. Fixing either is a change to how Omarchy behaves, which belongs upstream
(`pkgs/omarchy/skills/nixarchy/contributing.md`): detection of discrete NVIDIA
GPUs on x86_64, and recipes measured on discrete AMD and NVIDIA cards.
Nothing gets filed upstream without the owner's say-so.

What this spec delivers on each machine:

- **p620 (AMD):** the plumbing is ready. `omarchy agent local use
  qwen3.8-27b-gufo --unqualified` can be tried. Whether gufo's
  Strix-Halo-built ROCm image runs on `gfx1100` is a question for that
  image, answered by trying it, not by this port.
- **razer (NVIDIA, 8 GB):** the plumbing is ready, and proven with the
  engine's own container flags (see Verification). The engine still says "No
  supported GPU", and no recipe in v0.4.0 would fit 8 GB if it did. For local
  models on razer today, `programs.nixarchy.localAi` (Ollama with CUDA) is the
  working path.

### 5. The ledger, on edge

`data/omarchy-packages.nix`'s `omarchy-local-ai` row changes from `skip` to
`nix = "nixarchy-apps.omarchy-local-ai"`, as an edge carry. Main's tag does not
list the package, so a row there would be stale.

## Alternatives rejected

- **Patching the engine to detect discrete NVIDIA and AMD here.** It would be
  carried at every bump, and it is upstream's catalog and security boundary
  (README: "merging catalog changes grants software publication authority").
  Upstream is the place for it.
- **Turning on ROCm or CUDA on the host.** The images carry their own
  userspace. Host ROCm or CUDA would add gigabytes to the closure and nothing
  the containers use.
- **A `localAi.gpu` override enum** (the first draft). It would let a user
  force NVIDIA with no declared driver, which aborts evaluation in nixpkgs'
  assertion. AMD needs no detection at all.
- **Naming the option `programs.nixarchy.localAi.*`.** That namespace is the
  Ollama option (`modules/local-ai.nix:70`).
- **Probing hardware at build time** (`lspci` in a derivation) to pick the
  vendor. Builds are not on the target machine, and a remote build would pick
  the builder's GPU. The machine's declared drivers are the right signal.
- **Rootful Podman or Docker for the models.** Upstream's boundary is
  rootless, with user Quadlet units, and the engine calls `systemctl --user`.
- **A global `DefaultLimitMEMLOCK=infinity`** in `systemd.extraConfig`. It
  would reach every system service, when only the user's manager needs it.

## Risks

- **Memlock** (design §2): the VM check decides which setting does the work.
  If neither works, model containers fail at start on every machine with the
  NixOS default limit, and the wrapper's check says so before any download.
- **NVIDIA CDI hooks under the engine's hardening.** The engine runs every
  container with `ReadOnly=true`, `DropCapability=all` and
  `NoNewPrivileges=true` (`agent_local.py:1149`). agy raised that the CDI
  spec's `update-ldcache` hook may need to write `/etc/ld.so.cache`. Not
  measured yet, and only real NVIDIA hardware can answer it, so the razer
  verify step runs with exactly those flags. If it fails, it is reported
  upstream, not worked around by loosening the engine's flags (intent
  constraint).
- **The CDI generator runs at boot.** After the first switch, until a reboot
  or a manual `systemctl start nvidia-container-toolkit-cdi-generator`,
  there is no CDI spec, and the preflight message has to say so.
- **The group change needs a fresh login.** `render` membership reaches the
  session only after a log out and in, so the message must say that too.
- **Coexistence (§14).** A user who already runs Podman their way, has Docker
  with `dockerCompat`, or sets `hardware.nvidia-container-toolkit` themselves.
  Everything is `mkDefault` or a merging list, and fixtures prove it.
- **Model downloads are tens of GB**, into the user's home, at the user's
  request. No build or check fetches a model.

## Coexistence

`tests/coexistence/fixtures.nix` gains:

- `podman-own-config`: the user sets `virtualisation.podman.enable = true`
  with `dockerCompat = true`. Assert it evaluates and their settings win.
- `nvidia-ctk-own`: the user sets `hardware.nvidia-container-toolkit.enable =
  false` on an NVIDIA machine. Assert theirs wins, and that the module warns
  that NVIDIA models cannot start.

## Verification

- **Package check.** Builds, `checkPhase` runs upstream's engine tests, and
  `omarchy-local-ai list` runs with a temporary home and prints the catalog.
  Proven red by deleting `recipes/` from the install: `validate` must fail.
- **`tests/options.nix` cases, both states:**
  - off: no Podman, no groups, no limits, no CDI generator from us;
  - on with `amdgpu`: `render` and `video` added, the memlock limits set, no
    CDI generator;
  - on with `nvidia` in `videoDrivers`: the same, plus the CDI generator
    service;
  - on with `hardware.nvidia.datacenter.enable`: the CDI generator.

  Each is proven red by breaking that branch.
- **Memlock, in a VM** (a case in `checks.session`, or a small VM check of its
  own if the session case would slow it): with the option on, the user
  manager's `DefaultLimitMEMLOCK` is `infinity`, and so is `ulimit -Hl` in a
  login shell. Proven red by removing each setting in turn, which also
  answers which one does the work.
- **`omarchy-package-ledger`** on edge, with the row as `nix`.
- **`pkgs/verify.sh` steps for real hardware**, run by the owner:
  - p620: `podman run --rm --device /dev/kfd --device /dev/dri --group-add
    keep-groups docker.io/rocm/rocm-terminal rocminfo` lists `gfx1100`.
  - razer: with the engine's own flags, `podman run --rm --read-only
    --cap-drop all --security-opt no-new-privileges --ulimit memlock=-1:-1
    --device nvidia.com/gpu=all <cuda base image>` runs `nvidia-smi` (shows
    the RTX 3080) and `ls /dev/nvidia-uvm`. That catches the hook and uvm
    concerns that a plain `nvidia-smi` would not.
  - Both: `ulimit -l` inside a container started with
    `--ulimit memlock=-1:-1` prints `unlimited`.
- **Not verifiable here:** a real model serving on either machine, because
  of the catalog limits in §4.

## Review

Read-only reviews of the first draft, both given the spec, the upstream
source and `modules/services/boxes.nix`:

- **codex** (gpt-6-sol)
- **agy** (model not reported)

Every claim was checked before it changed anything here.

| finding | from | verdict | change |
|---|---|---|---|
| `programs.nixarchy.localAi` already exists (Ollama) | agy | **confirmed**, `modules/local-ai.nix:70` | renamed to `agentLocal` |
| forcing `gpu = "nvidia"` without a declared driver trips nixpkgs' assertion | both | **confirmed** by codex in nixpkgs' module | enum dropped; NVIDIA follows nixpkgs' own condition |
| `videoDrivers` misses a Wayland-only AMD host | both | plausible; p620 does declare `amdgpu`, but the default does not | AMD needs no detection; groups always |
| NVIDIA's CDI spec also passes `/dev/dri`, so `render`/`video` matter there too | agy | plausible | groups for both vendors |
| memlock: `user@` `LimitMEMLOCK` alone (codex) vs PAM `loginLimits` (agy) | disagree | not measured | set both, scoped to the user; a VM check decides |
| verify step runs in a login shell, which `user@`'s limit never reaches | agy | correct by systemd's slice layout | covered by `loginLimits` |
| `nvidia-smi` does not exercise `nvidia_uvm` | agy | correct; nixpkgs loads uvm by softdep | verify checks `/dev/nvidia-uvm` in the container |
| `ReadOnly=true` may break CDI's `update-ldcache` hook | agy | unverified, hardware-only | razer verify runs the engine's exact flags; a Risk |
| a Podman from `boxes` passes the wrapper's check, then fails after the download | agy | **confirmed** by reading `cmd_use`'s order | the wrapper checks memlock and CDI before `use` |
| `localAi.enable` without `omarchyApps` would lack the engine | agy | correct | `agentLocal.enable` installs the engine itself |
| `--unqualified` on p620 is rejected by the fit check | codex | **refuted**: AMD memory is VRAM + GTT, 144 GiB passes 38 | spec now says it fits but runs mostly from GTT |
| no entry script: `agent_local.py` has no shebang | agy | **refuted**: upstream ships `omarchy-local-ai` at the repo root | none |
| upstream cannot detect x86_64 NVIDIA; no recipe for `gfx1100`/256 | both | **confirmed** | as written |
