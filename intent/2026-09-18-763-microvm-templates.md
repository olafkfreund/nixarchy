---
status: approved
issue: 763
author: olafkfreund
---

# Intent: MicroVM templates for k3s, agent-claude and node, and enough memory for podman

## Problem

`data/microvm-templates.nix` has five templates: shell, python, podman,
agent and persistent. Three common uses have no template, and one of the
existing templates barely works.

- **Kubernetes.** There is no template for it. The owner maintains a k3s
  MicroVM flake by hand in the host config
  (`hosts/p620/microvm/flake.nix` in nixos_config). That flake hard-codes a
  token and passwords, and nixarchy does not build or check it.
- **A coding agent in a fenced sandbox.** `agent` has the egress allowlist
  (tinyproxy, an nftables default-drop, hosts listed in `allow-hosts`), but
  it ships no agent. You have to install one yourself inside a guest whose
  root filesystem is thrown away at every boot, and through a proxy that
  refuses everything you have not listed.
- **Node.** `python` has no JavaScript counterpart.
- **podman is starved.** `modules/microvm/templates/podman.nix` sets no
  `microvm.mem`, and `modules/microvm/guest.nix` sets none either, so the
  guest runs on microvm.nix's default of 512 MiB (`options.nix:110` in the
  pinned input). An image pull or a build runs out of memory in a VM whose
  whole point is containers.

## Proposed outcome

- `nixarchy vm templates` lists three new templates, and each one boots:
  - **`k3s`:** a single-node k3s server with `/var/lib/rancher` on a volume,
    so the cluster survives a restart, and `kubectl` working inside the
    guest.
  - **`agent-claude`:** `agent`'s egress fence, plus coding agents
    preinstalled. Their API hosts are allowed by default; everything else
    still goes through `allow-hosts`.
  - **`node`:** `nodejs` and `pnpm`, with the same shape and memory story as
    `python`.
- `podman` gets enough memory for real image pulls and builds.
- Each new template appears in the nixarchy.microvm plugin's create form
  with no plugin change, because the form reads `nixarchy vm templates`.
  Each is also usable as `programs.nixarchy.services.microvm.machines.<n>.template`.
- The catalogue notes say what each template gives and what it costs,
  following the house style.

## Affected users and systems

- **This repo:**
  - `data/microvm-templates.nix`;
  - `modules/microvm/templates/` (three new files, one edited);
  - the flake's `microvm-<name>` and `-tcg` runners, which are generated
    per catalogue entry, so the new entries add six runners;
  - `checks.microvm-template`, CI build time, and the binary cache (#697's
    5 GB free-tier budget);
  - the microvm docs page.
- **Every nixarchy user** who runs `nixarchy vm` or declares a permanent VM.
  Existing VMs are unaffected, except that a podman VM gets more memory on
  its next run.
- The owner's hand-kept k3s flake can be retired later, in a separate
  nixos_config change.

## Constraints

- **The catalogue's bar still holds.** A template is exactly a NixOS module:
  no nixarchy vocabulary, and nothing that depends on a per-VM value,
  because one runner serves every VM named from it.
- **No secret in a template.** k3s must not ship a fixed token or password.
  Any token has to be generated inside the guest at first boot.
- **agent-claude keeps agent's guarantee:** nothing reaches the network
  except through the proxy. Adding the agents' API hosts is the only
  loosening.
- **Unfree software.** `claude-code` is unfree. nixarchy must not
  redistribute it through its public binary cache, and a user without
  `allowUnfree` must still get a working catalogue, not an evaluation
  error.
- **Cache budget.** Six new runners must fit #697's budget, or be kept out
  of the cache the way other large outputs are.
- **Checks.** Every new runner is built by the checks that build the
  existing ones.

## Open questions

1. **Which agents go into `agent-claude`?** Proposal:
   - `codex` (Apache-2.0) and `opencode` (MIT) are built into the runner.
   - `claude-code`, which is unfree, is installed only when the host allows
     unfree. That runner stays out of the public cache and is built locally.

   Alternatives: ship only free agents under a neutral name such as
   `coding-agent`, or require unfree for the whole template.
2. **The allowlist default.** Proposal: `api.anthropic.com`,
   `api.openai.com`, `github.com` and `codeload.github.com` are allowed
   without being listed, and `allow-hosts` adds to them. Or should the
   template ship with nothing allowed until the user lists hosts, as `agent`
   does today?
3. **k3s resources.** Proposal: 4 GiB of RAM, 2 vCPUs, and a 20 GiB
   `/var/lib/rancher` volume. Traefik and servicelb are disabled, as in the
   hand-kept flake. Should the API port be reachable from the host, which
   only a permanent VM's forwarded ports can do, or is kubectl inside the
   guest enough for v1?
4. **podman memory.** Proposal: 4 GiB. python gets 3 GiB for less work.
   Would 2 GiB be enough?
5. **The name.** `agent-claude` as asked, or `coding-agent` if the claude
   part turns out to need unfree (question 1)?
