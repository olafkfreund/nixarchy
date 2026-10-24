---
status: approved
issue: 1432
spec: spec/2026-10-24-1432-nixi-track-master-companion.md
---

# Plan: Track nixi master and ship the snowflake companion

## Approved decisions (from the spec, so this file stands alone)

- **nixi tracks `master`.** nixarchy's `nixi` input loses its commit:
  `github:olafkfreund/nixi-nixarchy`, with no ref.
  - Both `follows` (`nixpkgs`, `omarchy`) stay.
  - The lock is the pin.
  - This reverses the documented "never track a branch" rule, by the user's decision (#1432).
- **The companion tracks `main`.** New input `nixi-companion =
  github:olafkfreund/nixoarchy-snowflake` with `inputs.nixpkgs.follows = "nixpkgs"`. The
  fork has no CI, so its risk is accepted for machines that turn it on.
- **nixarchy defaults the package:**
  - `services.nixi.companion.package = lib.mkDefault inputs.nixi-companion.packages.${system}.default`;
  - `enable` stays `false`, so a machine that doesn't turn it on gets no closure change;
  - nixi re-overrides the package with its bridge (`hm-module.nix:27`).
- **Docs:** a short paragraph in `docs/manual/ai.md` under "Nixi, on SUPER + H".
- **p620:**
  - `services.nixi.companion.enable = true`;
  - a Nix-written `~/.config/hypr/nixi-companion-binds.lua` with SUPER+ALT+H (`nixi-companion`)
    and SUPER+ALT+J (`nixi-companion listen`);
  - one `pcall(require, "hypr.nixi-companion-binds")` line in the user-owned `bindings.lua`.
- **Not in scope:**
  - a nixarchy CI check that builds the companion;
  - nixarchy writing anyone's bindings;
  - a user unit that autostarts the companion.
- **The p620 rebuild is the user's to run.**

### Added since the spec: how "update brings the latest" actually works

Nix takes an input's own inputs from **that input's** `flake.lock`. So dropping the rev in
nixarchy's `flake.nix` is not enough for p620. `nix flake update nixarchy` in the config would
still get whatever nixi commit nixarchy's lock holds, and nothing updates that lock
automatically (`flake-update.yml` updates `nixpkgs` only). To make the user's own
`nix flake update` move nixi and the companion, the config declares both inputs itself and has
nixarchy follow them. It does this the same way it already does `inputs.sops-nix.follows`
(`~/.config/nixos/flake.nix:67-80`).

- nixarchy's lock is still bumped in this PR, so other nixarchy users get current nixi. It then
  moves whenever someone runs `nix flake update nixi` there. This plan does not change CI
  (`AGENTS.md` §11).
- **What the user runs from now on:** `nix flake update` (or `nix flake update nixi nixi-companion`)
  in `~/.config/nixos`, then a rebuild.

## Who does what

The plan edits 7 files across 2 repos, so P1–P4 go to one `coder` agent and each later step is
sent to it with `SendMessage`. The lead reviews and commits each step, does P5–P7 (the config
and the hand-off), and runs the fresh Opus review (P8).

## Steps

**P1. nixi follows master** (nixarchy worktree `/mnt/code/Source-home/GitHub/nixarchy-1432`)
- `flake.nix:261`: change the `url` to `"github:olafkfreund/nixi-nixarchy"`. Keep lines 262–263.
- `flake.nix:144-259`, the comment above the input (about 116 lines of pin history):
  - Under `AGENTS.md` §7, "long blocks move, they do not get deleted", move it to
    `docs/internals/flake.md` as a new `## nixi` section.
  - In that section, rewrite the "Pinned to a COMMIT … never track a branch" paragraph into the
    #1432 decision:
    - nixi tracks master;
    - the lock is the pin;
    - `nix flake update nixi` moves it;
    - nixi's master needs 5 green checks.
  - Keep the pin-by-pin history below it as history.
  - Leave in `flake.nix` at most 3 lines plus `# Why: docs/internals/flake.md#nixi`, the form
    `sops-nix` uses at `flake.nix:~132`.
