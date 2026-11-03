---
status: approved
issue: 1577
author: olafkfreund
---

# Intent: Omarchy's local model runner on nixarchy

## Problem

Omarchy's quattro branch (edge, from `a69b19f`) adds `omarchy-local-ai` to
`install/omarchy-base.packages`. That makes it a default package, installed
on every machine. It is the engine behind `omarchy agent local …` and the
agents panel's local models:

- **What it is.** A Python 3.11 engine (`agent_local.py`) with a catalog of
  recipes, runtimes, reviews and measurements, from
  [omacom/omarchy-local-ai](https://github.com/omacom/omarchy-local-ai), v0.4.0.
  Arch installs the tree to `/usr/share/omarchy-local-ai` and links
  `/usr/bin/omarchy-local-ai`.
- **How models run.** Each model runs as a rootless Podman model server
  generated through Podman Quadlet: an internal network, a read-only root,
  allowlisted devices, and loopback endpoints with authentication.
- **What upstream installs on demand.** `bin/omarchy-agent-local` runs
  `omarchy-pkg-add podman crun`, plus `nvidia-container-toolkit` on NVIDIA
  machines, the first time a model is set up. On NixOS that call can install
  nothing.

nixarchy has no package for it. On edge, `omarchy agent local` finds no
command, and the agents panel has no list of models that fit the machine. The
package ledger from #1572 caught this. Its row is a `skip` that names this
issue, so the gap is recorded but still open.

## Proposed outcome

1. **The engine is a package.** `omarchy-local-ai` builds as
   `nixarchy-apps.omarchy-local-ai`, with its catalog beside it, and
   `omarchy agent local list` works on edge.
2. **Models can run.** Podman, crun and (on NVIDIA) the container toolkit's
   CDI come from NixOS options, not `omarchy-pkg-add`. `omarchy agent local use
   <recipe>` starts a model server on a machine that turned this on.
3. **The ledger row changes from `skip` to `nix`**, and #1577 closes.

## Affected users and systems

- Everyone on edge, and on main once a tagged Omarchy release lists the
  package.
- `pkgs/apps/`, the flake overlay, `data/omarchy-packages.nix`,
  `data/bin-ledger.nix` if `omarchy-agent-local` needs a different row there,
  and a NixOS module for the Podman side.
- p620 (AMD) and razer (NVIDIA): the two GPU paths the owner can test on.

## Constraints

- **Mode A.** Podman and the NVIDIA container toolkit are system services. A
  machine that imports the module and did not ask for them must not get them.
  The engine itself is small and could follow `omarchyApps.enable`.
- **The engine's security boundary is upstream's.** It pins images by digest
  and drops capabilities. The port must not loosen any of that to make it run,
  for example by turning off the read-only root.
- **Weights are large and downloaded at run time** into
  `~/.local/share/omarchy/agent-local`. Nothing here may fetch a model during
  a build or a check.
- **§1 and §2.** A check that fails if the command or its catalog goes
  missing, proven red. Running a real model is out of reach for CI, so that
  part is a `pkgs/verify.sh` step on real hardware.
- **A user's own Podman config wins (§14).** A machine that already sets
  `virtualisation.podman` or Docker's compatibility socket needs a
  coexistence fixture.

## Open questions

1. **Does the engine ship with `omarchyApps.enable`, or behind its own
   option?** Upstream installs it everywhere, but without Podman it can only
   list models.
   - My proposal: the engine ships with `omarchyApps.enable`. A separate
     `programs.nixarchy.localAi.enable` turns on Podman, plus the NVIDIA CDI
     when the machine has NVIDIA.
2. **Quadlet on NixOS.** The engine writes Quadlet units and expects
   Podman's user generator to turn them into services. Whether NixOS's
   `virtualisation.podman` wires that generator for user units has to be
   measured, not assumed. The spec answers it.
3. **Is upstream's install-time `omarchy-pkg-add` patched out, or left to
   fail?** On NixOS it runs and installs nothing. My proposal: patch the
   wrapper to check for the commands and point at the option instead,
   carried on edge until a tagged release lists the package.