- Lock: `nix flake update nixi`. Expect a rev ≥ `39af9e3`.
- Verify:
  - `nix flake metadata --json | jq -r '.locks.nodes.nixi.locked.rev'`;
  - `nix build .#nixi --no-link`;
  - `nix build .#checks.x86_64-linux.menu-model-merge --no-link`.
- Traps:
  - Don't touch any other input's pin.
  - In docs/internals/flake.md, the existing nixi mentions (~441, ~703) stay. Link the new
    section from them only if it reads naturally.

**P2. The companion input** (`flake.nix`, directly after the `nixi` input ~264)
- Add the input, with a 1–3 line comment: it's not in nixpkgs; it tracks `main` like nixi;
  the fork has no CI and is built only where `services.nixi.companion.enable` is on.
  ```nix
  nixi-companion = {
    url = "github:olafkfreund/nixoarchy-snowflake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```
- `nix flake lock` adds the node (no other node moves). Check with
  `git diff flake.lock | grep '"rev"'`: only `nixi` and `nixi-companion` revs change (P1+P2).
- Verify: `nix eval .#inputs` doesn't apply. Use
  `nix flake metadata --json | jq '.locks.nodes."nixi-companion".locked'`.
- Trap: the `outputs` function must accept the new input. Check whether it destructures inputs
  or takes `inputs@{ ... }` (it uses `inputs.nixi`, so `...` probably covers it). Confirm it.

**P3. Default the package** (`modules/home.nix`, the `services.nixi` block, ~875–881)
- Inside `nixi = { … }` after `package = …;`:
  ```nix
  # Off unless the user enables it; nixi pins its bridge into this package.
  companion.package = lib.mkDefault
    inputs.nixi-companion.packages.${pkgs.stdenv.hostPlatform.system}.default;
  ```
- `mkDefault` on a scalar (a package) is the house rule (`AGENTS.md` §7).
- Verify (from nixarchy):
  - `nix eval .#nixosConfigurations.vm.config.home-manager.users.omarchy.services.nixi.companion.package.name`
    prints a `nixi-companion-…` name;
  - `…services.nixi.companion.enable` is `false`;
  - `nix flake check` passes (at least `--no-build`, then the full check if time allows).
  - With companion off, `home.packages` has no companion: `nix eval …home.packages --apply 'ps: builtins.any (p: (p.pname or "") == "nixi-companion") ps'` returns `false`.
- Trap: `tests/options.nix` asserts option states. Run it, or the checks that include it.

**P4. Docs** (`docs/manual/ai.md`, at the end of "## Nixi, on SUPER + H", before line 283)
- 4–8 lines covering:
  - the snowflake companion: it listens and talks, and asks only through Nixi's bridge, so it
    follows Guide/Mechanic;
  - it's off by default;
  - turning it on: `services.nixi.companion.enable = true;` in Home Manager;
  - the two example `o.bind` lines;
  - a link to nixi's README section for what it leaves out.
- Verify: the repo's docs/link lint, if one runs in `nix flake check`. Otherwise read it.

**P1–P4 results (2026-10-24, the `coder` agent; reviewed and committed by the lead):**
- **P1:** as planned. The lock is at `39af9e3`. The `# Why:` line follows the 2-line note instead of
  leading it. The lead fixed one stale phrase in the moved text ("hyprland above").
- **P2/P3:** as planned. `nixi-companion` is locked at `09af56c`, and no other node moved.
  Evals: `companion.package` is `nixi-companion-0.1.0`, `enable` is `false`, and there is no
  companion in `home.packages`. `checks.options` builds, and `nix flake check --no-build` passes
  on the committed tree.
  The lead also built the VM config with `companion.enable = true`: `nixi-companion-0.1.0` builds
  and carries nixi's `nixi-node` and `bridge.js` store paths.
- **P4:** 18 lines instead of 4–8, because of the two code blocks.

**P5. The PR and merge** (lead)
- Push, then `gh pr create`:
  - fill in the template;
  - link intent, spec and plan;
  - list which steps the coder did.
- `AGENTS.md` §8: the final commit subject must be a sentence, with no conventional prefix.
  The squash uses the PR title, so make the title that sentence: "nixi follows its master
  branch, and the snowflake companion ships with nixarchy, off by default (#1432)".
- Merge once CI is green, then dispatch `omarchy-edge.yml` once (`gh workflow run
  omarchy-edge.yml`) so `edge` carries it today.
- Verify: `git -C … fetch && git merge-base --is-ancestor <merge> origin/edge`.

**P6. The config** (`~/.config/nixos`, lead; a working branch there, committed, not pushed unless
the user says)
- `flake.nix` `inputs` (~38), next to `nixarchy`:
  ```nix
  # Followed by nixarchy, so this config's `nix flake update` moves nixi itself (#1432).
  nixi = {
    url = "github:olafkfreund/nixi-nixarchy";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.omarchy.follows = "nixarchy/omarchy";
  };
  nixi-companion = {
    url = "github:olafkfreund/nixoarchy-snowflake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  ```
  and in the `nixarchy` block (~67–80): `inputs.nixi.follows = "nixi";` and
  `inputs.nixi-companion.follows = "nixi-companion";`.
- `hosts/p620/nixos/nixarchy.nix:169-172`, inside `services.nixi`: `companion.enable = true;`.
- In the same file's `home-manager.users.olafkfreund` (~134), write the binds file:
  ```nix
  home.file.".config/hypr/nixi-companion-binds.lua".text = ''
    -- Managed by hosts/p620/nixos/nixarchy.nix; edits are overwritten on rebuild.
    o.bind("SUPER + ALT + H", "Nixi companion: show or hide", "nixi-companion")
    o.bind("SUPER + ALT + J", "Nixi companion: listen", "nixi-companion listen")
  '';
  ```
  Copy the `o.bind` form from the existing `~/.config/hypr/ai-mirror-binds.lua`.
- Lock: `nix flake update nixarchy nixi nixi-companion` once P5's merge is on `edge`.
- Verify:
  - `nix build .#nixosConfigurations.p620.config.system.build.toplevel --no-link`;
  - `nix flake metadata --json | jq -r '.locks.nodes.nixi.locked.rev'` shows nixi master;
  - only one `nixi` node in the lock (the follows took).
- Traps:
  - `~/.config/nixos` is 3 commits behind `origin/main`. Pull first (fast-forward only), and stop
    and ask if it doesn't fast-forward.
  - Don't run `nixos-rebuild`.
  - A host that doesn't import nixarchy must still evaluate, because the inputs are only
    declared. Eval razer and p510 toplevels too
    (`nix eval .#nixosConfigurations.<h>.config.system.build.toplevel.drvPath`).

**P7. `bindings.lua` and the hand-off** (lead)
- `~/.config/hypr/bindings.lua` is user-owned, not managed by Nix. Append next to the other
  `pcall(require, …)` lines (~225, after `ai-mirror-binds`):
  ```lua
  -- Nixi companion (SUPER + ALT + H / J). Written by hosts/p620/nixos/nixarchy.nix.
  pcall(require, "hypr.nixi-companion-binds")
  ```
- Back up first, the way the file's own `.bak.*` copies are kept.
- Give the user the rebuild command and the live checks (Tests, below).

**P8. Review (lead):** a fresh Opus agent, given only this plan path and the nixarchy and config
diffs. Fix what's confirmed and record it here.

## Tests

| Command | Expected |
|---|---|
| `nix flake metadata` (nixarchy) | `nixi` URL has no rev, locked ≥ `39af9e3`; `nixi-companion` locked at fork `main` |
| `nix flake check` (nixarchy) and PR CI | green |
| VM eval, companion off | `companion.enable == false`, no `nixi-companion` in `home.packages` |
| p620 toplevel build (config) | builds |
| razer, p510 toplevel eval (config) | evaluates |
| **User, after rebuild:** `which nixi-companion`; SUPER+ALT+H; `hyprctl binds \| grep -i nixi-companion`; `pgrep -af claude` | on PATH; snowflake shows; two binds; `claude-agent-acp` under nixi's bridge, no `claude -p` |
| **Later:** `nix flake update` in the config | moves `nixi` and `nixi-companion` with no file edit |

## Rollback

- **nixarchy:** revert the merge (the URL gets its rev back; the companion input and default go).
- **Config:**
  - revert the commit;
  - delete the `pcall` line in `bindings.lua` (harmless if left: `pcall` ignores a missing file);
  - rebuild, or roll back with `nixos-rebuild switch --rollback`.
